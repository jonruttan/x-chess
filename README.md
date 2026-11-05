# x-chess

A chess engine on x-lang, as a lang bundle: a game against the engine
at the terminal, and the Universal Chess Interface for chess GUIs and
other engines.

    x -l chess -- [--white|--black|--both] [--fen FEN] [--time SECONDS] [--depth N] [--think] [--engine CMD] [--line] [--letters]
                  [--book FILE|--no-book]
    x -l chess -- --uci
    x -l chess -- --perft N [--fen FEN]
    x -l chess -- --match GAMES [--engine CMD [--engine CMD]] [--time SECONDS] [--depth N] [--fen FEN]
    x -l chess -- --tables

On a terminal it is a game on a board that fills the screen: you play
white unless you say otherwise, and the engine answers each move.
`--line` plays it a line at a time instead.  Fed lines, it speaks UCI
when the first line is `uci`, as a GUI expects of an engine it starts,
and otherwise plays the lines as moves and commands.  With no operands
`x -l chess` is the lang's REPL, with the engine's functions in reach.

## The board

The squares are as large as the terminal allows (7 by 3 cells from 86
by 29, 5 by 2 from 70 by 21, 3 by 1 down to 52 by 14).  Beside the board
a bar shows who stands better; to the right are the engine's thinking,
each depth's score and line as it finishes, and the moves, the last one
marked.  The last move's squares are yellowed, a king in check is red.

A move is typed (SAN or long algebraic, then Enter), or made with the
mouse, a click on the piece then on its square, or with the arrows and
Enter; a piece picked up shows where it can go.  A pawn reaching the
last rank asks for its piece.  The keys that cannot begin a move are
commands:

    u        take back your move and the engine's reply
    n        a new game
    v        turn the board
    w        play the other side
    i        a hint, its squares marked
    m        the engine moves now: it stops thinking, or plays for you
    l        analyse: the engine thinks until a key is pressed, and both
             sides are yours
    t        show or hide the thinking
    [ ]      back and forward through the game; Home, End
    p        letters or figures for the pieces (also --letters)
    ?        the keys
    q        quit

and `:` takes a command: `fen FEN`, `time S`, `depth N`, `engine CMD`,
`save FILE` (the game as PGN), `white`, `black`, `both`, `new`.

## Playing a line at a time

A move is SAN (`e4`, `Nf3`, `exd5`, `O-O`, `e8=Q`) or long algebraic
(`e2e4`, `e7e8q`).  Anything else is a command:

    go             the engine plays the side to move; you take the other
    white, black   play that side against the engine
    both           play both sides; go asks the engine for one move
    undo           take back your last move (and the engine's reply)
    new            a new game
    fen [FEN]      show the position as FEN, or set it up
    moves          the legal moves
    pgn            the moves of the game
    hint           the move the engine would play
    time SECONDS   how long the engine thinks (5 s)
    depth N        how deep it looks at most
    board, flip    show the board, turn it around
    think          show the engine's thinking as it goes, or stop showing it
    engine [CMD]   play a UCI engine, CMD its program and arguments, or
                   x-chess again; alone, name the engine played
    help, quit

A game ends at checkmate, stalemate, the fifty-move rule, threefold
repetition, or when neither side has the material to mate.

## Other engines

Any program that speaks UCI can take x-chess's place: `--engine
stockfish` plays a game against Stockfish, `engine stockfish` switches
to it during one, and `--think` (or `think`) shows each depth's score
and line as the engine finishes it, whichever engine it is.  The
command is split at spaces, so arguments may follow the program.

`--match GAMES` plays games between two engines, x-chess against the
one `--engine` names, or the two named; each takes white in turn.  The
games go to standard output as PGN, and a line for each game and the
score to standard error:

    x -l chess -- --match 10 --engine stockfish --time 1 > games.pgn

A game still going after 600 plies is a draw, and an engine that gives
no move loses.  x-chess opens a match game from its book, so the games
differ, and uses the endgame tables only when they are already built.

## UCI

`uci`, `isready`, `setoption`, `ucinewgame`, `position startpos|fen
FEN [moves ...]`, `go` with `depth`, `nodes`, `movetime`, `wtime`/
`btime`/`winc`/`binc`/`movestogo` or `infinite`, `stop` and `quit`;
and two that are not the protocol's but most engines have: `d` shows
the board and its FEN, `go perft N` counts the move paths N plies
deep, each first move's count then the total.  While it thinks it
reads `stop`, `quit` and `isready`.

Two options: `OwnBook` (off; a GUI usually keeps the book) plays from a
book before searching, `BookFile` names a Polyglot book for it, empty
for the built-in one.  `--book FILE` on the command line sets both.  A
book move is answered with `info string book move`.

## Openings

Before it searches, the engine plays from a book when the book knows
the position, a move drawn at random by its weight, so its games vary.

- The built-in book is 29 main lines written by hand, 10 to 16 plies
  each: the Ruy Lopez and its Berlin, the Italian, the Scotch, the
  Petrov, the Sicilian's Najdorf, Classical, Taimanov and Alapin, the
  French, the Caro-Kann, the Scandinavian, the Pirc, the Queen's Gambit
  declined and accepted, the Slav, the Nimzo- and Queen's Indian, the
  King's Indian, the Grünfeld, the Benoni, the Dutch, the London, the
  English and the Réti.  A position's moves are weighted by how many
  lines play them there, so 1. e4 comes 16 times in 29.  It is laid
  out at the first move asked of it, in about 3 s of processor time.
- `--book FILE` plays from a Polyglot `.bin` book, the format most
  opening books come in, and `--no-book` from none.  The file is
  binary-searched for the position's key, a 64-bit Zobrist hash over
  Polyglot's 781 published numbers.  They are held as four 16-bit limbs
  each, so the hash is the same on an engine of any word width.

## Endgame tables

King and queen, king and rook, and king and pawn against a lone king
are played exactly, from tables of every position's distance to mate
that the engine builds itself by retrograde analysis: no Syzygy files,
nothing from outside.  The search looks a position up as soon as it has
those men alone, and the engine's own move there is the table's
fastest mate, or longest defence.

The queen mates in at most 10 moves and the rook in 16, the published
figures; the pawn, by way of promotion, in 28.

Building the three takes about 190 s of processor time on an Apple
M-series machine: 52 s for the queen, 48 for the rook, 89 for the pawn,
which needs the other two for its promotions.  So they are built once
and kept: in `$X_CHESS_TABLES`, else `$XDG_CACHE_HOME/x-chess`, else
`~/.cache/x-chess`, 352 KB in all.

    x -l chess -- --tables     # build them now, and say how long it took

A game played a line at a time (`--line`, or fed moves) builds them the
first time it reaches one of those endings, and says so first.  The
board, a match and UCI never stop to build them: they use them when
they are on disk.

## The engine

- The board is 0x88, held in one Vector whose slots are read and
  written with the obj doors; a move is an integer, and making one
  allocates a single pair, the record unmaking needs.
- Moves are generated pseudo-legally; a move is refused when it leaves
  its own king attacked, and outside check only a king move, an en
  passant capture or a move off the line to its king can.
- perft matches the published counts for the start, Kiwipete and the
  chessprogramming wiki's positions 3 to 6.
- The search is negamax with alpha-beta, iteratively deepened, with a
  quiescence search of captures that leaves out a capture which could
  not reach alpha with two pawns to spare; it tries the last
  iteration's best move first, then captures by most valuable victim
  and least valuable attacker, then two killer moves a ply.  A side in
  check looks a ply further.  A clock or node limit holds from the
  first ply: stopped before any move is searched, it plays the first
  legal one.  Each ply keeps the line that raised alpha there, so a
  finished depth reports the whole line it expects, not only its move.
- The evaluation is Tomasz Michniewski's Simplified Evaluation Function,
  material and piece-square tables with a middle-game and an end-game
  king, blended by phase and kept up to date as pieces move.
- x collects only when asked; the search collects every 2048 nodes.

It searches 600 to 1,000 nodes a second on an Apple M-series machine:
four plies from the start in about three seconds, three in a quiet
middle game in five, and one or two where captures abound.

## Install

    make install          # into <share>/langs/chess, where x -l looks
    make test             # the spec suite
    make check            # the suite against tests/contract/known-failures.txt

`lang.xon` declares the x-lang release the bundle needs.

## Licence

MIT No Attribution (MIT-0).
