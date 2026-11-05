# Playing at the terminal
@weight 1

chess/play: a game against the engine, a line at a time.  The engine
here looks two plies deep; what it says after its move, how deep and
how long, is taken out (spec-untimed).

## a game

### a move, the reply, a move that is not legal, and the moves there are

```chess
(spec-lines (spec-untimed (spec-session (fn (_ io) (play-run io (list (pair 'depth 2)) ()))
  (list "e4" "e9" "moves" "quit"))))
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
x-chess plays Nf6
  +-----------------+
8 | r n b q k b . r |
7 | p p p p p p p p |
6 | . . . . . n . . |
5 | . . . . . . . . |
4 | . . . . P . . . |
3 | . . . . . . . . |
2 | P P P P . P P P |
1 | R N B Q K B N R |
  +-----------------+
    a b c d e f g h
White to move.
Not a legal move here: e9.  moves lists them, help the commands.
e5 h4 h3 g4 g3 f4 f3 d4 d3 c4 c3 b4 b3 a4 a3 Ne2 Nf3 Nh3 Ba6 Bb5 Bc4 Bd3 Be2 Ke2 Qh5 Qg4 Qf3 Qe2 Na3 Nc3
```

### undo takes back the reply too; pgn and fen say where the game is

```chess
(spec-lines (spec-untimed (spec-session (fn (_ io) (play-run io (list (pair 'depth 1)) "e4"))
  (list "undo" "d4" "pgn" "fen"))))
```
---
```output
x-chess plays Nf6
  +-----------------+
8 | r n b q k b . r |
7 | p p p p p p p p |
6 | . . . . . n . . |
5 | . . . . . . . . |
4 | . . . . P . . . |
3 | . . . . . . . . |
2 | P P P P . P P P |
1 | R N B Q K B N R |
  +-----------------+
    a b c d e f g h
White to move.
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
x-chess plays Nf6
  +-----------------+
8 | r n b q k b . r |
7 | p p p p p p p p |
6 | . . . . . n . . |
5 | . . . . . . . . |
4 | . . . P . . . . |
3 | . . . . . . . . |
2 | P P P . P P P P |
1 | R N B Q K B N R |
  +-----------------+
    a b c d e f g h
White to move.
1. d4 Nf6
rnbqkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 1 2
```

### black: the engine opens and the board turns

```chess
(spec-lines (spec-untimed (spec-session (fn (_ io) (play-run io (list (pair 'depth 1) (pair 'side 'black)) "board"))
  (list "quit"))))
```
---
```output
  +-----------------+
1 | R N B K Q B N R |
2 | P P P P P P P P |
3 | . . . . . . . . |
4 | . . . . . . . . |
5 | . . . . . . . . |
6 | . . . . . . . . |
7 | p p p p p p p p |
8 | r n b k q b n r |
  +-----------------+
    h g f e d c b a
x-chess plays Nf3
  +-----------------+
1 | R . B K Q B N R |
2 | P P P P P P P P |
3 | . . N . . . . . |
4 | . . . . . . . . |
5 | . . . . . . . . |
6 | . . . . . . . . |
7 | p p p p p p p p |
8 | r n b k q b n r |
  +-----------------+
    h g f e d c b a
Black to move.
```

### a mate ends the game, and new starts another

```chess
(spec-lines (spec-untimed (spec-session (fn (_ io) (play-run io (list (pair 'side 'both)) "f3"))
  (list "e5" "g4" "Qh4" "e4" "new"))))
```
---
    White to move.

### a bad position is refused and the game goes on

```chess
(spec-lines (spec-session (fn (_ io) (play-run io (list (pair 'side 'both)) "fen 8/8/8 w")) ()))
```
---
    White to move.
