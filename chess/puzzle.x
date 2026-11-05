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
; them.  The solver's move is right when it is the solution's; in a mate
; puzzle, any move that still mates within the moves left is right too,
; the engine finding the defence to it.
;
; Puzzles come from the set here, made for this bundle, or from lines of
; the lichess puzzle database's CSV (PuzzleId,FEN,Moves,Rating,...,Themes,
; ...), whose FEN is the position before the opponent's move that sets
; the puzzle: that move is made, and the rest are the solution.  Both
; carry the database's theme names (mateIn2, fork, crushing, ...), which
; is what a puzzle is chosen by.
;
; A puzzle is a Vector: 0 the FEN, 1 the solution, 2 its name or "", 3
; its rating or 0, 4 its id, 5 its themes.

(module chess/puzzle)

(import chess/board pos-from-fen pos-fen pos-copy make! move-uci move-parse-uci legal-moves in-check? parse-int)
(import chess/search search-best mate-score? mate-in)
(import x/core/doors int/ str-make str-byte-sub io-display-to-str)
(import x/sys/file)

(def puzzle-make
  (fn (_ fen solution name rating id themes)
    (def z (Vector make 6 ()))
    (Vector set! 0 fen z)
    (Vector set! 1 solution z)
    (Vector set! 2 name z)
    (Vector set! 3 rating z)
    (Vector set! 4 id z)
    (Vector set! 5 themes z)
    z))

(def puzzle-fen (fn (_ z) (Vector ref 0 z)))
(def puzzle-solution (fn (_ z) (Vector ref 1 z)))
(def puzzle-rating (fn (_ z) (Vector ref 3 z)))
(def puzzle-id (fn (_ z) (Vector ref 4 z)))
(def puzzle-themes (fn (_ z) (Vector ref 5 z)))

; How many moves of the solver's the solution takes.
(def puzzle-length (fn (_ z) (+ 1 (int/ (- (List length (puzzle-solution z)) 1) 2))))

; N of the mateInN theme, or 0 for a puzzle that is not a mate.
(def puzzle-mate-in
  (fn (_ z)
    (def t (List find (fn (_ t) (Str8 starts? "mateIn" t)) (puzzle-themes z)))
    (if (null? t) 0 ((fn (_ n) (if (null? n) 0 n)) (parse-int (Str8 slice 6 (Str8 length t) t))))))

(def %headings
  (list (pair "fork" "A fork") (pair "pin" "A pin") (pair "skewer" "A skewer")
        (pair "discoveredAttack" "A discovered attack") (pair "doubleCheck" "Double check")
        (pair "hangingPiece" "A piece left hanging") (pair "trappedPiece" "A trapped piece")
        (pair "promotion" "Promotion") (pair "sacrifice" "A sacrifice")))

; What the puzzle asks, from its themes: Mate in 2, A fork, ..., and its
; name after it when it has one.
(def puzzle-title
  (fn (_ z)
    (def n (puzzle-mate-in z))
    (def themes (puzzle-themes z))
    (def named (List find (fn (_ t) (not (null? (Assoc find t %headings)))) themes))
    (def heading
      (match ((< 0 n) (Str8 append "Mate in " (io-display-to-str n)))
             ((not (null? named)) (rest (Assoc find named %headings)))
             ((null? themes) "A puzzle")
             (#t (first themes))))
    (if (str=? (Vector ref 2 z) "") heading (Str8 append heading ": " (Vector ref 2 z)))))

; Whether puzzle Z has THEME: "" is any puzzle, and mate any mate.
(def puzzle-has?
  (fn (_ z theme)
    (match ((str=? theme "") #t)
           ((str=? theme "mate") (< 0 (puzzle-mate-in z)))
           (#t (List any? (fn (_ t) (str=? t theme)) (puzzle-themes z))))))

; --- the set ------------------------------------------------------------------------
;
; Each entry: the FEN, the solution, the name, the themes; easiest first.
; tests/specs/11-puzzles.spec.md checks that each mate mates in the moves
; its theme says and no fewer, and that each crushing line wins material.

(def %set
  (list
    (list "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1" "a1a8" "The back rank" "mate mateIn1 backRankMate")
    (list "6rk/6pp/8/6N1/8/8/8/6K1 w - - 0 1" "g5f7" "Smothered" "mate mateIn1 smotheredMate")
    (list "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4" "h5f7" "Too soon for the knight" "mate mateIn1 opening")
    (list "k7/8/1K6/8/8/8/8/7Q w - - 0 1" "h1h8" "The king helps" "mate mateIn1 endgame")
    (list "6k1/5ppp/8/8/8/8/Q4PPP/1R4K1 w - - 0 1" "b1b8" "Back rank again" "mate mateIn1 backRankMate")
    (list "4k3/8/4K3/8/8/8/8/R7 w - - 0 1" "a1a8" "The opposition" "mate mateIn1 endgame")
    (list "3k4/8/3K4/8/8/8/8/5Q2 w - - 0 1" "f1f8" "Queen to the edge" "mate mateIn1 endgame")
    (list "6k1/5ppp/r7/8/8/8/5PPP/3RR1K1 w - - 0 1" "d1d8" "Too far to block" "mate mateIn1 backRankMate")
    (list "7k/8/8/8/8/8/R7/1R5K w - - 0 1" "a2a7 h8g8 b1b8" "The ladder" "mate mateIn2 endgame")
    (list "r1b2k1r/ppp1bppp/8/1B1Q4/5q2/2P5/PPP2PPP/R3R1K1 w - - 1 1" "d5d8 e7d8 e1e8" "The queen as bait" "mate mateIn2 backRankMate sacrifice")
    (list "5r1k/6pp/7N/8/8/1Q6/8/6K1 w - - 0 1" "b3g8 f8g8 h6f7" "Philidor's smothered mate" "mate mateIn2 smotheredMate sacrifice")
    (list "rn1qkbnr/ppp2ppp/3p4/4N3/2B1P3/2N5/PPPP1PPP/R1BbK2R w KQkq - 0 6" "c4f7 e8e7 c3d5" "Légal's trap" "mate mateIn2 opening sacrifice")
    (list "k7/8/2K5/8/8/8/8/7R w - - 0 1" "c6c7 a8a7 h1a1" "A waiting move" "mate mateIn2 endgame")
    (list "4k3/8/3K4/8/8/8/8/7R w - - 0 1" "h1f1 e8d8 f1f8" "Take the square" "mate mateIn2 endgame")
    (list "7k/8/5K2/8/8/8/8/1Q6 w - - 0 1" "f6g6 h8g8 b1b8" "The king steps up" "mate mateIn2 endgame")
    (list "r5k1/5Npp/8/8/8/1Q6/8/6K1 w - - 0 1" "f7h6 g8h8 b3g8 a8g8 h6f7" "Philidor's legacy" "mate mateIn3 smotheredMate doubleCheck sacrifice")
    (list "q3k3/8/8/3N4/8/8/5PPP/6K1 w - - 0 1" "d5c7 e8d7 c7a8" "The king and the queen" "crushing fork")
    (list "r5k1/6pp/8/8/8/8/5PPP/3Q2K1 w - - 0 1" "d1d5 g8f8 d5a8" "Check, then the rook" "crushing fork")
    (list "q7/8/8/3k4/8/8/PP6/4KB2 w - - 0 1" "f1g2 d5e6 g2a8" "Through the king" "crushing skewer")
    (list "3k4/1p6/8/8/3q4/8/1P6/R3K3 w - - 0 1" "a1d1 d4d1 e1d1" "The queen cannot move" "crushing pin")
    (list "4k3/8/8/4B3/8/8/4R2K/q7 w - - 0 1" "e5a1" "Out of the way, with check" "crushing discoveredAttack")))

; The puzzles made for this bundle.
(def puzzle-set
  (fn (_)
    (List map (fn (_ e) (puzzle-make (first e) (%words (List ref 1 e)) (List ref 2 e) 0 "" (%words (List ref 3 e))))
      %set)))

(def %words (fn (_ s) (List reject (fn (_ w) (str=? w "")) (Str8 split " " s))))

; --- the lichess database -----------------------------------------------------------

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
                  (puzzle-make (pos-fen p) (rest moves) ""
                    ((fn (_ r) (if (null? r) 0 r)) (parse-int (List ref 3 fields)))
                    (first fields) (%words (List ref 7 fields))))))))))

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

; The puzzles of SOURCE with THEME ("" for any, as puzzle-has? takes it)
; whose rating, when they have one, is from LOW to HIGH, 0 being no bound.
(def puzzle-filter
  (fn (_ source theme low high)
    (def rated?
      (fn (_ r) (if (= r 0) #t (if (if (= low 0) #t (< (- low 1) r)) (if (= high 0) #t (< r (+ high 1))) #f))))
    (fn (self)
      ((fn (_ z) (match ((null? z) ()) ((if (puzzle-has? z theme) (rated? (puzzle-rating z)) #f) z) (#t (self))))
       (source)))))

; The range TEXT gives, LOW-HIGH, LOW- or -HIGH: (low . high), 0 for no
; bound, or () when it does not read as one.
(def puzzle-range
  (fn (_ text)
    (def parts (Str8 split "-" text))
    (def num (fn (_ s) (if (str=? s "") 0 (parse-int s))))
    (if (if (= (List length parts) 2) (not (str=? text "-")) #f)
      ((fn (_ lo hi) (if (if (null? lo) #t (null? hi)) () (pair lo hi))) (num (first parts)) (num (List ref 1 parts)))
      ())))

; --- solving ------------------------------------------------------------------------

; Whether M, made in a copy of P, mates.
(def %mates?
  (fn (_ p m)
    (def q (pos-copy p))
    (make! q m)
    (if (null? (legal-moves q)) (in-check? q) #f)))

; Whether M in P keeps a mate within K of the solver's moves: the engine
; looks for the defence, for 10 s at most, and a mate it has not found
; by then is not there.  A verdict as puzzle-judge answers it.
(def %mate-kept
  (fn (_ p m k left)
    (def q (pos-copy p))
    (make! q m)
    ; a ply past the mate, which the search sees only when it is made
    (def r (if (null? (legal-moves q)) () (search-best q (+ 1 (* 2 (- k 1))) 10000 0 (fn (_) #f) (fn (_ r) ()))))
    (def s (if (null? r) 0 (List ref 1 r)))
    (match
      ((null? r) (if (in-check? q) (pair (lit solved) ()) (pair (lit wrong) left)))
      ((if (mate-score? s) (if (< s 0) (< (- 0 (mate-in s)) k) #f) #f)
        (pair (lit right) (List map move-uci (List ref 5 r))))
      (#t (pair (lit wrong) left)))))

; What the solver's move M in P is for puzzle Z with LEFT of its solution
; still to play, and the line to play on after it: (right . LINE) with
; the reply first, (solved . ()), or (wrong . LEFT).
(def puzzle-judge
  (fn (_ z p m left)
    (def k (+ 1 (int/ (List length left) 2)))
    (match
      ((str=? (move-uci m) (first left))
        (if (null? (rest left)) (pair (lit solved) ()) (pair (lit right) (rest left))))
      ((= 0 (puzzle-mate-in z)) (pair (lit wrong) left))
      ((= k 1) (if (%mates? p m) (pair (lit solved) ()) (pair (lit wrong) left)))
      (#t (%mate-kept p m k left)))))

(provide chess/puzzle puzzle-make puzzle-fen puzzle-solution puzzle-title puzzle-rating puzzle-id
  puzzle-themes puzzle-mate-in puzzle-has? puzzle-filter puzzle-range
  puzzle-length puzzle-set puzzle-from-csv puzzle-judge puzzle-list-source puzzle-file-source)
