# x-chess

A chess engine on x-lang, as a lang bundle: a game against the engine
at the terminal, and the Universal Chess Interface for chess GUIs and
other engines.

    x -l chess -- [--white|--black|--both] [--fen FEN] [--time SECONDS] [--depth N]
    x -l chess -- --uci
    x -l chess -- --perft N [--fen FEN]

On a terminal it is a game: you play white unless you say otherwise,
and the engine answers each move.  Fed lines instead, it speaks UCI
when the first line is `uci`, as a GUI expects of an engine it starts,
and otherwise plays the lines as moves and commands.  With no operands
`x -l chess` is the lang's REPL, with the engine's functions in reach.

## Playing

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
    help, quit

A game ends at checkmate, stalemate, the fifty-move rule, threefold
repetition, or when neither side has the material to mate.

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
  legal one.
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
