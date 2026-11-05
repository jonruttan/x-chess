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
