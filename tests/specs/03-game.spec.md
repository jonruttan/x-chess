# Games
@weight 1

chess/game: moves made and taken back, the numbered move text, and how
a game ends.

## playing

### the fool's mate ends in mate, and its moves read back numbered

```chess
(def g (game-new ()))
(List for-each (fn (_ t) (game-play! g (move-parse (game-pos g) t))) (list "f3" "e5" "g4" "Qh4"))
(write (list (game-result g) (game-movetext g)))
```
---
    (("0-1" . "checkmate") "1. f3 e5 2. g4 Qh4#")

### a game from black's move numbers its first move with dots

```chess
(def g (game-new "4k3/8/8/8/8/8/8/R3K3 b Q - 3 40"))
(List for-each (fn (_ t) (game-play! g (move-parse (game-pos g) t))) (list "Kd7" "O-O-O+" "Ke7"))
(write (list (game-movetext g) (game-fen g)))
```
---
    ("40... Kd7 41. O-O-O+ Ke7" "8/4k3/8/8/8/8/8/2KR4 w - - 6 42")

### undo takes moves back until there are none

```chess
(def g (game-new ()))
(game-play! g (move-parse (game-pos g) "e4"))
(write (list (game-undo! g) (game-undo! g) (game-fen g) (game-moves g)))
```
---
    (#t #f "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" ())

## endings

### stalemate, the fifty-move rule, and too little to mate

```chess
(write (List map (fn (_ f) (game-result (game-new f)))
  (list "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"
        "4k3/8/8/8/8/8/8/R3K3 w - - 100 80"
        "4k3/8/8/8/8/8/8/2B1K3 w - - 0 1"
        "4k3/8/8/8/8/8/8/4K3 w - - 0 1"
        "4k3/8/8/8/8/8/8/1NB1K3 w - - 0 1"
        fen-start)))
```
---
    (("1/2-1/2" . "stalemate") ("1/2-1/2" . "the fifty-move rule") ("1/2-1/2" . "insufficient material") ("1/2-1/2" . "insufficient material") () ())

### the same position a third time

```chess
(def g (game-new ()))
(def play (fn (_ t) (game-play! g (move-parse (game-pos g) t)) (game-result g)))
(write (List map play (list "Nf3" "Nf6" "Ng1" "Ng8" "Nf3" "Nf6" "Ng1" "Ng8")))
```
---
    (() () () () () () () ("1/2-1/2" . "threefold repetition"))
