# The board in a window
@weight 2

chess/tui's view, what a window draws, and its square key, what a click
or a piece let go on a square does; chess/gui, the picture drawn from
the view and what is at a point of it: a square, a button, a move in
the list, a row or a pill of a box.  chess/window, the loop over a
window's events, needs a window and is not run here.

## the square key

### a click on a piece and then on its square plays the move

```chess
(def st (tui-make (list (pair (lit side) (lit both)))))
(tui-key! st (list (lit square) 20))
(tui-key! st (list (lit square) 52))
(write (move-uci (rest (Assoc find (lit last) (tui-view st)))))
```
---
```output
"e2e4"
```

### a piece picked up: the view has its square and where it can go

```chess
(def st (tui-make (list (pair (lit side) (lit both)))))
(List for-each (fn (_ sq) (tui-key! st (list (lit square) sq))) (list 20 52 100 68))
(tui-key! st (list (lit square) 5))
(def v (tui-view st))
(write (list (sq-name (rest (Assoc find (lit sel) v))) (List map sq-name (rest (Assoc find (lit targets) v)))))
```
---
```output
("f1" ("a6" "b5" "c4" "d3" "e2"))
```

### a promotion: the picker's squares down the file, a click on one chooses

```chess
(def st (tui-make (list (pair (lit side) (lit both)) (pair (lit fen) "8/1P6/8/8/8/8/6k1/4K3 w - - 0 1"))))
(tui-key! st (list (lit square) 97))
(tui-key! st (list (lit square) 113))
(write (List map (fn (_ c) (list (sq-name (first c)) (rest c))) (rest (Assoc find (lit promo) (tui-view st)))))
(tui-key! st (list (lit square) 81))
(write (move-uci (rest (Assoc find (lit last) (tui-view st)))))
```
---
```output
(("b8" 5) ("b7" 4) ("b6" 3) ("b5" 2))"b7b8b"
```

## the view

### the strips: who plays each side, whose move, what each has taken

```chess
(def st (tui-make (list (pair (lit side) (lit white)) (pair (lit fen) "4k3/8/8/8/8/8/8/R3K3 w - - 0 1"))))
(write (List map (fn (_ s) (list (List ref 1 s) (List ref 2 s) (List ref 3 s) (List ref 4 s)))
  (rest (Assoc find (lit strips) (tui-view st)))))
```
---
```output
((8 #f () -5) (0 #t () 5))
```

## the picture

### a point of the picture: a square as the board is seen, a button, or nothing

```chess
(def g (gui-make 1))
(def white (tui-view (tui-make ())))
(def black (tui-view (tui-make (list (pair (lit side) (lit black))))))
(write (list (gui-at g white 96 100) (gui-at g black 96 100) (gui-at g white 735 690) (gui-at g white 10 10)))
```
---
```output
(('square 112) ('square 7) ('key "n") ())
```

### a move in the list is a key that looks back at it; the steps go back and forward

```chess
(def g (gui-make 1))
(def st (tui-make (list (pair (lit side) (lit both)))))
(List for-each (fn (_ sq) (tui-key! st (list (lit square) sq))) (list 20 52 100 68 6 37))
(def v (tui-view st))
(write (list (gui-at g v 820 250) (gui-at g v 920 250) (gui-at g v 820 270) (gui-at g v 1000 230) (gui-at g v 1120 230)))
(tui-key! st (List ref 1 (gui-at g v 920 250)))
(write (rest (Assoc find (lit ply) (tui-view st))))
(tui-key! st "[")
(write (rest (Assoc find (lit ply) (tui-view st))))
(tui-key! st (lit end))
(write (rest (Assoc find (lit review) (tui-view st))))
```
---
```output
(('key ('ply 1)) ('key ('ply 2)) ('key ('ply 3)) ('key 'home) ('key 'end))21-1
```

### the choice of puzzles: a row is its key, the arrows step the rating, outside closes it

```chess
(def g (gui-make 1))
(def st (tui-make ()))
(tui-key! st "z")
(def v (tui-view st))
(write (list (gui-at g v 590 190) (gui-at g v 590 465) (gui-at g v 743 156) (gui-at g v 590 145) (gui-at g v 100 100)))
(tui-key! st (List ref 1 (gui-at g v 743 156)))
(write (first (first (rest (Assoc find (lit choice) (tui-view st))))))
(tui-key! st (List ref 1 (gui-at g v 100 100)))
(write (rest (Assoc find (lit choice) (tui-view st))))
```
---
```output
(('key "1") ('key "x") ('key ">") ('box) ('key 'escape))"Puzzles, rated below 1000"()
```

### the settings: the side you play, the engine's time, the toggles; another key closes them

```chess
(def st (tui-make ()))
(tui-key! st ",")
(def pills (fn (_) (List map (fn (_ it) (List map (fn (_ p) (list (first p) (List ref 2 p))) (List ref 3 it))) (rest (Assoc find (lit choice) (tui-view st))))))
(List for-each (fn (_ k) (tui-key! st k)) (list "b" "2" "j"))
(write (List reject null? (pills)))
(write (list (tui-ms st) (rest (Assoc find (lit view) (tui-view st)))))
(tui-key! st "q")
(write (list (rest (Assoc find (lit choice) (tui-view st))) (tui-quit? st)))
```
---
```output
((("White" #f) ("Black" #t) ("Both" #f)) (("1 s" #f) ("2 s" #t) ("5 s" #f) ("10 s" #f)) (("Turn" #f)) (("on" #t)) (("on" #t)) (("off" #f)) (("off" #f)))(2000 8)(() #f)
```

### the game's end has buttons: a new game, a move taken back

```chess
(def g (gui-make 1))
(def st (tui-make (list (pair (lit side) (lit both)))))
(List for-each (fn (_ sq) (tui-key! st (list (lit square) sq))) (list 21 37 100 84 22 54 115 55))
(def v (tui-view st))
(write (list (rest (Assoc find (lit over) v)) (gui-at g v 310 390) (gui-at g v 440 390)))
```
---
```output
("Black wins by checkmate" ('key "n") ('key "u"))
```

### the squares drawn in their colours

```chess
(def st (tui-make ()))
(import gfx/canvas)
(def g (gui-make 1))
(gui-draw! g (tui-view st) (Vector of -1 -1 -1 ()))
(def c (gui-canvas g))
(write (list (first c) (first (rest c)) (Canvas pixel c 96 500) (Canvas pixel c 96 420)))
```
---
```output
(1180 760 (122 149 113 255) (234 226 206 255))
```

### drawn at 2, the picture is twice as wide and high, and a point of it is read at 1

```chess
(def st (tui-make ()))
(import gfx/canvas)
(def g (gui-make 2))
(def v (tui-view st))
(gui-draw! g v (Vector of -1 -1 -1 ()))
(def c (gui-canvas g))
(write (list (gui-scale g) (first c) (first (rest c)) (Canvas pixel c 192 1000) (Canvas pixel c 192 840) (gui-at g v 96 100)))
```
---
```output
(2 2360 1520 (122 149 113 255) (234 226 206 255) ('square 112))
```

### a frame puts back only what the last drew over the still, and is the same as one drawn whole

```chess
(import gfx/canvas)
(def st (tui-make (list (pair (lit side) (lit both)))))
(List for-each (fn (_ sq) (tui-key! st (list (lit square) sq))) (list 21 37 100 84 22 54 115 55))
(def v (tui-view st))
(def a (gui-make 1))
(gui-draw! a v (Vector of 300 390 -1 ()))
(def lit-new (Canvas pixel (gui-canvas a) 260 392))
(gui-draw! a v (Vector of 820 250 -1 ()))
(def settle (fn (_ g) (let go ((n 0)) (when (if (< n 40) (gui-draw! g v (Vector of 100 100 -1 ())) #f) (go (+ n 1))))))
(settle a)
(def b (gui-make 1))
(settle b)
(def ca (gui-canvas a))
(def cb (gui-canvas b))
(write (list (equal? lit-new (Canvas pixel cb 260 392)) (equal? (List ref 2 ca) (List ref 2 cb))))
```
---
```output
(#f #t)
```

### a box opened, changed for another and closed: each frame is the one drawn whole

```chess
(import gfx/canvas)
(def st (tui-make (list (pair (lit side) (lit both)))))
(def a (gui-make 1))
(def same-as-whole
  (fn (_ ui)
    (def v (tui-view st))
    (gui-draw! a v ui)
    (def b (gui-make 1))
    (gui-draw! b v ui)
    (equal? (List ref 2 (gui-canvas a)) (List ref 2 (gui-canvas b)))))
(write (list
  (same-as-whole (Vector of 920 250 -1 ()))
  (do (tui-key! st "z") (same-as-whole (Vector of 590 250 -1 ())))
  (do (tui-key! st (lit escape)) (tui-key! st ",") (same-as-whole (Vector of 640 340 -1 ())))
  (do (tui-key! st (lit escape)) (same-as-whole (Vector of 920 250 -1 ())))))
```
---
```output
(#t #t #t #t)
```

### the pointer over one button then another, and a move that lets the game step back: each frame is the one drawn whole

```chess
(import gfx/canvas)
(def st (tui-make (list (pair (lit side) (lit both)))))
(def a (gui-make 1))
(def same-as-whole
  (fn (_ ui)
    (def v (tui-view st))
    (gui-draw! a v ui)
    (def b (gui-make 1))
    (gui-draw! b v ui)
    (equal? (List ref 2 (gui-canvas a)) (List ref 2 (gui-canvas b)))))
(write (list
  (same-as-whole (Vector of 300 300 -1 ()))
  (same-as-whole (Vector of 885 731 -1 ()))
  (same-as-whole (Vector of 996 731 -1 ()))
  (do (tui-key! st (list (lit square) 20)) (tui-key! st (list (lit square) 52)) (same-as-whole (Vector of 300 300 -1 ())))
  (same-as-whole (Vector of 885 731 -1 ()))))
```
---
```output
(#t #t #t #t #t)
```
