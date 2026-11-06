# The board
@weight 1

chess/board: FEN in and out, squares and moves as text, and the move
generator, checked by perft against the published counts.

## FEN

### the start reads and writes back

```chess
(write (pos-fen (pos-from-fen fen-start)))
```
---
    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

### the move counters may be left off

```chess
(write (pos-fen (pos-from-fen "4k3/8/8/8/8/8/8/4K2R b K e3")))
```
---
    "4k3/8/8/8/8/8/8/4K2R b K e3 0 1"

### what does not read says why

```chess
(write (List map (fn (_ f) (guard (e (e msg)) (pos-from-fen f)))
  (list "8/8/8/8/8/8/8/8 w - - 0 1"
        "4k3/8/8/8/8/8/8/4K3 x - - 0 1"
        "4k3/8/8/8/8/8/8/4K2 w - - 0 1"
        "4k3/8/8/8/8/8/8 w - - 0 1"
        "4k3/8/8/8/8/8/8/4K3 w KZ - 0 1"
        "P3k3/8/8/8/8/8/8/4K3 w - - 0 1"
        "4k3/8/8/8/8/8/8/4K3 w")))
```
---
    ("bad FEN: each side needs one king" "bad FEN: the side is not w or b" "bad FEN: a rank is not 8 squares" "bad FEN: the board is not 8 ranks of 8" "bad FEN: castling is not KQkq or -" "bad FEN: a pawn on the first or last rank" "bad FEN: fewer than 4 fields")

## squares and moves

### names, both ways

```chess
(write (list (sq-name 0) (sq-name 7) (sq-name 116) (sq-parse "e4" 0) (sq-parse "i9" 0)))
```
---
    ("a1" "h1" "e8" 52 -1)

### long algebraic, a promotion with its letter

```chess
(write (List map move-uci (legal-moves (pos-from-fen "4k3/1P6/8/8/8/8/8/4K3 w - - 0 1"))))
```
---
    ("b7b8q" "b7b8r" "b7b8b" "b7b8n" "e1f2" "e1d2" "e1e2" "e1d1" "e1f1")

## making and unmaking

### every move from Kiwipete made and taken back leaves it as it was

```chess
(def p (pos-from-fen "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"))
(def before (list (pos-fen p) (pos-middle p) (pos-end p) (pos-phase p)))
(write (List all? (fn (_ m) (if (make! p m) (unmake! p m) ()) (equal? before (list (pos-fen p) (pos-middle p) (pos-end p) (pos-phase p))))
  (gen-moves p #f)))
```
---
    #t

### castling moves the rook, and a king move loses both rights

```chess
(def p (pos-from-fen "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
(make! p (move-parse-uci p "e1g1"))
(write (pos-fen p))
```
---
    "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1"

### a rook taken in its corner takes that right with it

```chess
(def p (pos-from-fen "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
(make! p (move-parse-uci p "a1a8"))
(write (pos-fen p))
```
---
    "R3k2r/8/8/8/8/8/8/4K2R b Kk - 0 1"

### a double step leaves en passant open, and the capture takes the pawn

```chess
(def p (pos-from-fen "4k3/8/8/8/3p4/8/4P3/4K3 w - - 0 1"))
(make! p (move-parse-uci p "e2e4"))
(def after-double (pos-fen p))
(make! p (move-parse-uci p "d4e3"))
(write (list after-double (pos-fen p)))
```
---
    ("4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1" "4k3/8/8/8/8/4p3/8/4K3 w - - 0 2")

### a pinned piece may not leave the line of the pin

```chess
(write (List map move-uci (legal-moves (pos-from-fen "4k3/4r3/8/8/8/8/4N3/4K3 w - - 0 1"))))
```
---
    ("e1f2" "e1d2" "e1d1" "e1f1")

## perft

The published counts: the start, Kiwipete and the chessprogramming
wiki's positions 3 to 6.

### the start, three plies

```chess
(write (List map (fn (_ d) (perft (pos-from-fen fen-start) d)) (list 1 2 3)))
```
---
    (20 400 8902)

### Kiwipete

```chess
(write (List map (fn (_ d) (perft (pos-from-fen "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1") d)) (list 1 2)))
```
---
    (48 2039)

### positions 3 to 6, two plies

```chess
(write (List map (fn (_ f) (perft (pos-from-fen f) 2))
  (list "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
        "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
        "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"
        "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10")))
```
---
    (191 264 1486 2079)

### position 3, four plies: en passant and pins along the rank

```chess
(write (perft (pos-from-fen "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1") 3))
```
---
    2812

## the hash

### the same position by two orders of moves, from its FEN, and after each legal move made and unmade

```chess
(def h (fn (_ p) (pair (pos-hash-lo p) (pos-hash-hi p))))
(def hash=? (fn (_ a b) (if (= (first a) (first b)) (= (rest a) (rest b)) #f)))
(def played (fn (_ fen ts) ((fn (_ p) (List for-each (fn (_ t) (make! p (move-parse-uci p t))) ts) p) (pos-from-fen fen))))
(def a (played fen-start (list "g1f3" "g8f6" "b1c3")))
(def b (played fen-start (list "b1c3" "g8f6" "g1f3")))
; each legal move: the hash made is the hash of the FEN made, and unmade is the hash before
(def unkept
  (fn (_ fen)
    (def p (pos-from-fen fen))
    (def before (h p))
    (List length
      (List filter
        (fn (_ m)
          (make! p m)
          (def made (hash=? (h p) (h (pos-from-fen (pos-fen p)))))
          (unmake! p m)
          (if made (not (hash=? (h p) before)) #t))
        (legal-moves p)))))
(write (list (hash=? (h a) (h b)) (hash=? (h a) (h (pos-from-fen (pos-fen a))))
             (hash=? (h (pos-from-fen fen-start)) (h (pos-from-fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1")))
             (hash=? (h (pos-from-fen fen-start)) (h (pos-from-fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w Kkq - 0 1")))
             (unkept fen-start)
             (unkept "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
             (unkept "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1")
             (unkept "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8")
             (unkept "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")))
```
---
    (#t #t #f #f 0 0 0 0 0)
