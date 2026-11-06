# The board on a whole terminal
@weight 2

chess/tui: the state the board interface keeps, what a key does to it,
and what is drawn.  Each case presses keys, draws on a screen of a given
size and reads rows of it back.  A mouse press is (mouse BUTTON COL ROW
PRESS?), the columns and rows counted from 1 as a terminal reports them.

## drawing

### the start on 100 by 30: squares of 7 by 3, the panel, the strips and the keys

```chess
(def st (tui-make ()))
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 0 2 23 25 26 29)))
```
---
```output
   ●  x-chess (Black)                                         Playing x-chess · 5 s a move
8    ♜      ♞      ♝      ♛      ♚      ♝      ♞      ♜       Thinking
1    ♜      ♞      ♝      ♛      ♚      ♝      ♞      ♜
     a      b      c      d      e      f      g      h
   ○  You (White)
type or click a move · u back · v turn · i hint · m move now · l analyse · z puzzles · ? keys · q qu
```

### a smaller terminal takes squares of 3 by 1, letters drawn with p

```chess
(def st (tui-make ()))
(def s (Screen make 16 60))
(tui-key! st "p")
(spec-draw! st s)
(display (spec-rows s (list 1 8 9)))
```
---
```output
8  R  N  B  Q  K  B  N  R
1  R  N  B  Q  K  B  N  R
   a  b  c  d  e  f  g  h
```

### too small a terminal says so

```chess
(def s (Screen make 10 40))
(spec-draw! (tui-make ()) s)
(display (spec-rows s (list 0)))
```
---
```output
Too small: x-chess needs 52 by 14.
```

### from black's side the board is turned, a8 at the bottom right

```chess
(def st (tui-make (list (pair (lit side) (lit black)))))
(def s (Screen make 16 60))
(tui-key! st "p")
(spec-draw! st s)
(display (spec-rows s (list 1 8 9)))
```
---
```output
1  R  N  B  K  Q  B  N  R
8  R  N  B  K  Q  B  N  R
   h  g  f  e  d  c  b  a
```

## themes

### wood, the default: the pieces bold, white's white and black's black, on their squares

```chess
(def st (tui-make ()))
(def s (Screen make 30 100))
(spec-draw! st s)
(def at (fn (_ r c) (Screen style-at s r c)))
(write (list (Style has? (at 23 33) (lit bold)) (Style has? (at 2 33) (lit bold))
             (Style fg (at 23 33)) (Style fg (at 2 33)) (Style bg (at 23 33)) (Style bg (at 2 33))))
```
---
    (#t #t 231 16 137 180)

### green, blue and grey: the same pieces on squares of their own

```chess
(def colours
  (fn (_ name)
    (def s (Screen make 30 100))
    (spec-draw! (tui-make (list (pair (lit board) name))) s)
    (list (Style fg (Screen style-at s 23 33)) (Style bg (Screen style-at s 23 33)) (Style bg (Screen style-at s 2 33)))))
(write (List map colours (list "green" "blue" "grey")))
```
---
    ((231 65 108) (231 67 110) (231 242 248))

### ascii: letters, black's in lower case, the dark squares dotted, no colour

```chess
(def st (tui-make (list (pair (lit board) "ascii"))))
(spec-keys! st (list "e" "4" (lit enter)))
(def s (Screen make 16 60))
(spec-draw! st s)
(display (spec-rows s (list 0 1 2 5 6 7 8 9 10)))
(newline)
(write (list (Style has? (Screen style-at s 8 15) (lit bold)) (Style fg (Screen style-at s 8 15)) (Style bg (Screen style-at s 8 15))))
```
---
```output
   B  x-chess (Black)         Playing x-chess | 5 s a move
8  r .n. b .q. k .b. n .r. :
7 .p. p .p. p .p. p .p. p  :  Thinking
4    ...   ...-P-...   ...
3 ...   ...   ...   ...
2  P .P. P .P.---.P. P .P.    Moves
1 .R. N .B. Q .K. B .N. R       1. e4
   a  b  c  d  e  f  g  h
   W  You (White)
(#t () ())
```

### ascii: a piece picked up is reversed, the squares it can go to starred

```chess
(def st (tui-make (list (pair (lit board) "ascii"))))
(def s (Screen make 16 60))
(spec-draw! st s)
(tui-key! st (list (lit mouse) 0 16 8 #t))
(spec-draw! st s)
(display (spec-rows s (list 5 6 7)))
(newline)
(write (list (Style has? (Screen style-at s 7 15) (lit reverse)) (Style has? (Screen style-at s 6 15) (lit reverse))))
```
---
```output
4    ...   ... * ...   ...
3 ...   ...   .*.   ...
2  P .P. P .P. P .P. P .P.    Moves
(#t #f)
```

### :board steps through the themes; :board NAME picks one; a name it does not know is said

```chess
(def st (tui-make ()))
(def s (Screen make 30 100))
(def said
  (fn (_ keys)
    (spec-keys! st (List append (list ":") keys (list (lit enter))))
    (spec-draw! st s)
    (spec-rows s (list 28))))
(write (list (said (list "b" "o" "a" "r" "d"))
             (said (list "b" "o" "a" "r" "d" " " "a" "s" "c" "i" "i"))
             (said (list "b" "o" "a" "r" "d"))
             (said (list "b" "o" "a" "r" "d" " " "z" "a" "p"))))
```
---
    ("The green board." "The ascii board." "The wood board." "No such board: zap.  They are wood, green, blue, grey, ascii.")

## moves

### typed: e4, then a move that is not legal here

```chess
(def st (tui-make ()))
(spec-keys! st (list "e" "4" (lit enter)))
(def after-e4 (spec-moves st))
(tui-engine-played! st (move-parse (game-pos (tui-game st)) "e5"))
(spec-keys! st (list "N" "f" "6" (lit enter)))
(write (list after-e4 (spec-moves st) (tui-engine-to-move? st)))
(newline)
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 28)))
```
---
```output
(("e2e4") ("e2e4" "e7e5") #f)
Not a legal move here: Nf6
```

### clicked: the knight on g1, then f3; the engine is then to move

```chess
(def st (tui-make ()))
(def s (Screen make 30 100))
(spec-draw! st s)
(tui-key! st (list (lit mouse) 0 45 23 #t))
(tui-key! st (list (lit mouse) 0 38 17 #t))
(write (list (spec-moves st) (tui-engine-to-move? st)))
```
---
    (("g1f3") #t)

### the arrows and Enter: up from e1 to e2, pick up, up twice, put down

```chess
(def st (tui-make ()))
(spec-keys! st (list (lit up) (lit enter) (lit up) (lit up) (lit enter)))
(write (spec-moves st))
```
---
    ("e2e4")

### a pawn put down on the last rank asks for its piece: n makes a knight

```chess
(def st (tui-make (list (pair (lit fen) "8/4P3/8/8/8/8/k7/4K3 w - - 0 1"))))
(def s (Screen make 30 100))
(spec-draw! st s)
(tui-key! st (list (lit mouse) 0 31 5 #t))
(tui-key! st (list (lit mouse) 0 31 2 #t))
(spec-draw! st s)
(def asked (spec-rows s (list 28)))
(tui-key! st "n")
(write (list asked (spec-moves st)))
```
---
    ("Promote to: q queen, r rook, b bishop, n knight" ("e7e8n"))

### a piece of the side not to move is not picked up

```chess
(def st (tui-make ()))
(def s (Screen make 30 100))
(spec-draw! st s)
(tui-key! st (list (lit mouse) 0 45 2 #t))
(spec-draw! st s)
(display (spec-rows s (list 28)))
```
---
```output
Pick up one of your pieces.
```

### u takes back your move and the engine's reply together

```chess
(def st (tui-make ()))
(spec-keys! st (list "d" "4" (lit enter)))
(tui-engine-played! st (move-parse (game-pos (tui-game st)) "d5"))
(spec-keys! st (list "c" "4" (lit enter)))
(tui-engine-played! st (move-parse (game-pos (tui-game st)) "e6"))
(tui-key! st "u")
(write (spec-moves st))
```
---
    ("d2d4" "d7d5")

## the panel

### the engine's thinking, the moves, the bar and the message

```chess
(def st (tui-make ()))
(spec-keys! st (list "e" "4" (lit enter)))
(def g (tui-game st))
(def r (search-best (game-pos g) 2 0 0 (fn (_) #f) (fn (_ r) (tui-report! st (game-pos g) r))))
(tui-engine-played! st (List ref 4 r))
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 3 4 11 28)))
```
---
```output
                                                                2  +0.40  Nf6 Nc3
                                                                1  -0.10  Nf6
5                                                               1. e4       Nf6
x-chess plays Nf6
```

### looking back with [ and ], End to return

```chess
(def st (tui-make ()))
(spec-keys! st (list "e" "4" (lit enter)))
(tui-engine-played! st (move-parse (game-pos (tui-game st)) "e5"))
(spec-keys! st (list "["))
(def s (Screen make 30 100))
(spec-draw! st s)
(def back (spec-rows s (list 28)))
(spec-keys! st (list "e" "5" (lit enter)))
(spec-draw! st s)
(def refused (spec-rows s (list 28)))
(spec-keys! st (list (lit end) "N" "f" "3" (lit enter)))
(write (list back refused (spec-moves st)))
```
---
    ("Looking back at move 1: [ and ] step, End returns." "You are looking back: End returns to the game." ("e2e4" "e7e5" "g1f3"))

### the end of the game is said

```chess
(def st (tui-make (list (pair (lit fen) "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"))))
(spec-keys! st (list "R" "a" "8" (lit enter)))
(def s (Screen make 30 100))
(spec-draw! st s)
(write (list (spec-rows s (list 28)) (tui-engine-to-move? st)))
```
---
    ("White wins by checkmate.  n starts a new game, u takes a move back." #f)

## commands

### : then a command and Enter; a command it does not know is said

```chess
(def st (tui-make ()))
(spec-keys! st (list ":" "t" "i" "m" "e" " " "2" (lit enter)))
(def s (Screen make 30 100))
(spec-draw! st s)
(def timed (spec-rows s (list 0 28)))
(spec-keys! st (list ":" "f" "e" "n" " " "8" "/" "8" "/" "8" "/" "8" "/" "8" "/" "8" "/" "k" "7" "/" "4" "K" "3" " " "w" " " "-" " " "-" (lit enter)))
(def fen (pos-fen (game-pos (tui-game st))))
(spec-keys! st (list ":" "z" "z" (lit enter)))
(spec-draw! st s)
(write (list timed fen (spec-rows s (list 28))))
```
---
    ("   ●  x-chess (Black)                                         Playing x-chess · 2 s a move\nThe engine thinks 2 s." "8/8/8/8/8/8/k7/4K3 w - - 0 1" "No such command: zz.  ? lists them.")

### q leaves, as does ctrl-c

```chess
(def a (tui-make ()))
(tui-key! a "q")
(def b (tui-make ()))
(tui-key! b (lit interrupt))
(write (list (tui-quit? a) (tui-quit? b)))
```
---
    (#t #t)
