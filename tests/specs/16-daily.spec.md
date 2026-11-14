# The puzzle of the day
@weight 1

chess/daily: lichess's puzzle of the day, read from its JSON, kept, and
the copy kept set when lichess cannot be reached.  tests/daily.json is
one answer of https://lichess.org/api/puzzle/daily, the players left
out; no spec reaches the network.

## reading it

### the puzzle a day's answer holds, and none in text that is not one

```chess
(def text (File read-all (Str8 append (Sys getenv "CHESS_TESTS") "/daily.json")))
(def z (daily-from-text text))
(write (list (puzzle-id z) (puzzle-rating z) (puzzle-fen z) (puzzle-solution z) (puzzle-themes z) (puzzle-title z)
             (List any? (fn (_ m) (str=? (move-uci m) (first (puzzle-solution z)))) (legal-moves (pos-from-fen (puzzle-fen z))))
             (daily-from-text "{\"puzzle\":{\"id\":\"x\"}}") (daily-from-text "not json")))
```
---
    ("u52YY" 1868 "r2q1rk1/pp3pp1/7B/3pbP2/6Q1/2N5/PP4PP/n4R1K w - - 0 1" ("h6g7" "e5g7" "f5f6" "d8f6" "f1f6") ("middlegame" "advantage" "long" "sacrifice" "pin") "A sacrifice: the lichess puzzle of the day" #t () ())

## fetched or kept

### a fetched puzzle is kept; when lichess cannot be reached the copy kept is set; with neither, why

```chess
(def text (File read-all (Str8 append (Sys getenv "CHESS_TESTS") "/daily.json")))
(def t (File temp "/tmp/x-chess-daily-"))
(File close (first t))
(def path (rest t))
(File unlink path)
(def offline (fn (_) (Err raise (lit io) "Socket resolve: getaddrinfo failed for lichess.org" ())))
(def said (fn (_ fetch) (guard (e (e msg)) ((fn (_ r) (list (puzzle-id (first r)) (rest r))) (daily-get path fetch)))))
(def none (said offline))
(def fresh (said (fn (_) text)))
(def kept (File read-all path))
(def stale (said offline))
(def garbled (said (fn (_) "<html>busy</html>")))
(File unlink path)
(write (list none fresh (str=? kept text) stale garbled))
```
---
    ("no puzzle of the day: Socket resolve: getaddrinfo failed for lichess.org" ("u52YY" "") #t ("u52YY" "lichess not reached (Socket resolve: getaddrinfo failed for lichess.org): the last one fetched") ("u52YY" "lichess not reached (its answer did not read as a puzzle): the last one fetched"))

## on the board

### l in the choice says it is asking, then sets the puzzle; solved, it says so

```chess
(def text (File read-all (Str8 append (Sys getenv "CHESS_TESTS") "/daily.json")))
(def t (File temp "/tmp/x-chess-daily-"))
(File close (first t))
(def path (rest t))
(def r (File temp "/tmp/x-chess-record-"))
(File close (first r))
(def st (tui-make (list (pair (lit daily) (pair path (fn (_) text))) (pair (lit record) (rest r)) (pair (lit skip) #t)
                        (pair (lit clock) (spec-clock (list 0 7300))))))
(def s (Screen make 30 100))
(spec-keys! st (list "z" "l"))
(spec-draw! st s)
(display (spec-rows s (list 28)))
(newline)
(tui-work! st)
(spec-draw! st s)
(display (spec-rows s (list 0 28)))
(newline)
(spec-keys! st (list "B" "x" "g" "7" (lit enter)))
(spec-draw! st s)
(display (spec-rows s (list 28)))
(newline)
(spec-keys! st (list "f" "6" (lit enter) "R" "x" "f" "6" (lit enter)))
(spec-draw! st s)
(display (spec-rows s (list 28)))
(newline)
(spec-keys! st (list "n" ":" "p" "u" "z" "z" "l" "e" " " "d" "a" "i" "l" "y" (lit enter)))
(tui-work! st)
(spec-draw! st s)
(display (spec-rows s (list 28)))
(File unlink path)
(File unlink (rest r))
```
---
```output
Asking lichess for the puzzle of the day...
   ●  x-chess (Black)   +5                                    Puzzle 1 · 0 of 1 solved · rated 1868
A sacrifice: the lichess puzzle of the day: White to move.
Right.  Black replies Bxg7: your move.
Right.  Solved in 7.3 s (1 of 1 solved): z for the next puzzle.
You have solved today's puzzle, u52YY, rated 1868.
```
