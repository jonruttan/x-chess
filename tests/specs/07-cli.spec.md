# The command line
@weight 1

chess/cli: the options, and what is answered without a game.

## options

### flags and values, a value that is not a number, an unknown option

```chess
(write (list (chess-options (list "--black" "--time" "3" "--depth" "4" "--fen" "8/8/8/8/8/8/8/K6k w - -") ())
             (chess-options (list "--time" "x") ())
             (chess-options (list "--depth") ())
             (chess-options (list "--zap") ())))
```
---
    ((('fen . "8/8/8/8/8/8/8/K6k w - -") ('depth . 4) ('seconds . 3) ('side . 'black)) (('error . "--time takes a number of seconds")) (('error . "--depth takes a number of plies")) (('error . "no such option: --zap")))

### --book takes a file, --no-book none, --tables builds the endgame tables

```chess
(write (list (chess-options (list "--book" "openings.bin") ())
             (chess-options (list "--no-book" "--tables") ())
             (chess-options (list "--book") ())))
```
---
    ((('book . "openings.bin")) (('tables . #t) ('book . 'none)) (('error . "--book takes a Polyglot file")))

### --board takes a theme's name

```chess
(write (list (chess-options (list "--board" "ascii") ())
             (chess-options (list "--board" "zap") ())
             (chess-options (list "--board") ())))
```
---
    ((('board . "ascii")) (('error . "--board takes one of wood, green, blue, grey, ascii")) (('error . "--board takes one of wood, green, blue, grey, ascii")))

### --unsolved passes over the solved, --random sets the puzzles in a random order, --one one of them

```chess
(write (list (chess-options (list "--puzzle" "--unsolved" "--random") ())
             (chess-options (list "--puzzles" "p.csv" "--one") ())))
```
---
    ((('order . 'random) ('skip . #t) ('puzzle . #t)) (('order . 'one) ('puzzles . "p.csv")))

### a book that is not there is refused before play

```chess
(write (chess-main (list "--book" "/nonexistent/book.bin")))
```
---
    2


## answered without a game

### --version and --perft write their answer and succeed

```chess
(def a (chess-main (list "--version")))
(def b (chess-main (list "--perft" "2" "--fen" "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")))
(write (list a b))
```
---
```output
x-chess 0.1.0
2039
(0 0)
```
