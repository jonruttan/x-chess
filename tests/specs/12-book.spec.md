# Opening books
@weight 1

chess/book: the moves the engine plays before it searches.  A book is
builtin, the main lines the bundle carries, or the path of a Polyglot
.bin file; () is none.

## Polyglot keys

### the keys Polyglot's format description gives for its test positions

```chess
(def key-after
  (fn (_ ms)
    (def q (pos-from-fen fen-start))
    (List for-each (fn (_ t) (make! q (move-parse-uci q t))) ms)
    (polyglot-hex (polyglot-key q))))
(List for-each (fn (_ ms) (display (key-after ms)) (display "\n"))
  (list () (list "e2e4") (list "e2e4" "d7d5") (list "e2e4" "d7d5" "e4e5") (list "e2e4" "d7d5" "e4e5" "f7f5")
        (list "e2e4" "d7d5" "e4e5" "f7f5" "e1e2") (list "e2e4" "d7d5" "e4e5" "f7f5" "e1e2" "e8f7")
        (list "a2a4" "b7b5" "h2h4" "b5b4" "c2c4") (list "a2a4" "b7b5" "h2h4" "b5b4" "c2c4" "b4c3" "a1a3")))
```
---
```output
463b96181691fc9c
823c9b50fd114196
0756b94461c50fb0
662fafb965db29d4
22a48b5a8e47ff78
652a607ca3f242c1
00fdd303c946bdd9
3c8123ea7b067637
5c3f9b829b279560
```

## a Polyglot file

A book is written here entry by entry: the key's four limbs, the move,
the weight, all big-endian.  Polyglot's move is the to square, then the
from square, 6 bits each, then the promotion.

### a position's moves with their weights; one not legal there is left out

```chess
(import x/sys/file)
(import x/core/doors str-make str->ptr ptr-set! int>> int&)
(def write-book
  (fn (_ path entries)
    (def n (List length entries))
    (def buf (str-make (* 16 n)))
    (def p (str->ptr buf))
    (def put (fn (_ i b) (ptr-set! p i b 1)))
    (def put16 (fn (_ i v) (put i (int>> v 8)) (put (+ i 1) (int& v 255))))
    (List for-each
      (fn (_ k)
        (def e (List ref k entries))
        (def at (* k 16))
        (List for-each (fn (_ j) (put16 (+ at (* j 2)) (List ref j (first e)))) (list 0 1 2 3))
        (put16 (+ at 8) (List ref 1 e))
        (put16 (+ at 10) (List ref 2 e))
        (put16 (+ at 12) 0)
        (put16 (+ at 14) 0))
      (List range 0 n))
    (def fd (File open path (list (lit wronly) (lit creat) (lit trunc))))
    (File write fd buf (* 16 n))
    (File close fd)
    path))
(def start (pos-from-fen fen-start))
(def after-e4 (pos-from-fen "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"))
(def shown (fn (_ es) (List map (fn (_ e) (pair (move-uci (first e)) (rest e))) es)))
(def book
  (write-book "/tmp/x-chess-spec-book.bin"
    (list (list (list 0 0 0 1) 796 9)
          (list (polyglot-key start) 796 3)
          (list (polyglot-key start) 731 1)
          (list (polyglot-key start) 983 0)
          (list (polyglot-key start) 804 5)
          (list (polyglot-key after-e4) 3234 1)
          (list (list 65535 65535 65535 65535) 796 9))))

(write (list (shown (book-moves book start)) (shown (book-moves book after-e4))
             (book-moves book (pos-from-fen "4k3/8/8/8/8/8/8/4K3 w - - 0 1"))))
```
---
    ((("e2e4" . 3) ("d2d4" . 1) ("h2h3" . 0)) (("c7c5" . 1)) ())

### a move is drawn by weight, and a move of weight 0 never

```chess
(write (List map (fn (_ r) (move-uci (book-pick book start (fn (_ n) r)))) (list 0 1 2 3)))
```
---
    ("e2e4" "e2e4" "e2e4" "d2d4")

### castling is written as the king taking its rook

```chess
(def castles (pos-from-fen "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
(write (shown (book-moves (write-book "/tmp/x-chess-spec-book.bin" (list (list (polyglot-key castles) 263 2) (list (polyglot-key castles) 256 1))) castles)))
```
---
    (("e1g1" . 2) ("e1c1" . 1))

## the built-in book

### the first moves, weighted by how many lines play them

```chess
(write (shown (book-moves (lit builtin) (pos-from-fen fen-start))))
```
---
    (("g1f3" . 1) ("c2c4" . 2) ("d2d4" . 10) ("e2e4" . 16))

### and a few moves in, by transposition or not; out of the lines it has none

```chess
(def after (fn (_ ms) (def q (pos-from-fen fen-start)) (List for-each (fn (_ t) (make! q (move-parse-uci q t))) ms) q))
(write (list (shown (book-moves (lit builtin) (after (list "e2e4" "e7e5" "g1f3" "b8c6"))))
             (shown (book-moves (lit builtin) (after (list "d2d4" "g8f6" "c2c4" "e7e6"))))
             (book-moves (lit builtin) (after (list "a2a3")))))
```
---
    ((("d2d4" . 1) ("f1c4" . 2) ("f1b5" . 2)) (("g1f3" . 1) ("b1c3" . 1)) ())

### the engine's move from a book is reported as depth 0, unsearched

```chess
(def r (best-move (pos-from-fen fen-start) (lit builtin) 3 0 0 (fn (_) #f) (fn (_ r) ())))
(write (list (List ref 0 r) (List ref 2 r) (if (List any? (fn (_ m) (str=? m (move-uci (List ref 4 r)))) (list "e2e4" "d2d4" "c2c4" "g1f3")) #t #f)))
```
---
    (0 0 #t)

### with no book, or none for the position, it searches

```chess
(def r1 (best-move (pos-from-fen fen-start) () 2 0 0 (fn (_) #f) (fn (_ r) ())))
(def r2 (best-move (pos-from-fen "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1") (lit builtin) 2 0 0 (fn (_) #f) (fn (_ r) ())))
(write (list (first r1) (move-uci (List ref 4 r2)) (mate-in (List ref 1 r2))))
```
---
    (2 "a1a8" 1)

### a book that cannot be read leaves the search to it

```chess
(def r (best-move (pos-from-fen "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1") "/nonexistent/book.bin" 2 0 0 (fn (_) #f) (fn (_ r) ())))
(write (move-uci (List ref 4 r)))
```
---
    "a1a8"
