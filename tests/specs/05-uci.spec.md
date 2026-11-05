# UCI
@weight 1

chess/uci: the protocol a chess GUI speaks to an engine, a line at a
time.  The times in the info lines are taken out (spec-untimed).

## the handshake, a position, and a search

### uci, isready, position with moves, go depth

```chess
(spec-lines (spec-untimed (spec-session (fn (_ io) (uci-run io ()))
  (list "uci" "isready" "position startpos moves e2e4 e7e5" "go depth 2" "quit" "isready"))))
```
---
```output
id name x-chess 0.1.0
id author Jon Ruttan
option name OwnBook type check default false
option name BookFile type string default <empty>
uciok
readyok
info depth 1 score cp 50 nodes 34 pv g1f3
info depth 2 score cp 0 nodes 203 pv g1f3 g8f6
bestmove g1f3

```

### a mate is scored in moves

```chess
(spec-lines (spec-untimed (spec-session (fn (_ io) (uci-run io ()))
  (list "position fen 6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1" "go depth 2"))))
```
---
```output
info depth 1 score cp 505 nodes 21 pv a1a7
info depth 2 score mate 1 nodes 72 pv a1a8
bestmove a1a8

```

## the rest

### d shows the board, go perft counts, and what does not read is said

```chess
(spec-lines (spec-session (fn (_ io) (uci-run io ()))
  (list "position fen 8/8/8/8/8/8/8/K6k w - - 0 1 moves a1b1" "d" "go perft 2" "position fen 8/8/8 w" "position startpos moves e2e5")))
```
---
```output
  +-----------------+
8 | . . . . . . . . |
7 | . . . . . . . . |
6 | . . . . . . . . |
5 | . . . . . . . . |
4 | . . . . . . . . |
3 | . . . . . . . . |
2 | . . . . . . . . |
1 | . K . . . . . k |
  +-----------------+
    a b c d e f g h
Fen: 8/8/8/8/8/8/8/1K5k b - - 1 1
h1g2: 5
h1h2: 5
h1g1: 5

Nodes searched: 15

info string x-chess: cannot set up: position fen 8/8/8 w
info string x-chess: cannot set up: position startpos moves e2e5

```

### a mated side answers bestmove 0000

```chess
(spec-lines (spec-session (fn (_ io) (uci-run io ()))
  (list "position startpos moves f2f3 e7e5 g2g4 d8h4" "go depth 3")))
```
---
```output
bestmove 0000

```

### movetime, a slice of the clock, or no limit

```chess
(write (List map (fn (_ ws) (uci-think-ms ws 0))
  (list (list "movetime" "500")
        (list "wtime" "60000" "btime" "60000")
        (list "wtime" "1000" "winc" "100")
        (list "wtime" "60" "btime" "9000")
        (list "wtime" "60000" "movestogo" "8")
        (list "infinite"))))
```
---
    (500 1875 106 30 6000 0)

## options

### OwnBook plays the book's move unsearched; BookFile names a book, empty for the built-in one; other names are said

```chess
(spec-lines (spec-untimed (spec-session (fn (_ io) (uci-run io ()))
  (list "setoption name OwnBook value true"
        "position startpos moves e2e4 e7e5 g1f3 g8f6" "go depth 1"
        "setoption name BookFile value /nonexistent/book.bin" "go depth 1"
        "setoption name BookFile value <empty>" "go depth 1"
        "setoption name Hash value 16"
        "setoption name OwnBook value false" "go depth 1"))))
```
---
```output
info string book move
bestmove f3e5
info depth 1 score cp 50 nodes 49 pv b1c3
bestmove b1c3
info string book move
bestmove f3e5
info string x-chess: no such option: hash
info depth 1 score cp 50 nodes 49 pv b1c3
bestmove b1c3

```
