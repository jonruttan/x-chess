# The search
@weight 1

chess/search: the evaluation, and the move alpha-beta chooses.  A report
is (depth score nodes microseconds move), the score from the side to
move's view in centipawns.

## evaluation

### level at the start, and the same seen from either side

```chess
(write (list (evaluate (pos-from-fen fen-start))
             (evaluate (pos-from-fen "4k3/8/8/8/8/8/8/R3K3 w - - 0 1"))
             (evaluate (pos-from-fen "4k3/8/8/8/8/8/8/R3K3 b - - 0 1"))
             (evaluate (pos-from-fen "r3k3/8/8/8/8/8/8/4K3 b - - 0 1"))))
```
---
    (0 500 -500 500)

## choosing

### a mate in one is found and scored as mate

```chess
(def r (search-best (pos-from-fen "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1") 2 0 0 (fn (_) #f) (fn (_ r) ())))
(write (list (move-uci (List ref 4 r)) (List ref 1 r) (mate-score? (List ref 1 r)) (mate-in (List ref 1 r))))
```
---
    ("a1a8" 29999 #t 1)

### a queen left hanging is taken

```chess
(def r (search-best (pos-from-fen "rnb1kbnr/pppp1ppp/8/4p1q1/3P4/2N5/PPP1PPPP/R1BQKBNR w KQkq - 0 1") 3 0 0 (fn (_) #f) (fn (_ r) ())))
(write (list (move-uci (List ref 4 r)) (< 800 (List ref 1 r))))
```
---
    ("c1g5" #t)

### each finished depth is reported, deepest last

```chess
(def seen ())
(def r (search-best (pos-from-fen fen-start) 3 0 0 (fn (_) #f) (fn (_ r) (set! seen (pair (first r) seen)))))
(write (list (List reverse seen) (first r)))
```
---
    ((1 2 3) 3)

### a node limit or the poll stops it at its first look past the first depth

```chess
(def by-nodes (search-best (pos-from-fen fen-start) 20 0 50 (fn (_) #f) (fn (_ r) ())))
(def by-poll (search-best (pos-from-fen fen-start) 20 0 0 (fn (_) #t) (fn (_ r) ())))
(write (list (< (first by-nodes) 20) (first by-poll)))
```
---
    (#t 2)

### no legal move, no report

```chess
(write (search-best (pos-from-fen "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1") 2 0 0 (fn (_) #f) (fn (_ r) ())))
```
---
    ()
