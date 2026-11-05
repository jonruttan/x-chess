# Puzzles and the coach
@weight 2

chess/puzzle: puzzles made for x-chess and those of the lichess puzzle
database, and whether a move solves one.  chess/tui sets them on the
board, answers right moves with the solution's replies, and coaches a
game by the engine's own lines.  tests/puzzles.csv holds lines in the
lichess database's form.

## the set

### each puzzle's solution is legal and mates

```chess
(write (List map
  (fn (_ z)
    (def p (pos-from-fen (puzzle-fen z)))
    (List for-each (fn (_ u) (make! p (move-parse-uci p u))) (puzzle-solution z))
    (list (puzzle-title z) (puzzle-length z) (if (null? (legal-moves p)) (in-check? p) #f)))
  (puzzle-set)))
```
---
```output
(("Mate in 1: The back rank" 1 #t) ("Mate in 1: Smothered" 1 #t) ("Mate in 1: Too soon for the knight" 1 #t) ("Mate in 1: The king helps" 1 #t) ("Mate in 2: The ladder" 2 #t) ("Mate in 1: Back rank again" 1 #t) ("Mate in 1: The opposition" 1 #t) ("Mate in 1: Queen to the edge" 1 #t) ("Mate in 1: Too far to block" 1 #t))
```

### the engine finds no faster mate than each title gives

```chess
(write (List map
  (fn (_ z)
    (def r (search-best (pos-from-fen (puzzle-fen z)) (* 2 (puzzle-length z)) 0 0 (fn (_) #f) (fn (_ r) ())))
    (Heap collect)
    (mate-in (List ref 1 r)))
  (puzzle-set)))
```
---
    (1 1 1 1 2 1 1 1 1)

## judging a move

### the solution's move, another that mates, a wrong move, and a move on the way

```chess
(def zs (puzzle-set))
(def judge
  (fn (_ i text)
    (def z (List ref i zs))
    (def p (pos-from-fen (puzzle-fen z)))
    (puzzle-judge z p (move-parse p text) (puzzle-solution z))))
(write (list (judge 0 "Ra8") (judge 8 "Re8") (judge 0 "Ra7") (judge 4 "Ra7") (judge 4 "Rb8")))
```
---
    ('solved 'solved 'wrong 'right 'wrong)

## the lichess database

### a line read: the setup move made, the rest the solution

```chess
(def z (puzzle-from-csv "00sHx,q3k1nr/1pp1nQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 b k - 0 17,e8d7 a2e6 d7d8 f7f8,1760,80,83,72,mate mateIn2 middlegame short,https://lichess.org/yyznGmXs/black#34,"))
(write (list (puzzle-id z) (puzzle-title z) (puzzle-rating z) (puzzle-fen z) (puzzle-solution z) (puzzle-length z)))
```
---
    ("00sHx" "Mate in 2" 1760 "q5nr/1ppknQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 w - - 1 18" ("a2e6" "d7d8" "f7f8") 2)

### the header and a line that does not read are no puzzles

```chess
(write (list (puzzle-from-csv "PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags")
             (puzzle-from-csv "bad,not a position,e2e4,1500,80,83,72,short,,")))
```
---
    (() ())

### a file read as a source: the lines that read, then nothing

```chess
(def next (puzzle-file-source (Str8 append (Sys getenv "CHESS_TESTS") "/puzzles.csv")))
(def a (next))
(def b (next))
(write (list (puzzle-id a) (puzzle-id b) (puzzle-title b) (puzzle-solution b) (next)))
```
---
    ("00sHx" "01xyz" "endgame" ("g8f8" "c1c8") ())

### a file that is not there is refused

```chess
(write (guard (e (e msg)) (do (puzzle-file-source "/nonexistent/puzzles.csv") "opened")))
```
---
    "cannot open /nonexistent/puzzles.csv"

## on the board

### a mate in two: a wrong move, the right one answered, then the mate

```chess
(def st (tui-make (list (pair (lit puzzles) (puzzle-list-source (List drop 4 (puzzle-set)))))))
(def s (Screen make 30 100))
(def says (fn (_ keys) (spec-keys! st keys) (spec-draw! st s) (spec-rows s (list 28))))
(spec-draw! st s)
(display (spec-rows s (list 0 28 29)))
(newline)
(display (says (list "R" "b" "8" (lit enter))))
(newline)
(display (says (list "R" "a" "7" (lit enter))))
(newline)
(display (says (list "R" "b" "8" (lit enter))))
(newline)
(display (says (list "z")))
(newline)
(write (spec-moves st))
```
---
```output
   ●  x-chess (Black)                                         Puzzle 1 · 0 of 1 solved
Mate in 2: The ladder: White to move.
type or click a move · i hint · m show the move · z next puzzle · n leave · ? keys · q quit
Not Rb8+: try again.  i shows a hint, m the move.
Right.  Black replies Kg8: your move.
Right.  Done (0 of 1 solved): z for the next puzzle.
Mate in 1: Back rank again: White to move.
()
```

### a hint, then the move shown, and the end of the puzzles

```chess
(def st (tui-make (list (pair (lit puzzles) (puzzle-list-source (list (List ref 0 (puzzle-set))))))))
(spec-keys! st (list "i" "m"))
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 28)))
(newline)
(spec-keys! st (list "z"))
(spec-draw! st s)
(display (spec-rows s (list 0 28)))
```
---
```output
The move is Ra8#.  Done (0 of 1 solved): z for the next puzzle.
   ●  You (Black)                                             Playing x-chess · 5 s a move
No more puzzles: 0 of 1 solved.
```

### i shows the solution's move as a hint

```chess
(def st (tui-make (list (pair (lit puzzles) (puzzle-list-source (puzzle-set))))))
(def s (Screen make 30 100))
(spec-keys! st (list "i"))
(spec-draw! st s)
(display (spec-rows s (list 28)))
```
---
```output
Hint: Ra8#
```

### z with no puzzles set starts those made for x-chess, n leaves them

```chess
(def st (tui-make ()))
(def s (Screen make 30 100))
(spec-keys! st (list "z"))
(spec-draw! st s)
(display (spec-rows s (list 0 28)))
(newline)
(spec-keys! st (list "n"))
(spec-draw! st s)
(display (spec-rows s (list 28 29)))
```
---
```output
   ●  x-chess (Black)                                         Puzzle 1 · 0 of 1 solved
Mate in 1: The back rank: White to move.
A new game.
type or click a move · u back · v turn · i hint · m move now · l analyse · z puzzles · ? keys · q qu
```

## the coach

### your move judged by the engine's next score against the one its line expected

```chess
(def st (tui-make ()))
(def report
  (fn (_ score sans)
    (def p (pos-copy (game-pos (tui-game st))))
    (def line (List map (fn (_ t) ((fn (_ m) (make! p m) m) (move-parse p t))) sans))
    (list 9 score 100 1000 (first line) line)))
(spec-keys! st (list "j"))
(def on (tui-message! st ""))
(spec-keys! st (list "e" "4" (lit enter)))
(tui-engine-played! st (move-parse (game-pos (tui-game st)) "e5") (report 20 (list "e5" "Nf3")))
(spec-keys! st (list "a" "3" (lit enter)))
(tui-engine-played! st (move-parse (game-pos (tui-game st)) "Nc6") (report 200 (list "Nc6" "Nf3")))
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 0 28)))
(newline)
(spec-keys! st (list "N" "f" "3" (lit enter)))
(tui-engine-played! st (move-parse (game-pos (tui-game st)) "Nf6") (report 190 (list "Nf6")))
(spec-draw! st s)
(display (spec-rows s (list 28)))
(newline)
(spec-keys! st (list "j"))
(spec-draw! st s)
(display (spec-rows s (list 28)))
```
---
```output
   ●  x-chess (Black)                                         Playing x-chess · 5 s a move · coached
A mistake: Nf3 was better.  x-chess plays Nc6
Best.  x-chess plays Nf6
The coach is off.
```

## the command line

### the options puzzles and the coach take

```chess
(write (list (List map rest (chess-options (list "--puzzle" "--coach" "--puzzles" "p.csv") ()))
             (List map rest (chess-options (list "--puzzles") ()))))
```
---
    (("p.csv" #t #t) ("--puzzles takes a file"))
