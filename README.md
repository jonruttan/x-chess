# x-chess

A chess engine on x-lang, as a lang bundle: a game against the engine
at the terminal, and the Universal Chess Interface for chess GUIs and
other engines.

    x -l chess -- [--white|--black|--both] [--fen FEN] [--time SECONDS] [--depth N] [--think] [--engine CMD] [--line] [--letters] [--coach]
    x -l chess -- --puzzle | --puzzles FILE
    x -l chess -- --uci
    x -l chess -- --perft N [--fen FEN]
    x -l chess -- --match GAMES [--engine CMD [--engine CMD]] [--time SECONDS] [--depth N] [--fen FEN]

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
    z        puzzles (below)
    j        the coach, on or off (below)
    [ ]      back and forward through the game; Home, End
    p        letters or figures for the pieces (also --letters)
    ?        the keys
    q        quit

and `:` takes a command: `fen FEN`, `time S`, `depth N`, `engine CMD`,
`save FILE` (the game as PGN), `white`, `black`, `both`, `new`,
`puzzle [FILE]`, `coach`.

## Puzzles

`--puzzle`, `z` on the board, or `:puzzle` sets the puzzles made for
x-chess, mates in one and two; `--puzzles FILE` or `:puzzle FILE` sets
those of FILE, a CSV in the form of the lichess puzzle database
(<https://database.lichess.org/#puzzles>), read a block at a time as
the puzzles are asked for.  You play the side to move.  A right move is
answered with the solution's reply; a move that mates where the
solution mates is right too.  In a puzzle, `i` marks the solution's
next move, `m` makes it for you, `z` goes on to the next puzzle and `n`
leaves the puzzles for a new game.  A puzzle counts as solved when it
was solved with no wrong move, hint or move shown.

## The coach

`--coach`, `j` or `:coach` has the engine judge your moves.  When the
engine moves, the second move of its line is the reply it expects of
you, and its score the one it expects to see when it next moves.  Its
next score, less that, is what your move cost: from 0.70 of a pawn an
inaccuracy, from 1.50 a mistake, from 3 a blunder, and the move it
expected is named.

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
no move loses.

## UCI

`uci`, `isready`, `ucinewgame`, `position startpos|fen FEN [moves ...]`,
`go` with `depth`, `nodes`, `movetime`, `wtime`/`btime`/`winc`/`binc`/
`movestogo` or `infinite`, `stop` and `quit`; and two that are not the
protocol's but most engines have: `d` shows the board and its FEN, `go
perft N` counts the move paths N plies deep, each first move's count
then the total.  While it thinks it reads `stop`, `quit` and `isready`.

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
