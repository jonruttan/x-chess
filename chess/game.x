; # x-chess -- a chess engine on x-lang
;
; ## chess/game.x -- a game: its moves, take-backs, and how it ends
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A game is a position and what led to it: the FEN it started from, the
; moves made since, last first, and the repetition key of every
; position on the way, the current one first.

(module chess/game)

(import chess/board fen-start pos-from-fen pos-fen pos-key pos-piece pos-half pos-side
  in-check? legal-moves make! unmake! piece-kind pos-full)
(import chess/san moves-san)
(import x/core/doors int& io-display-to-str)

(def %g-pos 0)
(def %g-moves 1)
(def %g-keys 2)
(def %g-start 3)

; A new game from FEN, the start when FEN is ().
(def game-new
  (fn (_ fen)
    (def start (if (null? fen) fen-start fen))
    (def p (pos-from-fen start))
    (def g (Vector make 4 ()))
    (Vector set! %g-pos p g)
    (Vector set! %g-moves () g)
    (Vector set! %g-keys (list (pos-key p)) g)
    (Vector set! %g-start start g)
    g))

(def game-pos (fn (_ g) (Vector ref %g-pos g)))
(def game-start (fn (_ g) (Vector ref %g-start g)))
(def game-fen (fn (_ g) (pos-fen (game-pos g))))

; The moves made, first first.
(def game-moves (fn (_ g) (List reverse (Vector ref %g-moves g))))

; Make M, a legal move, in G.
(def game-play!
  (fn (_ g m)
    (make! (game-pos g) m)
    (Vector set! %g-moves (pair m (Vector ref %g-moves g)) g)
    (Vector set! %g-keys (pair (pos-key (game-pos g)) (Vector ref %g-keys g)) g)
    g))

; Take back the last move: #f when there is none.
(def game-undo!
  (fn (_ g)
    (if (null? (Vector ref %g-moves g)) #f
      (do (unmake! (game-pos g) (first (Vector ref %g-moves g)))
          (Vector set! %g-moves (rest (Vector ref %g-moves g)) g)
          (Vector set! %g-keys (rest (Vector ref %g-keys g)) g)
          #t))))

; How many times the current position has stood in the game.
(def game-repeats
  (fn (_ g)
    (def keys (Vector ref %g-keys g))
    (List length (List filter (fn (_ k) (str=? k (first keys))) keys))))

; Whether neither side has the material to mate: kings alone, or a king
; and one knight or bishop against a king.
(def %bare?
  (fn (_ p)
    (def kinds
      (List map (fn (_ sq) (piece-kind (pos-piece p sq)))
        (List filter (fn (_ sq) (if (= (int& sq 136) 0) (< 0 (pos-piece p sq)) #f)) (List range 0 128))))
    (def others (List filter (fn (_ k) (not (= k 6))) kinds))
    (if (null? others) #t
      (if (null? (rest others)) (if (= (first others) 2) #t (= (first others) 3)) #f))))


; How G stands: () while it goes on, else (RESULT . REASON), the result
; "1-0", "0-1" or "1/2-1/2".
(def game-result
  (fn (_ g)
    (def p (game-pos g))
    (def moves (legal-moves p))
    (match
      ((null? moves)
        (if (in-check? p)
          (pair (if (= (pos-side p) 0) "0-1" "1-0") "checkmate")
          (pair "1/2-1/2" "stalemate")))
      ((< 99 (pos-half p)) (pair "1/2-1/2" "the fifty-move rule"))
      ((< 2 (game-repeats g)) (pair "1/2-1/2" "threefold repetition"))
      ((%bare? p) (pair "1/2-1/2" "insufficient material"))
      (#t ()))))

; The moves as numbered SAN: "1. e4 e5 2. Nf3".
(def game-movetext
  (fn (_ g)
    (def moves (game-moves g))
    (def p (pos-from-fen (game-start g)))
    (def sans (moves-san p moves))
    (def black-first (= (pos-side p) 8))
    (def number (pos-full p))
    (def go
      (fn (self ss n white acc)
        (if (null? ss) (Str8 join " " (List reverse acc))
          (if white
            (self (rest ss) n #f (pair (first ss) (pair (Str8 append (io-display-to-str n) ".") acc)))
            (self (rest ss) (+ n 1) #t (pair (first ss) acc))))))
    (if black-first
      (if (null? sans) ""
        (go (rest sans) (+ number 1) #t (list (first sans) (Str8 append (io-display-to-str number) "..."))))
      (go sans number #t ()))))


; Game G as PGN: TAGS, an alist of names and values, in order, then SetUp
; and FEN when the game did not start from the usual position, a Result
; tag of RESULT ("1-0", "0-1", "1/2-1/2" or "*"), and the movetext
; folded at 79 columns, ending in the result.
(def game-pgn
  (fn (_ g tags result)
    (def all
      (List append tags
        (list (pair "Result" result))
        (if (str=? (game-start g) fen-start) () (list (pair "SetUp" "1") (pair "FEN" (game-start g))))))
    (Str8 append
      (Str8 join "" (List map (fn (_ t) (Str8 append "[" (first t) " \"" (%pgn-quote (rest t)) "\"]\n")) all))
      "\n"
      (%fold-words (List append (List reject (fn (_ w) (str=? w "")) (Str8 split " " (game-movetext g))) (list result)) 79)
      "\n")))

(def %pgn-quote
  (fn (_ s) (Str8 replace "\"" "\\\"" (Str8 replace "\\" "\\\\" s))))

; WORDS joined by spaces, a newline before any that would pass WIDTH.
(def %fold-words
  (fn (_ words width)
    (def go
      (fn (self ws line acc)
        (match
          ((null? ws) (Str8 join "\n" (List reverse (if (str=? line "") acc (pair line acc)))))
          ((str=? line "") (self (rest ws) (first ws) acc))
          ((< width (+ (Str8 length line) 1 (Str8 length (first ws)))) (self ws "" (pair line acc)))
          (#t (self (rest ws) (Str8 append line " " (first ws)) acc)))))
    (go words "" ())))

(provide chess/game game-new game-pos game-start game-fen game-moves game-play! game-undo!
  game-repeats game-result game-movetext game-pgn)
