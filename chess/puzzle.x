; # x-chess -- a chess engine on x-lang
;
; ## chess/puzzle.x -- puzzles: a position, the moves that solve it
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A puzzle is a position with the side to move the solver's, and its
; solution in long algebraic: the solver's moves with the replies between
; them.  The solver's move is right when it is the solution's, or, where
; the solution mates with it, when it mates too.
;
; Puzzles come from the set here, made for this bundle, or from lines of
; the lichess puzzle database's CSV (PuzzleId,FEN,Moves,Rating,...,Themes,
; ...), whose FEN is the position before the opponent's move that sets
; the puzzle: that move is made, and the rest are the solution.
;
; A puzzle is a Vector: 0 the FEN, 1 the solution, 2 its title, 3 its
; rating or 0, 4 its id.

(module chess/puzzle)

(import chess/board pos-from-fen pos-fen make! move-uci move-parse-uci legal-moves in-check? parse-int)
(import x/core/doors int/ str-make str-byte-sub)
(import x/sys/file)

(def puzzle-make
  (fn (_ fen solution title rating id)
    (def z (Vector make 5 ()))
    (Vector set! 0 fen z)
    (Vector set! 1 solution z)
    (Vector set! 2 title z)
    (Vector set! 3 rating z)
    (Vector set! 4 id z)
    z))

(def puzzle-fen (fn (_ z) (Vector ref 0 z)))
(def puzzle-solution (fn (_ z) (Vector ref 1 z)))
(def puzzle-title (fn (_ z) (Vector ref 2 z)))
(def puzzle-rating (fn (_ z) (Vector ref 3 z)))
(def puzzle-id (fn (_ z) (Vector ref 4 z)))

; How many moves of the solver's the solution takes.
(def puzzle-length (fn (_ z) (+ 1 (int/ (- (List length (puzzle-solution z)) 1) 2))))

; --- the set ------------------------------------------------------------------------

(def %set
  (list
    (list "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1" "a1a8" "The back rank" "Mate in 1")
    (list "6rk/6pp/8/6N1/8/8/8/6K1 w - - 0 1" "g5f7" "Smothered" "Mate in 1")
    (list "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4" "h5f7" "Too soon for the knight" "Mate in 1")
    (list "k7/8/1K6/8/8/8/8/7Q w - - 0 1" "h1h8" "The king helps" "Mate in 1")
    (list "7k/8/8/8/8/8/R7/1R5K w - - 0 1" "a2a7 h8g8 b1b8" "The ladder" "Mate in 2")
    (list "6k1/5ppp/8/8/8/8/Q4PPP/1R4K1 w - - 0 1" "b1b8" "Back rank again" "Mate in 1")
    (list "4k3/8/4K3/8/8/8/8/R7 w - - 0 1" "a1a8" "The opposition" "Mate in 1")
    (list "3k4/8/3K4/8/8/8/8/5Q2 w - - 0 1" "f1f8" "Queen to the edge" "Mate in 1")
    (list "6k1/5ppp/r7/8/8/8/5PPP/3RR1K1 w - - 0 1" "d1d8" "Too far to block" "Mate in 1")))

; The puzzles made for this bundle.
(def puzzle-set
  (fn (_)
    (List map (fn (_ e) (puzzle-make (first e) (%words (List ref 1 e))
                          (Str8 append (List ref 3 e) ": " (List ref 2 e)) 0 ""))
      %set)))

(def %words (fn (_ s) (List reject (fn (_ w) (str=? w "")) (Str8 split " " s))))

; --- the lichess database -----------------------------------------------------------

; The title its themes give a lichess puzzle: mate in N, or the first theme.
(def %title
  (fn (_ themes)
    (def mate (List find (fn (_ t) (Str8 starts? "mateIn" t)) themes))
    (match
      ((not (null? mate)) (Str8 append "Mate in " (Str8 slice 6 (Str8 length mate) mate)))
      ((null? themes) "A puzzle")
      (#t (first themes)))))

; The puzzle LINE of the lichess CSV holds, or () when it holds none (the
; header, or a line that does not read).
(def puzzle-from-csv
  (fn (_ line)
    (def fields (Str8 split "," line))
    (guard (e ())
      (if (< (List length fields) 8) ()
        (do (def p (pos-from-fen (List ref 1 fields)))
            (def moves (%words (List ref 2 fields)))
            (def setup (move-parse-uci p (first moves)))
            (if (null? setup) ()
              (do (make! p setup)
                  (puzzle-make (pos-fen p) (rest moves) (%title (%words (List ref 7 fields)))
                    ((fn (_ r) (if (null? r) 0 r)) (parse-int (List ref 3 fields)))
                    (first fields)))))))))

; --- sources ------------------------------------------------------------------------
;
; A source is a function of no arguments answering the next puzzle, or ()
; when there are no more.

(def puzzle-list-source
  (fn (_ zs)
    (def left zs)
    (fn (_) (if (null? left) () ((fn (_ z) (set! left (rest left)) z) (first left))))))

; The puzzles of the lichess CSV at PATH, read a block at a time as they
; are asked for: the database runs to millions of lines.  Raises an io
; Err when the file cannot be opened.
(def puzzle-file-source
  (fn (_ path)
    (def fd (File open path (lit rdonly)))
    (when (< fd 0) (Err raise (lit io) (Str8 append "cannot open " path) path))
    ; whole lines not yet taken, and the start of the next
    (def lines ())
    (def part "")
    (def done #f)
    (def fill!
      (fn (_)
        (def buf (str-make 65536))
        (def n (File read fd buf 65536))
        (if (< 0 n)
          ((fn (_ ls) (set! lines (List init ls)) (set! part (List last ls)))
           (Str8 split "\n" (Str8 append part (str-byte-sub buf 0 n))))
          (do (set! done #t) (File close fd)))))
    (def line
      (fn (self)
        (match
          ((not (null? lines)) ((fn (_ l) (set! lines (rest lines)) l) (first lines)))
          (done (if (str=? part "") () ((fn (_ l) (set! part "") l) part)))
          (#t (do (fill!) (self))))))
    (fn (self)
      (def l (line))
      (match ((null? l) ())
             (#t ((fn (_ z) (if (null? z) (self) z)) (puzzle-from-csv (Str8 replace "\r" "" l))))))))

; --- solving ------------------------------------------------------------------------

; Whether M, made in P, mates.
(def %mates?
  (fn (_ p m)
    (make! p m)
    (def r (if (null? (legal-moves p)) (in-check? p) #f))
    r))

; What the solver's move M in P is for puzzle Z with its solution from
; K on still to play: right (the solution's move, or a mate where the
; solution mates), mate (it mates and so ends the puzzle) or wrong.
(def puzzle-judge
  (fn (_ z p m left)
    (def want (first left))
    (def q (pos-from-fen (pos-fen p)))
    (match
      ((str=? (move-uci m) want) (if (null? (rest left)) (lit solved) (lit right)))
      ((if (%mates? q m) (%mates? (pos-from-fen (pos-fen p)) (move-parse-uci p want)) #f) (lit solved))
      (#t (lit wrong)))))

(provide chess/puzzle puzzle-make puzzle-fen puzzle-solution puzzle-title puzzle-rating puzzle-id
  puzzle-length puzzle-set puzzle-from-csv puzzle-judge puzzle-list-source puzzle-file-source)
