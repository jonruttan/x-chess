# Puzzles and the coach
@weight 3

chess/puzzle: puzzles made for x-chess, the library cut from the lichess
puzzle database that x-chess ships, and those of any file of that
database, chosen by its themes and ratings, and whether a move solves
one.  chess/tui sets them on the board, answers right moves with the
solution's replies, and coaches a game by the engine's own lines.
tests/puzzles.csv holds lines in the lichess database's form.

## the set

### each mate's solution is legal and mates

```chess
(write (List map
  (fn (_ z)
    (def p (pos-from-fen (puzzle-fen z)))
    (List for-each (fn (_ u) (make! p (move-parse-uci p u))) (puzzle-solution z))
    (list (puzzle-title z) (puzzle-length z) (if (null? (legal-moves p)) (in-check? p) #f)))
  (List filter (fn (_ z) (puzzle-has? z "mate")) (puzzle-set))))
```
---
```output
(("Mate in 1: The back rank" 1 #t) ("Mate in 1: Smothered" 1 #t) ("Mate in 1: Too soon for the knight" 1 #t) ("Mate in 1: The king helps" 1 #t) ("Mate in 1: Back rank again" 1 #t) ("Mate in 1: The opposition" 1 #t) ("Mate in 1: Queen to the edge" 1 #t) ("Mate in 1: Too far to block" 1 #t) ("Mate in 2: The ladder" 2 #t) ("Mate in 2: The queen as bait" 2 #t) ("Mate in 2: Philidor's smothered mate" 2 #t) ("Mate in 2: Légal's trap" 2 #t) ("Mate in 2: A waiting move" 2 #t) ("Mate in 2: Take the square" 2 #t) ("Mate in 2: The king steps up" 2 #t) ("Mate in 3: Philidor's legacy" 3 #t))
```

### each tactic's solution wins at least a minor piece, by the evaluation

```chess
(write (List map
  (fn (_ z)
    (def p (pos-from-fen (puzzle-fen z)))
    (def before (evaluate p))
    (List for-each (fn (_ u) (make! p (move-parse-uci p u))) (puzzle-solution z))
    ; an odd number of moves leaves the other side to move
    (def after (if (= (% (List length (puzzle-solution z)) 2) 1) (- 0 (evaluate p)) (evaluate p)))
    (list (puzzle-title z) (< 250 (- after before))))
  (List filter (fn (_ z) (puzzle-has? z "crushing")) (puzzle-set))))
```
---
```output
(("A fork: The king and the queen" #t) ("A fork: Check, then the rook" #t) ("A skewer: Through the king" #t) ("A pin: The queen cannot move" #t) ("A discovered attack: Out of the way, with check" #t))
```

### the engine finds no faster mate than each title gives: none in two for a mate in three

```chess
(write (List map
  (fn (_ z)
    (def n (puzzle-mate-in z))
    (def r (search-best (pos-from-fen (puzzle-fen z)) (* 2 (if (< 2 n) 2 n)) 0 0 (fn (_) #f) (fn (_ r) ())))
    (Heap collect)
    (if (mate-score? (List ref 1 r)) (mate-in (List ref 1 r)) (lit none)))
  (List filter (fn (_ z) (puzzle-has? z "mate")) (puzzle-set))))
```
---
    (1 1 1 1 1 1 1 1 2 2 2 2 2 2 2 3)

## judging a move

### the solution's move, another that mates, a wrong move, a move on the way, and another way on

```chess
(def zs (puzzle-set))
(def find (fn (_ name) (List find (fn (_ z) (Str8 includes? name (puzzle-title z))) zs)))
(def judge
  (fn (_ name text)
    (def z (find name))
    (def p (pos-from-fen (puzzle-fen z)))
    (first (puzzle-judge z p (move-parse p text) (puzzle-solution z)))))
(write (list (judge "The back rank" "Ra8") (judge "Too far to block" "Re8") (judge "The back rank" "Ra7")
             (judge "The ladder" "Ra7") (judge "The ladder" "Rb8") (judge "The ladder" "Rb7")))
```
---
    ('solved 'solved 'wrong 'right 'wrong 'right)

### another way on to the mate is answered with the longest defence

```chess
(def z (List find (fn (_ z) (Str8 includes? "The ladder" (puzzle-title z))) (puzzle-set)))
(def p (pos-from-fen (puzzle-fen z)))
(write (puzzle-judge z p (move-parse p "Rb7") (puzzle-solution z)))
```
---
    ('right "h8g8" "a2a8")

## the library

### the puzzles x-chess ships: where, a band's ratings in order, and the first of three themes

```chess
(def lib (puzzle-library))
(def ratings (fn (self next) ((fn (_ z) (if (null? z) () (pair (puzzle-rating z) (self next)))) (next))))
(def rising? (fn (self rs) (if (null? (rest rs)) #t (if (< (List ref 1 rs) (first rs)) #f (self (rest rs))))))
(def top (ratings (puzzle-file-source lib "mateIn5" 2200 0)))
(def first-of (fn (_ t low high) ((puzzle-file-source lib t low high))))
(write (list (Str8 ends? "/chess/puzzles.csv" lib)
             (List length top) (rising? top) (< 2199 (first top))
             (List map (fn (_ t) ((fn (_ z) (list (puzzle-length z) (puzzle-rating z))) (first-of t 0 0)))
               (list "mateIn1" "mateIn5" "fork"))
             (puzzle-rating (first-of "pin" 1800 2199))))
```
---
    (#t 40 #t #t ((1 746) (5 1077) (2 847)) 1800)

### the counts beside the library, as many as the library gives, and none beside a file without them

```chess
(def c (puzzle-counts (puzzle-library)))
(def tally (fn (self next) (if (null? (next)) 0 (+ 1 (self next)))))
(write (list (puzzle-count c "mateIn4" 1000 1399) (puzzle-count c "" 0 0) (puzzle-count c "fork" 2200 0)
             (tally (puzzle-file-source (puzzle-library) "fork" 2200 0))
             (puzzle-count c "nosuch" 0 0)
             (puzzle-counts (Str8 append (Sys getenv "CHESS_TESTS") "/puzzles.csv"))))
```
---
    (40 2342 54 54 () ())

### every solution of the hardest mates in five is legal in the engine's rules and ends in mate

```chess
(def lib (puzzle-library))
(def plays
  (fn (_ z)
    (def p (pos-from-fen (puzzle-fen z)))
    (def go
      (fn (self ms)
        (if (null? ms) (if (null? (legal-moves p)) (in-check? p) #f)
          ((fn (_ m) (if (null? m) #f (do (make! p m) (self (rest ms))))) (move-parse-uci p (first ms))))))
    (go (puzzle-solution z))))
(def tally
  (fn (self next ok bad)
    (Heap collect)
    ((fn (_ z) (match ((null? z) (list ok bad))
                      ((plays z) (self next (+ ok 1) bad))
                      (#t (self next ok (pair (puzzle-id z) bad)))))
     (next))))
(write (tally (puzzle-file-source lib "mateIn5" 2200 0) 0 ()))
```
---
    (40 ())

## themes

### the titles themes give, and what a theme picks

```chess
(def zs (puzzle-set))
(def count (fn (_ t) (List length (List filter (fn (_ z) (puzzle-has? z t)) zs))))
(write (list (puzzle-title (puzzle-make "8/8/8/8/8/8/8/8 w - - 0 1" () "" 0 "" (list "crushing" "fork")))
             (puzzle-title (puzzle-make "8/8/8/8/8/8/8/8 w - - 0 1" () "Named" 0 "" (list "mate" "mateIn3")))
             (puzzle-title (puzzle-make "8/8/8/8/8/8/8/8 w - - 0 1" () "" 0 "" (list "endgame")))
             (puzzle-title (puzzle-make "8/8/8/8/8/8/8/8 w - - 0 1" () "" 0 "" ()))
             (list (count "mateIn1") (count "mateIn2") (count "mateIn3") (count "crushing") (count "mate") (count ""))))
```
---
    ("A fork" "Mate in 3: Named" "endgame" "A puzzle" (8 7 1 5 16 21))

### a range read, and a file's puzzles picked by theme and rating

```chess
(def file (Str8 append (Sys getenv "CHESS_TESTS") "/puzzles.csv"))
(def ids (fn (self next) ((fn (_ z) (if (null? z) () (pair (puzzle-id z) (self next)))) (next))))
(write (list (puzzle-range "1500-1800") (puzzle-range "1500-") (puzzle-range "-1800") (puzzle-range "fork") (puzzle-range "-")
             (ids (puzzle-file-source file "mate" 0 0))
             (ids (puzzle-file-source file "" 0 1000))
             (ids (puzzle-file-source file "" 1000 0))))
```
---
    ((1500 . 1800) (1500 . 0) (0 . 1800) () () ("00sHx") ("01xyz") ("00sHx"))

## on the board

### a mate in two: a wrong move, the right one answered, then the mate

```chess
(def st (tui-make (list (pair (lit puzzles) (puzzle-list-source (List filter (fn (_ z) (puzzle-has? z "mateIn2")) (puzzle-set)))))))
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
Mate in 2: The queen as bait: White to move.
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

### z with no puzzles set shows the choice, < > a band, a key picks, n leaves them

```chess
(def st (tui-make ()))
(def s (Screen make 30 100))
(spec-keys! st (list "z"))
(spec-draw! st s)
(display (spec-rows s (List range 4 25)))
(newline)
(spec-keys! st (list ">" ">"))
(spec-draw! st s)
(display (spec-rows s (List range 4 7)))
(newline)
(spec-keys! st (list "4"))
(spec-draw! st s)
(display (spec-rows s (list 0 28)))
(newline)
(spec-keys! st (list "n"))
(spec-draw! st s)
(display (spec-rows s (list 28 29)))
```
---
```output
7    ♟      ♟      ♟    Puzzles, any rating

                        1   Mate in one          182
6                       2   Mate in two          200
                        3   Mate in three        200
                        4   Mate in four         200
5                       5   Mate in five         160
                        f   Forks                258
                        p   Pins                 272
4                       s   Skewers              207
                        d   Discovered attacks   287
                        t   Trapped pieces       204
3                       h   Pieces left hanging  216
                        e   Endgames             977
                        a   All of them         2342
2    ♙      ♙      ♙    x   x-chess's own, unrated
                        l   lichess's puzzle of the day

1    ♖      ♘      ♗    < >  another rating · any other key: back to the game


7    ♟      ♟      ♟    Puzzles, rated 1000 to 1399

   ●  x-chess (Black)   +2                                    Puzzle 1 · 0 of 1 solved · rated 1227
Mate in 4: White to move.
A new game.
type or click a move · u back · v turn · i hint · m move now · l analyse · z puzzles · ? keys · q qu
```

### a key the choice does not offer goes back to the game

```chess
(def st (tui-make ()))
(spec-keys! st (list "z" "y"))
(def s (Screen make 30 100))
(spec-draw! st s)
(display (spec-rows s (list 0 28)))
```
---
```output
   ●  x-chess (Black)                                         Playing x-chess · 5 s a move
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
(write (list (List map rest (chess-options (list "--puzzle" "--coach" "--puzzles" "p.csv" "--theme" "fork" "--rating" "1500-1800") ()))
             (List map rest (chess-options (list "--puzzles") ()))
             (List map rest (chess-options (list "--rating" "hard") ()))))
```
---
    (((1500 . 1800) "fork" "p.csv" #t #t) ("--puzzles takes a file") ("--rating takes a range: LOW-HIGH, LOW- or -HIGH"))
