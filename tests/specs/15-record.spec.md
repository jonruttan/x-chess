# The puzzles finished
@weight 1

chess/record: the rated puzzles finished, kept a line each in a file;
the puzzles chosen pass over those solved, and the choice scores each
theme in its band.

## the record

### a missed puzzle, then solved, stays solved; one with no ID is not kept

```chess
(def t (File temp "/tmp/x-chess-record-"))
(File close (first t))
(def path (rest t))
(def z (fn (_ id rating themes) (puzzle-make "7k/8/8/8/8/8/R7/1R5K w - - 0 1" (list "a2a7") "" rating id themes)))
(def r (record-load path))
(record-add! r (z "aaaaa" 1227 (list "mate" "mateIn2")) #f ())
(record-add! r (z "bbbbb" 1500 (list "fork")) #t ())
(record-add! r (z "aaaaa" 1227 (list "mate" "mateIn2")) #t ())
(record-add! r (z "aaaaa" 1227 (list "mate" "mateIn2")) #f ())
(record-add! r (z "ccccc" 1300 (list "fork")) #f ())
(record-add! r (z "" 0 (list "mate" "mateIn1")) #t ())
(display (File read-all path))
(def again (record-load path))
(write (list (record-solved? again "aaaaa") (record-solved? again "bbbbb") (record-solved? again "ccccc")
             (record-score again "" 0 0) (record-score again "mate" 0 0) (record-score again "fork" 1000 1399)
             (record-score again "pin" 0 0)))
(File unlink path)
```
---
```output
aaaaa 1227 missed mate mateIn2
bbbbb 1500 solved fork
aaaaa 1227 solved mate mateIn2
aaaaa 1227 missed mate mateIn2
ccccc 1300 missed fork
(#t #t #f (2 . 3) (1 . 1) (0 . 1) (0 . 0))
```

### no file, a line that does not read, and the solved passed over

```chess
(def t (File temp "/tmp/x-chess-record-"))
(File close (first t))
(def path (rest t))
(File write-all path "bbbbb 1500 solved fork\nnot a line\nccccc\n")
(def z (fn (_ id) (puzzle-make "7k/8/8/8/8/8/R7/1R5K w - - 0 1" (list "a2a7") "" 1500 id (list "fork"))))
(def next (record-unsolved (record-load path) (puzzle-list-source (List map z (list "aaaaa" "bbbbb" "ccccc"))) puzzle-id))
(def drain (fn (self) ((fn (_ z) (if (null? z) () (pair (puzzle-id z) (self)))) (next))))
(write (list (drain) (record-score (record-load "/nonexistent/solved") "" 0 0) (record-score (record-load ()) "" 0 0)))
(File unlink path)
```
---
    (("aaaaa" "ccccc") (0 . 0) (0 . 0))

## on the board

### a puzzle solved and one shown are recorded

```chess
(def t (File temp "/tmp/x-chess-record-"))
(File close (first t))
(def path (rest t))
(def two (list (puzzle-make "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1" (list "a1a8") "" 900 "back1" (list "mate" "mateIn1"))
               (puzzle-make "6k1/5ppp/8/8/8/8/Q4PPP/1R4K1 w - - 0 1" (list "b1b8") "" 950 "back2" (list "mate" "mateIn1"))))
(def st (tui-make (list (pair (lit record) path) (pair (lit clock) (spec-clock (list 0 4200 5000 9000))) (pair (lit puzzles) (puzzle-list-source two)))))
(spec-keys! st (list "R" "a" "8" (lit enter) "z" "m"))
(display (File read-all path))
(File unlink path)
```
---
```output
back1 900 solved 4200ms mate mateIn1
back2 950 missed 4000ms mate mateIn1
```

### the choice scores each theme in its band, and passes over the solved

```chess
(def t (File temp "/tmp/x-chess-record-"))
(File close (first t))
(def path (rest t))
(def first4 ((puzzle-file-source (puzzle-library) "mateIn4" 1000 1399)))
(File write-all path (Str8 append (puzzle-id first4) " 1227 solved mate mateIn4\nzzzzz 1300 missed mate mateIn4\nyyyyy 2300 solved fork\n"))
(def st (tui-make (list (pair (lit record) path) (pair (lit skip) #t))))
(def s (Screen make 30 100))
(spec-keys! st (list "z" ">" ">"))
(spec-draw! st s)
(display (spec-rows s (List range 4 12)))
(newline)
(spec-keys! st (list "4"))
(spec-draw! st s)
(display (spec-rows s (list 0)))
(File unlink path)
```
---
```output
                        Puzzles, rated 1000 to 1399
7    ♟      ♟      ♟
                        1   Mate in one           40
                        2   Mate in two           40
6                       3   Mate in three         40
                        4   Mate in four          40   1 of 2 solved
                        5   Mate in five          40
5                       f   Forks                 52
   ○  x-chess (White)   +2                                    Puzzle 1 · 0 of 1 solved · rated 1251
```

## solve times

### the fastest solve kept, a miss's time no solve time, a line with no time read

```chess
(def t (File temp "/tmp/x-chess-record-"))
(File close (first t))
(def path (rest t))
(File write-all path "old11 1200 solved fork\n")
(def z (fn (_ id) (puzzle-make "7k/8/8/8/8/8/R7/1R5K w - - 0 1" (list "a2a7") "" 1500 id (list "fork"))))
(def r (record-load path))
(record-add! r (z "aaaaa") #t 12400)
(record-add! r (z "aaaaa") #t 8100)
(record-add! r (z "aaaaa") #t 9900)
(record-add! r (z "bbbbb") #f 3000)
(display (File read-all path))
(def again (record-load path))
(write (List map (fn (_ id) (list id (record-played? again id) (record-solved? again id) (record-best again id)))
  (list "aaaaa" "bbbbb" "old11" "zzzzz")))
(newline)
(write (record-score again "fork" 0 0))
(File unlink path)
```
---
```output
old11 1200 solved fork
aaaaa 1500 solved 12400ms fork
aaaaa 1500 solved 8100ms fork
aaaaa 1500 solved 9900ms fork
bbbbb 1500 missed 3000ms fork
(("aaaaa" #t #t 8100) ("bbbbb" #t #f ()) ("old11" #t #t ()) ("zzzzz" #f #f ()))
(2 . 3)
```

### on the board: the time said when solved, and again when it is set again

```chess
(def t (File temp "/tmp/x-chess-record-"))
(File close (first t))
(def path (rest t))
(def z (List ref 0 (puzzle-set)))
(def st (tui-make (list (pair (lit record) path) (pair (lit clock) (spec-clock (list 0 4200 10000 12500 20000 23000 30000 95000)))
                        (pair (lit puzzles) (puzzle-list-source (list z z z z))))))
(def s (Screen make 30 100))
(def says (fn (_ keys) (spec-keys! st keys) (spec-draw! st s) (spec-rows s (list 28))))
(display (says ()))
(newline)
(display (says (list "R" "a" "8" (lit enter))))
(newline)
(display (says (list "z")))
(newline)
(display (says (list "R" "a" "8" (lit enter))))
(newline)
(display (says (list "z" "R" "a" "8" (lit enter))))
(newline)
(display (says (list "z" "m")))
(newline)
(display (File read-all path))
(File unlink path)
```
---
```output
Mate in 1: The back rank: White to move.
Right.  Solved in 4.2 s (1 of 1 solved): z for the next puzzle.
Mate in 1: The back rank: White to move.  Solved before in 4.2 s.
Right.  Solved in 2.5 s, faster than your 4.2 s (2 of 2 solved): z for the next puzzle.
Right.  Solved in 3.0 s, your best 2.5 s (3 of 3 solved): z for the next puzzle.
The move is Ra8#.  Done (3 of 4 solved): z for the next puzzle.
xc01 0 solved 4200ms mate mateIn1 backRankMate
xc01 0 solved 2500ms mate mateIn1 backRankMate
xc01 0 solved 3000ms mate mateIn1 backRankMate
xc01 0 missed 65000ms mate mateIn1 backRankMate
```

### a puzzle missed before says so, and an unrated one is in no theme's score

```chess
(def t (File temp "/tmp/x-chess-record-"))
(File close (first t))
(def path (rest t))
(File write-all path "xc01 0 missed 5000ms mate mateIn1 backRankMate\nxc02 0 solved mate mateIn1 smotheredMate\n")
(def st (tui-make (list (pair (lit record) path) (pair (lit puzzles) (puzzle-list-source (List take 3 (puzzle-set)))))))
(def s (Screen make 30 100))
(def says (fn (_ keys) (spec-keys! st keys) (spec-draw! st s) (spec-rows s (list 28))))
(display (says ()))
(newline)
(display (says (list "z")))
(newline)
(display (says (list "z")))
(newline)
(write (record-score (record-load path) "mate" 0 0))
(File unlink path)
```
---
```output
Mate in 1: The back rank: White to move.  Missed before.
Mate in 1: Smothered: White to move.  Solved before.
Mate in 1: Too soon for the knight: White to move.
(0 . 0)
```

## skipping the solved

### --unsolved passes over the solved, of a list of puzzles and of a file's lines

```chess
(def t (File temp "/tmp/x-chess-record-"))
(File close (first t))
(def path (rest t))
(File write-all path "xc01 0 solved 900ms mate mateIn1 backRankMate\n00sHx 1760 solved 4000ms mate mateIn2\n")
(def file (Str8 append (Sys getenv "CHESS_TESTS") "/puzzles.csv"))
(def ids (fn (self next) ((fn (_ z) (if (null? z) () (pair (puzzle-id z) (self next)))) (next))))
(def r (record-load path))
(write (list (ids (record-unsolved r (puzzle-list-source (List take 3 (puzzle-set))) puzzle-id))
             (ids (puzzle-parsed (record-unsolved r (puzzle-file-lines file "" 0 0) puzzle-line-id)))
             (puzzle-line-id "00sHx,q3k1nr/1pp1nQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 b k - 0 17,e8d7")))
(newline)
(def on (tui-make (list (pair (lit record) path) (pair (lit skip) #t) (pair (lit puzzles) (puzzle-list-source (List take 2 (puzzle-set)))))))
(def off (tui-make (list (pair (lit record) path) (pair (lit puzzles) (puzzle-list-source (List take 2 (puzzle-set)))))))
(def s (Screen make 30 100))
(spec-draw! on s)
(display (spec-rows s (list 28)))
(newline)
(spec-draw! off s)
(display (spec-rows s (list 28)))
(File unlink path)
```
---
```output
(("xc02" "xc03") ("01xyz") "00sHx")
Mate in 1: Smothered: White to move.
Mate in 1: The back rank: White to move.  Solved before in 0.9 s.
```

### the puzzle of the day solved is set again, unless the solved are passed over

```chess
(def text (File read-all (Str8 append (Sys getenv "CHESS_TESTS") "/daily.json")))
(def t (File temp "/tmp/x-chess-daily-"))
(File close (first t))
(def r (File temp "/tmp/x-chess-record-"))
(File close (first r))
(File write-all (rest r) "u52YY 1868 solved 61000ms sacrifice\n")
(def s (Screen make 30 100))
(def daily (fn (_ skip)
  (def st (tui-make (list (pair (lit daily) (pair (rest t) (fn (_) text))) (pair (lit record) (rest r)) (pair (lit skip) skip))))
  (spec-keys! st (list "z" "l"))
  (tui-work! st)
  (spec-draw! st s)
  (spec-rows s (list 28))))
(display (daily #f))
(newline)
(display (daily #t))
(File unlink (rest t))
(File unlink (rest r))
```
---
```output
A sacrifice: the lichess puzzle of the day: White to move.  Solved before in 1:01.
You have solved today's puzzle, u52YY, rated 1868.
```

### u in the choice passes over the solved or sets them again

```chess
(def st (tui-make (list (pair (lit record) "/dev/null"))))
(def s (Screen make 30 100))
(spec-keys! st (list "z"))
(spec-draw! st s)
(display (spec-rows s (list 23)))
(newline)
(spec-keys! st (list "u"))
(spec-draw! st s)
(display (spec-rows s (list 23)))
```
---
```output
1    ♜      ♞      ♝    u   those solved set again
1    ♜      ♞      ♝    u   those solved passed over
```
