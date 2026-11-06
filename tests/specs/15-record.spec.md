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
(record-add! r (z "aaaaa" 1227 (list "mate" "mateIn2")) #f)
(record-add! r (z "bbbbb" 1500 (list "fork")) #t)
(record-add! r (z "aaaaa" 1227 (list "mate" "mateIn2")) #t)
(record-add! r (z "aaaaa" 1227 (list "mate" "mateIn2")) #f)
(record-add! r (z "ccccc" 1300 (list "fork")) #f)
(record-add! r (z "" 0 (list "mate" "mateIn1")) #t)
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
(def next (record-unsolved (record-load path) (puzzle-list-source (List map z (list "aaaaa" "bbbbb" "ccccc")))))
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
(def st (tui-make (list (pair (lit record) path) (pair (lit puzzles) (puzzle-list-source two)))))
(spec-keys! st (list "R" "a" "8" (lit enter) "z" "m"))
(display (File read-all path))
(File unlink path)
```
---
```output
back1 900 solved mate mateIn1
back2 950 missed mate mateIn1
```

### the choice scores each theme in its band, and passes over the solved

```chess
(def t (File temp "/tmp/x-chess-record-"))
(File close (first t))
(def path (rest t))
(def first4 ((puzzle-file-source (puzzle-library) "mateIn4" 1000 1399)))
(File write-all path (Str8 append (puzzle-id first4) " 1227 solved mate mateIn4\nzzzzz 1300 missed mate mateIn4\nyyyyy 2300 solved fork\n"))
(def st (tui-make (list (pair (lit record) path))))
(def s (Screen make 30 100))
(spec-keys! st (list "z" ">" ">"))
(spec-draw! st s)
(display (spec-rows s (List range 5 13)))
(newline)
(spec-keys! st (list "4"))
(spec-draw! st s)
(display (spec-rows s (list 0)))
(File unlink path)
```
---
```output
7    ♟      ♟      ♟
                        Puzzles, rated 1000 to 1399

6                       1   Mate in one           40
                        2   Mate in two           40
                        3   Mate in three         40
5                       4   Mate in four          40   1 of 2 solved
                        5   Mate in five          40
   ○  x-chess (White)   +2                                    Puzzle 1 · 0 of 1 solved · rated 1251
```
