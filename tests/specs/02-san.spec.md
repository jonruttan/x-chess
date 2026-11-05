# Algebraic notation
@weight 1

chess/san: writing a move as SAN from the position before it, and
reading SAN or long algebraic back.

## writing

### pieces, pawns and the start

```chess
(def p (pos-from-fen fen-start))
(write (List map (fn (_ t) (move-san p (move-parse-uci p t))) (list "g1f3" "e2e4" "b1c3")))
```
---
    ("Nf3" "e4" "Nc3")

### two knights for one square: the file tells them apart

```chess
(def p (pos-from-fen "4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1"))
(write (List map (fn (_ t) (move-san p (move-parse-uci p t))) (list "b1d2" "f3d2" "f3e5")))
```
---
    ("Nbd2" "Nfd2" "Ne5")

### two rooks on one file: the rank does

```chess
(def p (pos-from-fen "4k3/8/8/R7/8/8/8/R3K3 w - - 0 1"))
(write (List map (fn (_ t) (move-san p (move-parse-uci p t))) (list "a1a3" "a5a3" "a5a8")))
```
---
    ("R1a3" "R5a3" "Ra8+")

### castling, en passant, promotion, check and mate

```chess
(write (list
  ((fn (_ p) (List map (fn (_ t) (move-san p (move-parse-uci p t))) (list "e1g1" "e1c1")))
   (pos-from-fen "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
  ((fn (_ p) (move-san p (move-parse-uci p "e5d6"))) (pos-from-fen "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1"))
  ((fn (_ p) (List map (fn (_ t) (move-san p (move-parse-uci p t))) (list "b7b8q" "b7a8n")))
   (pos-from-fen "r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1"))
  ((fn (_ p) (move-san p (move-parse-uci p "d8h4"))) (pos-from-fen "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2"))))
```
---
    (("O-O" "O-O-O") "exd6" ("b8=Q+" "bxa8=N") "Qh4#")

### a game's moves, made in turn

```chess
(def p (pos-from-fen fen-start))
(write (list (moves-san p (List map (fn (_ t) (move-make (sq-parse t 0) (sq-parse t 2) 0 0)) (list "e2e3" "e7e6" "g1f3")))
             (pos-fen p)))
```
---
    (("e3" "e6" "Nf3") "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

## reading

### SAN, with or without its marks, castling with zeros, and long algebraic

```chess
(def p (pos-from-fen "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
(write (List map (fn (_ t) ((fn (_ m) (if (null? m) () (move-uci m))) (move-parse p t)))
  (list "O-O" "0-0-0" "Rxa8+" "Rxa8" "Rb1!?" "e1f1" "E1F1" "Kd3" "")))
```
---
    ("e1g1" "e1c1" "a1a8" "a1a8" "a1b1" "e1f1" "e1f1" () ())

### a move that needs telling apart reads only as SAN writes it

```chess
(def p (pos-from-fen "4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1"))
(write (List map (fn (_ t) ((fn (_ m) (if (null? m) () (move-uci m))) (move-parse p t))) (list "Nd2" "Nbd2" "N1d2")))
```
---
    (() "b1d2" ())
