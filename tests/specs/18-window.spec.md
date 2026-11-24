# The board in a window
@weight 2

chess/tui's view, what a window draws, and its square key, what a click
or a piece let go on a square does; chess/gui, the picture drawn from
the view and what is at a point of it.  chess/window, the loop over a
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
(write (list (gui-at 0 96 100) (gui-at 8 96 100) (gui-at 0 735 690) (gui-at 0 10 10)))
```
---
```output
(('square 112) ('square 7) ('key "n") ())
```

### the squares drawn in their colours

```chess
(def st (tui-make ()))
(import gfx/canvas)
(def g (gui-make))
(gui-draw! g (tui-view st) (Vector of -1 -1 -1 ()))
(def c (gui-canvas g))
(write (list (first c) (first (rest c)) (Canvas pixel c 96 500) (Canvas pixel c 96 420)))
```
---
```output
(1180 760 (122 149 113 255) (234 226 206 255))
```
