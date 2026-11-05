# Endgame tables
@weight 3

chess/tables: king and queen, king and rook, and king and pawn against
a lone king, solved by retrograde analysis.  A probe answers N + 1 for
a win in N plies from the side to move's view, -(N + 1) for a loss,
0 for a draw, and () for a position the tables do not hold.  The
tables are built here in memory, kept in no file.

## building

### all three, in a time this machine can wait for

```chess
(def times (tables-build! ()))
(write (list (tables-loaded? ) (List all? (fn (_ us) (< us 600000000)) times)))
```
---
    (#t #t)

## probing

### a mate in one; a lone king mated; the stronger side black; a check with the wrong side to move is no position

```chess
(write (List map (fn (_ f) (table-probe (pos-from-fen f)))
  (list "k7/8/1K6/8/8/8/8/6Q1 w - - 0 1"
        "k6Q/8/1K6/8/8/8/8/8 b - - 0 1"
        "8/8/8/8/8/1k6/8/K6q w - - 0 1"
        "7q/8/8/8/8/8/8/k1K5 w - - 0 1"
        "8/8/8/8/8/8/8/K1k4R w - - 0 1"
        "8/8/8/8/8/8/8/K1k4R b - - 0 1")))
```
---
    (2 -1 -1 -13 0 -23)

### king and pawn: the opposition decides, a king on the sixth before its pawn wins, a rook pawn draws, a pawn outruns a king

```chess
(write (List map (fn (_ f) (table-probe (pos-from-fen f)))
  (list "8/4k3/8/4K3/4P3/8/8/8 w - - 0 1"
        "8/4k3/8/4K3/4P3/8/8/8 b - - 0 1"
        "4k3/8/4K3/4P3/8/8/8/8 w - - 0 1"
        "4k3/8/4K3/4P3/8/8/8/8 b - - 0 1"
        "k7/8/8/8/8/8/P7/K7 w - - 0 1"
        "8/8/8/8/8/k7/7P/K7 w - - 0 1")))
```
---
    (0 -29 22 -25 0 28)

### what the tables do not hold, and what needs none

```chess
(write (List map (fn (_ f) (table-probe (pos-from-fen f)))
  (list fen-start
        "4k3/8/8/8/8/8/8/R3K3 w Q - 0 1"
        "4k3/8/8/8/8/8/8/2B1K3 w - - 0 1"
        "4k3/8/8/8/8/8/8/4K3 w - - 0 1"
        "4k3/8/8/8/8/8/8/RR2K3 w - - 0 1")))
```
---
    (() () 0 0 ())

## playing

### the engine plays the tables' fastest mate, and says it is mate

```chess
(def r (best-move (pos-from-fen "k7/8/1K6/8/8/8/8/6Q1 w - - 0 1") () 3 0 0 (fn (_) #f) (fn (_ r) ())))
(write (list (move-uci (List ref 4 r)) (mate-in (List ref 1 r))))
```
---
    ("g1g8" 1)

### the longest wins, in moves, and the positions won: the queen mates in at most 10, the rook 16

```chess
(import x/core/doors int/)
(write (List map (fn (_ t) (list (int/ (+ (first t) 1) 2) (List ref 1 t))) (tables-longest)))
```
---
    ((10 18081) (16 21959) (28 62480))
