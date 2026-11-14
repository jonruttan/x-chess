# The score, the bar and the engine's suggestions
@weight 2

chess/tui: the Score the panel heads with, the bar beside the board and
the one across the panel, which follow the position shown, and the moves
the engine suggests when s is on.  The searches here are limited by
depth, so what they find is the same every run.  The ascii board draws a
bar's black cells as : and its white ones as reversed spaces, so a row's
text shows how far the bar has moved.

## the score

### before any search: not scored yet, the material even

```chess
(def st (tui-make ()))
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 2 3 4)))
```
---
```output
8    ♜      ♞      ♝      ♛      ♚      ♝      ♞      ♜       Score  not scored yet

                                                              material even
```

### a search's report: the score, who stands better, the depth and the material

```chess
(def st (tui-make (list (pair (lit board) "ascii"))))
(spec-keys! st (list "e" "4" (lit enter)))
(def g (tui-game st))
(search-best (game-pos g) 2 0 0 (fn (_) #f) (fn (_ r) (tui-report! st (game-pos g) r)))
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 2 3 4)))
```
---
```output
8    r   ...n...   b   ...q...   k   ...b...   n   ...r... :  Score  White is slightly better
         .......       .......       .......       ....... :  +0.40               :::::::::::
  .......       .......       .......       .......        :  depth 2 | material even
```

### the bars move with the score: even, then white a rook up

```chess
(def even (tui-make (list (pair (lit board) "ascii"))))
(def up (tui-make (list (pair (lit board) "ascii") (pair (lit side) (lit both))
                        (pair (lit fen) "4k3/8/8/8/8/8/8/R3K3 w - - 0 1"))))
(def g (tui-game up))
(search-best (game-pos g) 1 0 0 (fn (_) #f) (fn (_ r) (tui-scored! up (game-pos g) r)))
(def a (Screen make 30 100))
(def b (Screen make 30 100))
(spec-draw! even a)
(spec-draw! up b)
(display (spec-rows a (list 3 8 16)))
(display "\n")
(display (spec-rows b (list 2 3 4 8 16)))
```
---
```output
         .......       .......       .......       ....... :                     ::::::::::::
6        .......       .......       .......       ....... :
  .......       .......       .......       .......
8        .......       .......   k   .......       ....... :  Score  White is winning
         .......       .......       .......       .......    +5.27                        ::
  .......       .......       .......       .......           depth 1 | material White +5
6        .......       .......       .......       .......
  .......       .......       .......       .......
```

### a mate found: the side that mates, in how many, the bar all white's

```chess
(def st (tui-make (list (pair (lit board) "ascii") (pair (lit side) (lit both))
                        (pair (lit fen) "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"))))
(def g (tui-game st))
(search-best (game-pos g) 2 0 0 (fn (_) #f) (fn (_ r) (tui-scored! st (game-pos g) r)))
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 2 3 4)))
```
---
```output
8        .......       .......       .......   k   .......    Score  White mates in 1
         .......       .......       .......       .......    #1
  .......       .......       .......       .......           depth 2 | material White +5
```

### the game's end: its result, and nothing left to score

```chess
(def st (tui-make (list (pair (lit side) (lit both)) (pair (lit fen) "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"))))
(spec-keys! st (list "R" "a" "8" (lit enter)))
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 2 3 4)))
(display "\n")
(write (tui-unscored st))
```
---
```output
8    ♜                                         ♚              Score  White wins by checkmate
                                                              1-0
                                                              material White +5
()
```

## following the position

### a position wants a score until one is kept for it

```chess
(def st (tui-make (list (pair (lit side) (lit both)))))
(def g (tui-game st))
(def before (pos-fen (tui-unscored st)))
(search-best (game-pos g) 1 0 0 (fn (_) #f) (fn (_ r) (tui-scored! st (game-pos g) r)))
(write (list before (tui-unscored st)))
```
---
    ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" ())

### a move made: the last score shown while the new one is found, and each kept for going back

```chess
(def st (tui-make (list (pair (lit side) (lit both)))))
(def g (tui-game st))
(def score! (fn (_ d) (search-best (game-pos g) d 0 0 (fn (_) #f) (fn (_ r) (tui-scored! st (game-pos g) r)))))
(def s (Screen make 30 100))
(score! 2)
(spec-draw! st s)
(def start (spec-rows s (list 3 4)))
(spec-keys! st (list "e" "4" (lit enter)))
(spec-draw! st s)
(def waiting (spec-rows s (list 2 4)))
(score! 1)
(spec-draw! st s)
(def after (spec-rows s (list 3 4)))
(spec-keys! st (list "["))
(spec-draw! st s)
(def back (spec-rows s (list 3 4)))
(spec-lines (Str8 join "\n" (list start waiting after back)))
```
---
```output
                                                              +0.00
                                                              depth 2 · material even
8    ♜      ♞      ♝      ♛      ♚      ♝      ♞      ♜       Score  Even
                                                              scoring · material even
                                                              -0.10
                                                              depth 1 · material even
                                                              +0.00
                                                              depth 2 · material even
```

### the engine's move: its score, a ply shallower, is the new position's

```chess
(def st (tui-make ()))
(spec-keys! st (list "e" "4" (lit enter)))
(def g (tui-game st))
(def r (search-best (game-pos g) 3 0 0 (fn (_) #f) (fn (_ r) (tui-report! st (game-pos g) r))))
(tui-engine-played! st (List ref 4 r) r)
(def s (Screen make 30 100))
(spec-draw! st s)
(write (list (List ref 0 r) (tui-unscored st)))
(display "\n")
(display (spec-rows s (list 4)))
```
---
```output
(3 ())
                                                              depth 2 · material even
```

### a puzzle being solved is not scored

```chess
(def st (tui-make (list (pair (lit puzzles) (puzzle-list-source (puzzle-set))))))
(def s (Screen make 30 100))
(spec-draw! st s)
(write (list (spec-rows s (list 2)) (tui-unscored st)))
```
---
```output
("8                                              ♚              Score  not shown in a puzzle" ())
```

## the engine's suggestions

### search-excluding passes over the moves given at the root

```chess
(def p (pos-from-fen "4k3/8/8/8/8/8/8/R3K3 w - - 0 1"))
(def best (search-best p 2 0 0 (fn (_) #f) (fn (_ r) ())))
(def other (search-excluding p (list (List ref 4 best)) 2 0 0 (fn (_) #f) (fn (_ r) ())))
(write (list (= (List ref 4 best) (List ref 4 other))
             (search-excluding p (legal-moves p) 2 0 0 (fn (_) #f) (fn (_ r) ()))
             (= (List ref 4 best) (List ref 4 (search-best p 2 0 0 (fn (_) #f) (fn (_ r) ()))))))
```
---
    (#f () #t)

### s turns them on and off; :suggest does too

```chess
(def st (tui-make ()))
(def s (Screen make 30 100))
(tui-key! st "s")
(spec-draw! st s)
(def on (spec-rows s (list 0 6 28)))
(spec-keys! st (list ":" "s" "u" "g" "g" "e" "s" "t" (lit enter)))
(spec-draw! st s)
(spec-lines (Str8 join "\n" (list on (spec-rows s (list 0 6 28)))))
```
---
```output
   ●  x-chess (Black)                                         Playing x-chess · 5 s a move · suggest
                                                              Suggested  looking
The engine suggests your moves: s stops.
   ●  x-chess (Black)                                         Playing x-chess · 5 s a move
                                                              Thinking
Suggestions are off.
```

### wanted on your move, each search passing over the moves found before

```chess
(def st (tui-make (list (pair (lit board) "ascii"))))
(tui-key! st "s")
(def find!
  (fn (self k)
    (def w (tui-suggest-wanted st))
    (unless (null? w)
      (search-excluding (first w) (rest w) 2 0 0 (fn (_) #f) (fn (_ r) (tui-suggestion! st (first w) k r)))
      (self (+ k 1)))))
(def first-wanted (tui-suggest-wanted st))
(find! 0)
(tui-suggested! st (game-pos (tui-game st)))
(def s (Screen make 30 100))
(spec-draw! st s)
(write (list (List length first-wanted) (tui-suggest-wanted st)))
(display "\n")
(display (spec-rows s (list 2 3 4 6 7 8 9 11)))
(display "\n")
(display (spec-rows s (list 16 19 22)))
```
---
```output
(1 ())
8    r   ...n...   b   ...q...   k   ...b...   n   ...r... :  Score  Even
         .......       .......       .......       ....... :  +0.00              ::::::::::::
  .......       .......       .......       .......        :  depth 2 | material even
  .......       .......       .......       .......        :  Suggested
         .......       .......       .......       ....... :  1. Nf3     +0.00  Nf6
6        .......       .......       .......       ....... :  2. Nc3     +0.00  Nf6
         .......       .......       .......       ....... :  3. e4      -0.10  Nf6
5 .......       .......       .......       .......        :  Thinking
  .......       .......       .......~~~~~~~.......
         .......       .......       .......       .......
  .......       .......       .......       ~~~~~~~
```

### not wanted when it is not your move, and not in a puzzle

```chess
(def st (tui-make ()))
(tui-key! st "s")
(spec-keys! st (list "e" "4" (lit enter)))
(def s (Screen make 30 100))
(spec-draw! st s)
(def engine-to-move (list (tui-suggest-wanted st) (spec-rows s (list 6))))
(def pz (tui-make (list (pair (lit puzzles) (puzzle-list-source (puzzle-set))))))
(tui-key! pz "s")
(spec-draw! pz s)
(write (list engine-to-move (tui-suggest-wanted pz) (spec-rows s (list 28))))
```
---
```output
((() "                                                              Suggested  on your move") () "In a puzzle: i shows a hint, m the move.")
```
