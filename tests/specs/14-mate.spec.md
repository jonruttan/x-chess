# Mates by forcing moves
@weight 3

chess/mate: the shortest mate in a number of moves, found by the
attacker's checks (and its quiet moves at its last two), and whether
every defence still loses to one.

## finding a mate

### each built-in mate, no shorter than its title and ending in mate

```chess
(def mated?
  (fn (_ fen line)
    (def p (pos-from-fen fen))
    (List for-each (fn (_ m) (make! p m)) line)
    (if (null? (legal-moves p)) (in-check? p) #f)))
(write (List map
  (fn (_ z)
    (def line (mate-find (pos-from-fen (puzzle-fen z)) (puzzle-mate-in z) 0))
    (list (puzzle-mate-in z) (List length line) (mated? (puzzle-fen z) line)))
  (List filter (fn (_ z) (puzzle-has? z "mate")) (puzzle-set))))
```
---
    ((1 1 #t) (1 1 #t) (1 1 #t) (1 1 #t) (1 1 #t) (1 1 #t) (1 1 #t) (1 1 #t) (2 3 #t) (2 3 #t) (2 3 #t) (2 3 #t) (2 3 #t) (2 3 #t) (2 3 #t) (3 5 #t))

### a quiet first move, the king's step, found in a mate in two

```chess
(def p (pos-from-fen "k7/8/2K5/8/8/8/8/7R w - - 0 1"))
(write (List map move-uci (mate-find p 2 0)))
```
---
    ("c6c7" "a8a7" "h1a1")

### none in two where there is none, and none when the time runs out

```chess
(write (list (mate-find (pos-from-fen fen-start) 2 0)
             (mate-find (pos-from-fen "r5k1/5Npp/8/8/8/1Q6/8/6K1 w - - 0 1") 3 1)))
```
---
    (() ())

### mates in five the bundle ships: those by checks found in five, the others not

```chess
(def next (puzzle-file-source (puzzle-library) "mateIn5" 1400 1799))
(def five (List map (fn (_ i) (next)) (List range 0 4)))
(write (List map
  (fn (_ z)
    (def line (mate-find (pos-from-fen (puzzle-fen z)) 5 20000))
    (Heap collect)
    (list (puzzle-id z) (List length line)))
  five))
```
---
    (("B9jGX" 0) ("e5s5a" 0) ("StxKE" 9) ("Ux9r1" 9))

## a defence

### every reply to the ladder's other rook move still loses in one; a slower move lets the king out

```chess
(def after
  (fn (_ text)
    (def p (pos-from-fen "7k/8/8/8/8/8/R7/1R5K w - - 0 1"))
    (make! p (move-parse p text))
    p))
(write (list (List map move-uci (mate-forced (after "Rb7") 1 0))
             (mate-forced (after "Ra3") 1 0)
             (mate-forced (after "Ra8") 0 0)))
```
---
    (("h8g8" "a2a8") 'escape 'escape)
