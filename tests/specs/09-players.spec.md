# Players, thinking shown, and matches
@weight 2

chess/engine speaks UCI to another program, chess/player asks it or
x-chess's own search for a move the same way, chess/match plays games
between two players, and game-pgn writes a game as PGN.  The engine the
specs start is tests/fake-engine.sh, which answers every go with two
info lines and the move it was given.

## another engine

### its name, a report for each info line, and the move it chose

```chess
(def e (engine-start (list "sh" (Str8 append (Sys getenv "CHESS_TESTS") "/fake-engine.sh"))))
(def g (game-new ()))
(game-play! g (move-parse (game-pos g) "e4"))
(def seen ())
(def r (engine-think e g 2 0 (fn (_) #f) (fn (_ r) (set! seen (pair (list (List ref 0 r) (List ref 1 r) (List map move-uci (List ref 5 r))) seen)))))
(def out (list (engine-name e) (List reverse seen) (move-uci (List ref 4 r)) (List map move-uci (List ref 5 r))))
(engine-quit! e)
(write out)
```
---
    ("Fake 1.0" ((1 13 ("e7e5")) (2 -21 ("e7e5" "g1f3"))) "e7e5" ("e7e5" "g1f3"))

### an info line read as a report: a mate in moves, the line as far as it is legal

```chess
(def r (engine-info-report (pos-from-fen fen-start)
         (list "info" "depth" "9" "score" "mate" "-2" "nodes" "5" "time" "7" "pv" "e2e4" "e7e5" "zz" "g1f3")))
(write (list (List ref 0 r) (mate-in (List ref 1 r)) (List ref 2 r) (List ref 3 r) (List map move-uci (List ref 5 r))))
```
---
    (9 -2 5 7000 ("e2e4" "e7e5"))

### a program that cannot be started is refused

```chess
(write (guard (e (e msg)) (do (engine-start (list "/nonexistent/engine")) "started")))
```
---
    "cannot start the engine /nonexistent/engine: no uciok"

## players

### x-chess's own, and a player started from a command

```chess
(def own (player-start ()))
(def fake (player-start (Str8 append "sh " (Sys getenv "CHESS_TESTS") "/fake-engine.sh")))
(def out (list (player-name own) (player-builtin? own) (player-name fake) (player-builtin? fake)
               (player-name (player-start "x-chess"))))
(player-quit! fake)
(write out)
```
---
    ("x-chess" #t "Fake 1.0" #f "x-chess")

## a game against another engine, its thinking shown

### the engine's lines as it finishes each depth, then its move

```chess
(def fake (player-start (Str8 append "sh " (Sys getenv "CHESS_TESTS") "/fake-engine.sh")))
(spec-lines (spec-untimed (spec-session (fn (_ io) (play-run io (list (pair (lit engine) fake) (pair (lit think) #t)) ()))
  (list "e4" "engine" "quit"))))
```
---
```output
x-chess 0.1.0: you play white; help lists the commands.
  +-----------------+
8 | r n b q k b n r |
7 | p p p p p p p p |
6 | . . . . . . . . |
5 | . . . . . . . . |
4 | . . . . . . . . |
3 | . . . . . . . . |
2 | P P P P P P P P |
1 | R N B Q K B N R |
  +-----------------+
    a b c d e f g h
White to move.
   1    +0.13  e5
   2    -0.21  e5 Nf3
Fake 1.0 plays e5
  +-----------------+
8 | r n b q k b n r |
7 | p p p p . p p p |
6 | . . . . . . . . |
5 | . . . . p . . . |
4 | . . . . P . . . |
3 | . . . . . . . . |
2 | P P P P . P P P |
1 | R N B Q K B N R |
  +-----------------+
    a b c d e f g h
White to move.
The engine is Fake 1.0.
```

### an engine with no move to give leaves both sides to you

```chess
(def fake (player-start (Str8 append "sh " (Sys getenv "CHESS_TESTS") "/fake-engine.sh none")))
(def out (spec-untimed (spec-session (fn (_ io) (play-run io (list (pair (lit engine) fake)) ())) (list "e4" "quit"))))
(write (List filter (fn (_ l) (Str8 includes? "no move" l)) (Str8 split "\n" out)))
```
---
    ("Fake 1.0 has no move: you play both sides.")

### think turns the thinking on and off

```chess
(write (List filter (fn (_ l) (Str8 starts? "Thinking" l))
  (Str8 split "\n" (spec-session (fn (_ io) (play-run io () "think")) (list "think" "quit")))))
```
---
    ("Thinking is shown." "Thinking is not shown.")

## matches

### two games from a mate in one: each side mates as white, a point each

```chess
(def out ())
(def rep ())
(def score (match-run (player-builtin) (player-builtin) 2
             (list (pair (lit fen) "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1") (pair (lit depth) 2) (pair (lit date) "2026.11.05"))
             (fn (_ t) (set! out (pair t out)))
             (fn (_ t) (set! rep (pair t rep)))))
(display (Str8 join "" (List reverse out)))
(display (Str8 join "" (List reverse rep)))
(write score)
```
---
```output
[Event "x-chess match"]
[Site "?"]
[Date "2026.11.05"]
[Round "1"]
[White "x-chess"]
[Black "x-chess"]
[Result "1-0"]
[SetUp "1"]
[FEN "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"]

1. Ra8# 1-0

[Event "x-chess match"]
[Site "?"]
[Date "2026.11.05"]
[Round "2"]
[White "x-chess"]
[Black "x-chess"]
[Result "1-0"]
[SetUp "1"]
[FEN "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"]

1. Ra8# 1-0

Game 1 of 2: x-chess - x-chess  1-0 (checkmate)
Game 2 of 2: x-chess - x-chess  1-0 (checkmate)
Score: x-chess 1, x-chess 1
(2 . 2)
```

## PGN

### the tags, and the movetext folded at 79 columns

```chess
(def g (game-new ()))
(List for-each (fn (_ s) (game-play! g (move-parse (game-pos g) s)))
  (list "e4" "e5" "Nf3" "Nc6" "Bb5" "a6" "Ba4" "Nf6" "O-O" "Be7" "Re1" "b5" "Bb3" "d6" "c3" "O-O" "h3" "Nb8" "d4" "Nbd7"))
(display (game-pgn g (list (pair "Event" "A \"quoted\" game")) "*"))
```
---
```output
[Event "A \"quoted\" game"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3
O-O 9. h3 Nb8 10. d4 Nbd7 *
```

## the command line

### the options a match and another engine take

```chess
(write (list (List map rest (chess-options (list "--match" "4" "--engine" "sf" "--engine" "lc0 --x" "--think") ()))
             (List map rest (chess-options (list "--match" "0") ()))
             (List map rest (chess-options (list "--engine") ()))))
```
---
    ((#t "lc0 --x" "sf" 4) ("--match takes a number of games") ("--engine takes a command"))
