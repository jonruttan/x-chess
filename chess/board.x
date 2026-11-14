; # x-chess -- a chess engine on x-lang
;
; ## chess/board.x -- the position, its moves, and FEN
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The board is 0x88: a square is rank * 16 + file, so a1 is 0, h1 7, a8
; 112, and a square is off the board exactly when (sq & 0x88) is not 0.
; A step off any edge lands on such a square, which is the whole of the
; edge test.
;
; A position is one Vector whose raw slots are read with the obj doors:
; slot sq + 1 holds the piece on sq, and the slots past the board hold
; the side to move, the castling rights, the en passant square, the
; clocks, the kings' squares and the undo list.  A piece is its kind, 1
; pawn to 6 king, plus 8 for black; 0 is an empty square.  The side to
; move is 0 for white and 8 for black, the colour bit of its pieces.
;
; A move is an integer: from + to * 128 + promotion * 16384 + flags *
; 262144, the flags 1 for an en passant capture, 2 for castling and 4
; for a pawn's double step.  Nothing is allocated to make or unmake a
; move but the one pair that holds what unmaking needs back.

(module chess/board)

(import x/sys/gc)
(import x/num/random)
(import chess/pst pst-middle pst-end pst-phase)
(import x/core/doors int+ int- int* int< int= int& int| int>> obj-ref obj-set!
  str-byte-ref str-byte-len str-byte-sub io-display-to-str)

; --- pieces and slots ----------------------------------------------------------

(def PAWN 1)
(def KNIGHT 2)
(def BISHOP 3)
(def ROOK 4)
(def QUEEN 5)
(def KING 6)
(def WHITE 0)
(def BLACK 8)

(def %f-side 129)
(def %f-castle 130)
(def %f-ep 131)
(def %f-half 132)
(def %f-full 133)
(def %f-wking 134)
(def %f-bking 135)
(def %f-undo 136)
(def %f-mg 137)
(def %f-eg 138)
(def %f-phase 139)
(def %f-zlo 140)
(def %f-zhi 141)
(def %slots 141)

(def pos-piece (fn (_ p sq) (obj-ref p (int+ sq 1))))
(def pos-side (fn (_ p) (obj-ref p %f-side)))
(def pos-castle (fn (_ p) (obj-ref p %f-castle)))
(def pos-ep (fn (_ p) (obj-ref p %f-ep)))
(def pos-half (fn (_ p) (obj-ref p %f-half)))
(def pos-full (fn (_ p) (obj-ref p %f-full)))
(def pos-king (fn (_ p side) (obj-ref p (match ((int= side 0) %f-wking) (#t %f-bking)))))
(def pos-middle (fn (_ p) (obj-ref p %f-mg)))
(def pos-end (fn (_ p) (obj-ref p %f-eg)))
(def pos-phase (fn (_ p) (obj-ref p %f-phase)))
(def pos-hash-lo (fn (_ p) (obj-ref p %f-zlo)))
(def pos-hash-hi (fn (_ p) (obj-ref p %f-zhi)))

(def piece-kind (fn (_ pc) (int& pc 7)))
(def piece-colour (fn (_ pc) (int& pc 8)))

; An empty position: no pieces, white to move, nothing to undo.
(def %pos-blank
  (fn (_)
    (def p (Vector make %slots 0))
    (obj-set! p %f-ep -1)
    (obj-set! p %f-full 1)
    (obj-set! p %f-undo ())
    p))

; A copy of P that moves apart from it.  The undo list is shared: it is
; pairs that are never written, only pushed onto and popped.
(def pos-copy
  (fn (_ p)
    (def q (Vector make %slots 0))
    (def go (fn (self i) (when (int< i (int+ %slots 1)) (obj-set! q i (obj-ref p i)) (self (int+ i 1)))))
    (go 1)
    q))

; --- squares and text ------------------------------------------------------------

(def sq-file (fn (_ sq) (int& sq 7)))
(def sq-rank (fn (_ sq) (int>> sq 4)))
(def sq-make (fn (_ file rank) (int+ (int* rank 16) file)))

(def %files "abcdefgh")
(def %ranks "12345678")

(def sq-name
  (fn (_ sq)
    (Str8 append (str-byte-sub %files (sq-file sq) 1) (str-byte-sub %ranks (sq-rank sq) 1))))

; The index of byte B in S, or -1.
(def %byte-index
  (fn (_ s b)
    (def n (str-byte-len s))
    (def go (fn (self i) (match ((int= i n) -1) ((int= (str-byte-ref s i) b) i) (#t (self (int+ i 1))))))
    (go 0)))

; The square named at offset I of S, "e4", or -1.
(def sq-parse
  (fn (_ s i)
    (if (int< (str-byte-len s) (int+ i 2)) -1
      ((fn (_ f r) (if (if (int< f 0) #t (int< r 0)) -1 (sq-make f r)))
       (%byte-index %files (str-byte-ref s i))
       (%byte-index %ranks (str-byte-ref s (int+ i 1)))))))

; FEN's letters, white's in upper case, at the index of their code.
(def %piece-letters ".PNBRQK..pnbrqk")

(def piece-letter (fn (_ pc) (str-byte-sub %piece-letters pc 1)))

; --- moves -------------------------------------------------------------------------

(def FLAG-EP 1)
(def FLAG-CASTLE 2)
(def FLAG-DOUBLE 4)

(def move-make
  (fn (_ from to promo flags)
    (int+ from (int+ (int* to 128) (int+ (int* promo 16384) (int* flags 262144))))))
(def move-from (fn (_ m) (int& m 127)))
(def move-to (fn (_ m) (int& (int>> m 7) 127)))
(def move-promo (fn (_ m) (int& (int>> m 14) 15)))
(def move-flags (fn (_ m) (int>> m 18)))

; The move in UCI's long algebraic: e2e4, e7e8q.
(def move-uci
  (fn (_ m)
    (def promo (move-promo m))
    (Str8 append (sq-name (move-from m)) (sq-name (move-to m))
      (if (int= promo 0) "" (str-byte-sub ".pnbrqk" promo 1)))))

; --- FEN -------------------------------------------------------------------------------

(def fen-start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

(def %fen-bad (fn (_ fen why) (Err raise (lit chess) (Str8 append "bad FEN: " why) fen)))

(def parse-int
  (fn (_ s) (guard (e ()) ((prim-ref (lit convert) (lit to)) s (Type named INTEGER) 10))))

; The placement field of FEN onto P: ranks 8 to 1, files a to h.
(def %fen-place!
  (fn (_ p fen s)
    (def n (str-byte-len s))
    (def go
      (fn (self i rank file)
        (if (int= i n)
          (match ((not (int= file 8)) (%fen-bad fen "a rank is not 8 squares"))
                 ((not (int= rank 0)) (%fen-bad fen "the board is not 8 ranks of 8"))
                 (#t ()))
          (do
            (def b (str-byte-ref s i))
            (def pc (%byte-index %piece-letters b))
            (match
              ((int= b 47) ; /
                (if (int= file 8) (self (int+ i 1) (int- rank 1) 0) (%fen-bad fen "a rank is not 8 squares")))
              ((if (int< 48 b) (int< b 57) #f) ; 1-8
                (self (int+ i 1) rank (int+ file (int- b 48))))
              ((if (int< 0 pc) (int< file 8) #f)
                (if (int< rank 0) (%fen-bad fen "more than 8 ranks")
                  (do (obj-set! p (int+ (sq-make file rank) 1) pc)
                      (when (int= pc 6) (obj-set! p %f-wking (sq-make file rank)))
                      (when (int= pc 14) (obj-set! p %f-bking (sq-make file rank)))
                      (self (int+ i 1) rank (int+ file 1)))))
              (#t (%fen-bad fen "a rank is not 8 squares")))))))
    (go 0 7 0)))

(def %fen-count
  (fn (_ p pc)
    (List fold (fn (_ n sq) (if (int= (obj-ref p (int+ sq 1)) pc) (int+ n 1) n)) 0 (List range 0 128))))

; The position FEN describes.  The move counters may be left off.
(def pos-from-fen
  (fn (_ fen)
    (def fields (List reject (fn (_ f) (str=? f "")) (Str8 split " " (Str8 trim fen))))
    (when (int< (List length fields) 4) (%fen-bad fen "fewer than 4 fields"))
    (def p (%pos-blank))
    (%fen-place! p fen (first fields))
    (unless (if (int= (%fen-count p 6) 1) (int= (%fen-count p 14) 1) #f)
      (%fen-bad fen "each side needs one king"))
    (when (List any? (fn (_ f) (if (int= (obj-ref p (int+ f 1)) 1) #t (if (int= (obj-ref p (int+ f 1)) 9) #t
                                 (if (int= (obj-ref p (int+ f 113)) 1) #t (int= (obj-ref p (int+ f 113)) 9)))))
            (List range 0 8))
      (%fen-bad fen "a pawn on the first or last rank"))
    (def side (List ref 1 fields))
    (obj-set! p %f-side
      (match ((str=? side "w") 0) ((str=? side "b") 8) (#t (%fen-bad fen "the side is not w or b"))))
    (def cs (List ref 2 fields))
    (obj-set! p %f-castle
      (if (str=? cs "-") 0
        (List fold (fn (_ acc b)
                     (def k (%byte-index "KQkq" b))
                     (if (int< k 0) (%fen-bad fen "castling is not KQkq or -") (int| acc (int>> 8 (int- 3 k)))))
          0 (List map (fn (_ i) (str-byte-ref cs i)) (List range 0 (str-byte-len cs))))))
    (def ep (List ref 3 fields))
    (obj-set! p %f-ep
      (if (str=? ep "-") -1
        ((fn (_ sq) (if (int< sq 0) (%fen-bad fen "the en passant square") sq)) (sq-parse ep 0))))
    (def num (fn (_ i dflt) (if (int< i (List length fields)) ((fn (_ n) (if (null? n) dflt n)) (parse-int (List ref i fields))) dflt)))
    (obj-set! p %f-half (num 4 0))
    (obj-set! p %f-full (num 5 1))
    (%score! p)
    (%z-start! p)
    p))

; FEN's first field, P's pieces.
(def %fen-placement
  (fn (_ p)
    (def rank-text
      (fn (self rank file empty acc)
        (if (int= file 8)
          (if (int= empty 0) acc (pair (str-byte-sub %ranks (int- empty 1) 1) acc))
          ((fn (_ pc)
             (if (int= pc 0) (self rank (int+ file 1) (int+ empty 1) acc)
               (self rank (int+ file 1) 0
                 (pair (piece-letter pc) (if (int= empty 0) acc (pair (str-byte-sub %ranks (int- empty 1) 1) acc))))))
           (obj-ref p (int+ (sq-make file rank) 1))))))
    (Str8 join "/"
      (List map (fn (_ rank) (Str8 join "" (List reverse (rank-text rank 0 0 ()))))
        (list 7 6 5 4 3 2 1 0)))))

; The first four fields of FEN: what makes positions the same for
; repetition.
(def pos-key
  (fn (_ p)
    (def c (obj-ref p %f-castle))
    (def castle
      (Str8 append (if (int= (int& c 1) 0) "" "K") (if (int= (int& c 2) 0) "" "Q")
                   (if (int= (int& c 4) 0) "" "k") (if (int= (int& c 8) 0) "" "q")))
    (Str8 append (%fen-placement p) (if (int= (obj-ref p %f-side) 0) " w " " b ")
      (if (str=? castle "") "-" castle) " "
      (if (int< (obj-ref p %f-ep) 0) "-" (sq-name (obj-ref p %f-ep))))))

(def pos-fen
  (fn (_ p)
    (Str8 append (pos-key p) " " (io-display-to-str (obj-ref p %f-half)) " "
      (io-display-to-str (obj-ref p %f-full)))))

; --- attacks -------------------------------------------------------------------------------

(def %knight-steps (list 33 31 18 14 -33 -31 -18 -14))
(def %king-steps (list 1 -1 16 -16 15 17 -15 -17))
(def %diagonal-steps (list 15 17 -15 -17))
(def %straight-steps (list 1 -1 16 -16))

; The hot paths below branch with match alone: match is the engine's
; primitive, while if, when and unless are operatives that evaluate
; their test through eval, a cost paid at every square looked at.

; The piece on SQ, or 7 when SQ is off the board: 7 is no piece's code.
(def %at
  (fn (_ p sq) (match ((int= (int& sq 136) 0) (obj-ref p (int+ sq 1))) (#t 7))))

; Whether a step from SQ by each of STEPS lands on PC.
(def %step-hits?
  (fn (self p sq steps pc)
    (match ((null? steps) #f)
           ((int= (%at p (int+ sq (first steps))) pc) #t)
           (#t (self p sq (rest steps) pc)))))

; The first piece a ray from S by D meets: 7 when it leaves the board.
(def %ray-first
  (fn (self p s d)
    (def pc (%at p s))
    (match ((int= pc 0) (self p (int+ s d) d)) (#t pc))))

; A match clause takes its first form alone, so where a clause needs a
; value twice the value is handed to a function of its own.

(def %ray-met?
  (fn (self p sq steps a b pc)
    (match ((int= pc a) #t)
           ((int= pc b) #t)
           (#t (%ray-hits? p sq (rest steps) a b)))))

; Whether a ray from SQ by each of STEPS first meets A or B.
(def %ray-hits?
  (fn (self p sq steps a b)
    (match
      ((null? steps) #f)
      (#t (%ray-met? p sq steps a b (%ray-first p (int+ sq (first steps)) (first steps)))))))

; Whether a pawn of side BY attacks SQ.
(def %pawn-hits?
  (fn (_ p sq by)
    (match
      ((int= by 0) (match ((int= (%at p (int- sq 15)) 1) #t) (#t (int= (%at p (int- sq 17)) 1))))
      (#t (match ((int= (%at p (int+ sq 15)) 9) #t) (#t (int= (%at p (int+ sq 17)) 9)))))))

; Whether side BY attacks SQ.
(def attacked?
  (fn (_ p sq by)
    (match
      ((%pawn-hits? p sq by) #t)
      ((%step-hits? p sq %knight-steps (int+ 2 by)) #t)
      ((%step-hits? p sq %king-steps (int+ 6 by)) #t)
      ((%ray-hits? p sq %diagonal-steps (int+ 3 by) (int+ 5 by)) #t)
      ((%ray-hits? p sq %straight-steps (int+ 4 by) (int+ 5 by)) #t)
      (#t #f))))

; Whether the side to move is in check.
(def in-check?
  (fn (_ p)
    (def side (obj-ref p %f-side))
    (attacked? p (obj-ref p (match ((int= side 0) %f-wking) (#t %f-bking))) (int- 8 side))))

; --- generating moves --------------------------------------------------------------------
;
; Pseudo-legal: each piece's moves by its rules, a move that leaves its
; own king attacked included; make! refuses those.  With CAPTURES only
; captures and promotions are made, for the quiescence search.

; A pawn's move from SQ to TO onto ACC: the four promotions when TO is
; on the last rank, the queen's alone with CAPTURES.
(def %pawn-add
  (fn (_ sq to flags captures acc)
    (def m (int+ sq (int+ (int* to 128) (int* flags 262144))))
    (match
      ((match ((int< to 8) #t) ((int< 111 to) #t) (#t #f))
        (match
          (captures (pair (int+ m 81920) acc))
          (#t (pair (int+ m 81920) (pair (int+ m 65536) (pair (int+ m 49152) (pair (int+ m 32768) acc)))))))
      (#t (pair m acc)))))

(def %pawn-took
  (fn (_ p sq to pc side captures acc)
    (match
      ((int= pc 0) (match ((int= to (obj-ref p %f-ep)) (pair (int+ sq (int+ (int* to 128) 262144)) acc)) (#t acc)))
      ((int= (int& pc 8) side) acc)
      (#t (%pawn-add sq to 0 captures acc)))))

; A pawn of SIDE on SQ taking on TO, onto ACC.
(def %pawn-take
  (fn (_ p sq to side captures acc)
    (match
      ((int= (int& to 136) 0) (%pawn-took p sq to (obj-ref p (int+ to 1)) side captures acc))
      (#t acc))))

; A pawn of SIDE on SQ stepping forward, onto ACC.
(def %pawn-push
  (fn (_ p sq one up side captures acc)
    (match
      ((int< 0 (obj-ref p (int+ one 1))) acc)
      ((match ((int< one 8) #t) ((int< 111 one) #t) (#t #f)) (%pawn-add sq one 0 captures acc))
      (captures acc)
      ((match ((int= side 0) (int= (int>> sq 4) 1)) (#t (int= (int>> sq 4) 6)))
        (match
          ((int= (obj-ref p (int+ (int+ one up) 1)) 0)
            (pair (int+ sq (int+ (int* (int+ one up) 128) 1048576)) (pair (int+ sq (int* one 128)) acc)))
          (#t (pair (int+ sq (int* one 128)) acc))))
      (#t (pair (int+ sq (int* one 128)) acc)))))

(def %pawn-moves
  (fn (_ p sq side captures acc)
    (def up (match ((int= side 0) 16) (#t -16)))
    (def one (int+ sq up))
    (%pawn-take p sq (int+ one 1) side captures
      (%pawn-take p sq (int- one 1) side captures
        (%pawn-push p sq one up side captures acc)))))

(def %step-onto
  (fn (_ sq to pc side captures acc)
    (match ((int= pc 0) (match (captures acc) (#t (pair (int+ sq (int* to 128)) acc))))
           ((int= (int& pc 8) side) acc)
           (#t (pair (int+ sq (int* to 128)) acc)))))

; A step from SQ to TO onto ACC, unless TO is off the board or SIDE's.
(def %step-to
  (fn (_ p sq to side captures acc)
    (match
      ((int= (int& to 136) 0) (%step-onto sq to (obj-ref p (int+ to 1)) side captures acc))
      (#t acc))))

(def %step-moves
  (fn (self p sq side steps captures acc)
    (match
      ((null? steps) acc)
      (#t (self p sq side (rest steps) captures (%step-to p sq (int+ sq (first steps)) side captures acc))))))

(def %ray-onto
  (fn (_ p sq to d pc side captures acc)
    (match ((int= pc 0)
             (%ray-moves p sq (int+ to d) d side captures
               (match (captures acc) (#t (pair (int+ sq (int* to 128)) acc)))))
           ((int= (int& pc 8) side) acc)
           (#t (pair (int+ sq (int* to 128)) acc)))))

; The moves along the ray from SQ by D, from TO on, onto ACC.
(def %ray-moves
  (fn (_ p sq to d side captures acc)
    (match
      ((int= (int& to 136) 0) (%ray-onto p sq to d (obj-ref p (int+ to 1)) side captures acc))
      (#t acc))))

(def %slide-moves
  (fn (self p sq side steps captures acc)
    (match
      ((null? steps) acc)
      (#t (self p sq side (rest steps) captures
            (%ray-moves p sq (int+ sq (first steps)) (first steps) side captures acc))))))

; Whether the files FS of the back rank from BASE are empty.
(def %castle-empty?
  (fn (self p base fs)
    (match ((null? fs) #t)
           ((int= (obj-ref p (int+ base (int+ (first fs) 1))) 0) (self p base (rest fs)))
           (#t #f))))

; Whether ENEMY attacks none of the files FS of the back rank from BASE.
(def %castle-safe?
  (fn (self p base fs enemy)
    (match ((null? fs) #t)
           ((attacked? p (int+ base (first fs)) enemy) #f)
           (#t (self p base (rest fs) enemy)))))

; Whether the side whose back rank starts at BASE may castle by the
; rights bit BIT: its ROOK in slot SLOT from BASE, the files EMPTY empty
; and the files SAFE unattacked.
(def %castle-open?
  (fn (_ p base rights bit slot rook empty safe enemy)
    (match ((int= (int& rights bit) 0) #f)
           ((int= (obj-ref p (int+ base slot)) rook)
             (match ((%castle-empty? p base empty) (%castle-safe? p base safe enemy)) (#t #f)))
           (#t #f))))

(def %short-empty (list 5 6))
(def %short-safe (list 4 5 6))
(def %long-empty (list 3 2 1))
(def %long-safe (list 4 3 2))

(def %castle-moves
  (fn (_ p side acc)
    (def c (obj-ref p %f-castle))
    (def base (match ((int= side 0) 0) (#t 112)))
    (def rights (match ((int= side 0) c) (#t (int>> c 2))))
    (def enemy (int- 8 side))
    (def rook (int+ 4 side))
    (def short
      (match ((%castle-open? p base rights 1 8 rook %short-empty %short-safe enemy)
               (pair (move-make (int+ base 4) (int+ base 6) 0 2) acc))
             (#t acc)))
    (match ((%castle-open? p base rights 2 1 rook %long-empty %long-safe enemy)
             (pair (move-make (int+ base 4) (int+ base 2) 0 2) short))
           (#t short))))

(def %kind-moves
  (fn (_ p sq kind side captures acc)
    (match ((int= kind 1) (%pawn-moves p sq side captures acc))
           ((int= kind 2) (%step-moves p sq side %knight-steps captures acc))
           ((int= kind 3) (%slide-moves p sq side %diagonal-steps captures acc))
           ((int= kind 4) (%slide-moves p sq side %straight-steps captures acc))
           ((int= kind 5) (%slide-moves p sq side %king-steps captures acc))
           (#t (%step-moves p sq side %king-steps captures acc)))))

; The moves of the piece PC of SIDE on SQ, onto ACC.
(def %piece-moves
  (fn (_ p sq pc side captures acc)
    (match ((int= pc 0) acc)
           ((int= (int& pc 8) side) (%kind-moves p sq (int& pc 7) side captures acc))
           (#t acc))))

(def %gen-from
  (fn (self p sq side captures acc)
    (match ((int< 127 sq) acc)
           ((int= (int& sq 8) 8) (self p (int+ sq 8) side captures acc))
           (#t (self p (int+ sq 1) side captures
                 (%piece-moves p sq (obj-ref p (int+ sq 1)) side captures acc))))))

; Every pseudo-legal move of the side to move; with CAPTURES only the
; captures and promotions.
(def gen-moves
  (fn (_ p captures)
    (def side (obj-ref p %f-side))
    (def moves (%gen-from p 0 side captures ()))
    (match (captures moves) (#t (%castle-moves p side moves)))))

; --- making and unmaking ---------------------------------------------------------------
;
; The castling rights a move keeps, by the squares it leaves and lands
; on: moving a king or rook, or taking a rook, loses that side's rights.
(def %castle-keep
  (do (def v (Vector make 128 15))
      (List for-each (fn (_ e) (obj-set! v (int+ (first e) 1) (rest e)))
        (list (pair 0 13) (pair 7 14) (pair 4 12) (pair 112 7) (pair 119 11) (pair 116 3)))
      v))

; --- the position's hash ------------------------------------------------------------
;
; A Zobrist hash, kept as moves are made and unmade: the exclusive or of
; a number for each piece on its square, for the castling rights, for
; the en passant square and for black to move.  It is two 16-bit limbs,
; so it is the same on an engine of any word width.  The numbers are
; drawn once from a fixed seed, each a pair of limbs: piece PC on SQ at
; PC * 128 + SQ + 1 in %z (no piece is (0 . 0)), and in %zf the
; castling rights C at C + 1, the en passant square E (-1 for none) at
; E + 18, and black to move at 146, also kept as %z-black.

(def %xor (prim-ref (lit int) (lit ^)))

(def %z-draw
  (fn (_ r n first)
    (def v (Vector make n (pair 0 0)))
    (List for-each (fn (_ i) (obj-set! v i (pair (r int 65536) (r int 65536)))) (List range first (int+ n 1)))
    v))

(def %z-random (Random sw 1070372))
(def %z (%z-draw %z-random 2048 129))
(def %zf (%z-draw %z-random 146 1))
(obj-set! %zf 17 (pair 0 0))
(def %z-black (obj-ref %zf 146))

; A number below N drawn at random, from a generator seeded by the time
; of day the first time one is asked for.
(def %random ())
(def chess-roll
  (fn (_ n)
    (when (null? %random)
      (def tod (Sys time-of-day))
      (set! %random (Random sw (int+ (int* (int& (first tod) 65535) 1000003) (rest tod)))))
    (%random int n)))

; Exclusive-or the limbs LO and HI into P's hash.
(def %z-xor!
  (fn (_ p lo hi)
    (obj-set! p %f-zlo (%xor (obj-ref p %f-zlo) lo))
    (obj-set! p %f-zhi (%xor (obj-ref p %f-zhi) hi))))

; Exclusive-or the flag numbers at A and B into P's hash.
(def %z-flags!
  (fn (_ p a b)
    (def x (obj-ref %zf a))
    (def y (obj-ref %zf b))
    (%z-xor! p (%xor (first x) (first y)) (%xor (rest x) (rest y)))))

; Exclusive-or the number of PC on SQ into P's hash.
(def %z-piece!
  (fn (_ p pc sq)
    ((fn (_ z) (%z-xor! p (first z) (rest z))) (obj-ref %z (int+ (int* pc 128) (int+ sq 1))))))

; P's hash, from none: after a FEN has set the position.
(def %z-start!
  (fn (_ p)
    (List for-each (fn (_ sq) (%z-piece! p (obj-ref p (int+ sq 1)) sq))
      (List filter (fn (_ sq) (int= (int& sq 136) 0)) (List range 0 128)))
    (%z-flags! p (int+ (obj-ref p %f-castle) 1) (int+ (obj-ref p %f-ep) 18))
    (match ((int= (obj-ref p %f-side) 8) (%z-xor! p (first %z-black) (rest %z-black))) (#t ()))))

; A move made or unmade: SIDE's PC from FROM, PLACED on TO, CAP the piece
; it took there, FLAGS the move's, and CASTLE and EP the flags on the
; other side of the move from P's.  Making and unmaking change the hash
; by the same numbers, so each answers it here alike.
(def %z-move!
  (fn (_ p from to pc placed cap side flags castle ep)
    (def a (obj-ref %z (int+ (int* pc 128) (int+ from 1))))
    (def b (obj-ref %z (int+ (int* placed 128) (int+ to 1))))
    (def c (obj-ref %z (int+ (int* cap 128) (int+ to 1))))
    (obj-set! p %f-zlo
      (%xor (obj-ref p %f-zlo) (%xor (%xor (first a) (first %z-black)) (%xor (first b) (first c)))))
    (obj-set! p %f-zhi
      (%xor (obj-ref p %f-zhi) (%xor (%xor (rest a) (rest %z-black)) (%xor (rest b) (rest c)))))
    (match
      ((int= flags 0) ())
      ((int= flags 1) (%z-piece! p (int- 9 side) (match ((int= side 0) (int- to 16)) (#t (int+ to 16)))))
      ((int= flags 2)
        (match
          ((int< from to) (do (%z-piece! p (int+ 4 side) (int+ from 3)) (%z-piece! p (int+ 4 side) (int+ from 1))))
          (#t (do (%z-piece! p (int+ 4 side) (int- from 4)) (%z-piece! p (int+ 4 side) (int- from 1))))))
      (#t ()))
    (match ((int= castle (obj-ref p %f-castle)) ())
           (#t (%z-flags! p (int+ castle 1) (int+ (obj-ref p %f-castle) 1))))
    (match ((int= ep (obj-ref p %f-ep)) ())
           (#t (%z-flags! p (int+ ep 18) (int+ (obj-ref p %f-ep) 18))))))

; Put PC on SQ, keeping the position's score: the middle-game and
; end-game sums of the piece-square tables, and the phase.  The hash is
; kept by %z-move!.
(def %set
  (fn (_ p sq pc)
    (def i (int+ sq 1))
    (def old (obj-ref p i))
    (def k (int* pc 128))
    (def o (int* old 128))
    (obj-set! p i pc)
    (obj-set! p %f-mg (int+ (obj-ref p %f-mg) (int- (obj-ref pst-middle (int+ k i)) (obj-ref pst-middle (int+ o i)))))
    (obj-set! p %f-eg (int+ (obj-ref p %f-eg) (int- (obj-ref pst-end (int+ k i)) (obj-ref pst-end (int+ o i)))))
    (obj-set! p %f-phase (int+ (obj-ref p %f-phase) (int- (obj-ref pst-phase (int+ pc 1)) (obj-ref pst-phase (int+ old 1)))))))

; The score of P's pieces counted afresh, after FEN has placed them.
(def %score!
  (fn (_ p)
    (List for-each
      (fn (_ sq)
        (def pc (obj-ref p (int+ sq 1)))
        (obj-set! p (int+ sq 1) 0)
        (%set p sq pc))
      (List filter (fn (_ sq) (int= (int& sq 136) 0)) (List range 0 128)))
    p))

; The step from one square toward another on the same line, by their
; difference: slot d + 120 holds it, 0 when they share no line.
(def %line
  (do (def v (Vector make 240 0))
      (List for-each
        (fn (_ d) (List for-each (fn (_ k) (obj-set! v (int+ (int* d k) 120) d)) (List range 1 8)))
        %king-steps)
      v))

(def %diagonal?
  (fn (_ d) (match ((int= d 15) #t) ((int= d 17) #t) ((int= d -15) #t) ((int= d -17) #t) (#t #f))))

; Whether ENEMY has a slider on the ray from KSQ by D that sees KSQ.
(def %ray-pins?
  (fn (_ p ksq d enemy)
    ((fn (_ pc)
       (match
         ((int= pc (int+ 5 enemy)) #t)
         ((%diagonal? d) (int= pc (int+ 3 enemy)))
         (#t (int= pc (int+ 4 enemy)))))
     (%ray-first p (int+ ksq d) d))))

; Make M on P.  Answers #t, or #f with P as it was when the move leaves
; the mover's king attacked.  CHECK says the mover is in check now; a
; move that is not the king's, nor en passant, nor out of check, can
; only uncover its king along the line from the king to its from square,
; so that one ray is all that is looked at.
(def make-checked!
  (fn (_ p m check)
    (def from (int& m 127))
    (def to (int& (int>> m 7) 127))
    (def promo (int& (int>> m 14) 15))
    (def flags (int>> m 18))
    (def side (obj-ref p %f-side))
    (def pc (obj-ref p (int+ from 1)))
    (def cap (obj-ref p (int+ to 1)))
    (def ep (obj-ref p %f-ep))
    (def castle (obj-ref p %f-castle))
    (def half (obj-ref p %f-half))
    (obj-set! p %f-undo
      (pair (int+ cap (int+ (int* castle 16) (int+ (int* (int+ ep 1) 256) (int* half 65536))))
            (obj-ref p %f-undo)))
    (def placed (match ((int= promo 0) pc) (#t (int+ promo side))))
    (%set p from 0)
    (%set p to placed)
    (match
      ((int= flags 1) (%set p (match ((int= side 0) (int- to 16)) (#t (int+ to 16))) 0))
      ((int= flags 2)
        (match
          ((int< from to) (do (%set p (int+ from 1) (obj-ref p (int+ from 4))) (%set p (int+ from 3) 0)))
          (#t (do (%set p (int- from 1) (obj-ref p (int- from 3))) (%set p (int- from 4) 0)))))
      (#t ()))
    (match ((int= (int& pc 7) 6) (obj-set! p (match ((int= side 0) %f-wking) (#t %f-bking)) to)) (#t ()))
    (obj-set! p %f-castle
      (int& castle (int& (obj-ref %castle-keep (int+ from 1)) (obj-ref %castle-keep (int+ to 1)))))
    (obj-set! p %f-ep (match ((int= flags 4) (int+ from (match ((int= side 0) 16) (#t -16)))) (#t -1)))
    (obj-set! p %f-half (match ((int= (int& pc 7) 1) 0) ((int< 0 cap) 0) (#t (int+ half 1))))
    (match ((int= side 8) (obj-set! p %f-full (int+ (obj-ref p %f-full) 1))) (#t ()))
    (obj-set! p %f-side (int- 8 side))
    (%z-move! p from to pc placed cap side flags castle ep)
    (def ksq (obj-ref p (match ((int= side 0) %f-wking) (#t %f-bking))))
    (def enemy (int- 8 side))
    (match
      ((match
         ((int= (int& pc 7) 6) (attacked? p ksq enemy))
         (check (attacked? p ksq enemy))
         ((int= flags 1) (attacked? p ksq enemy))
         (#t ((fn (_ d) (match ((int= d 0) #f) (#t (%ray-pins? p ksq d enemy))))
              (obj-ref %line (int+ (int- from ksq) 120)))))
        (do (unmake! p m) #f))
      (#t #t))))

; Make M on P: #t, or #f with P as it was when M is not legal.
(def make! (fn (_ p m) (make-checked! p m (in-check? p))))

; Take M back off P: M must be the last move made.
(def unmake!
  (fn (_ p m)
    (def from (int& m 127))
    (def to (int& (int>> m 7) 127))
    (def promo (int& (int>> m 14) 15))
    (def flags (int>> m 18))
    (def castle (obj-ref p %f-castle))
    (def ep (obj-ref p %f-ep))
    (def undo (first (obj-ref p %f-undo)))
    (obj-set! p %f-undo (rest (obj-ref p %f-undo)))
    (def side (int- 8 (obj-ref p %f-side)))
    (obj-set! p %f-side side)
    (def placed (obj-ref p (int+ to 1)))
    (def pc (match ((int= promo 0) placed) (#t (int+ 1 side))))
    (%set p from pc)
    (%set p to (int& undo 15))
    (match
      ((int= flags 1) (%set p (match ((int= side 0) (int- to 16)) (#t (int+ to 16))) (int- 9 side)))
      ((int= flags 2)
        (match
          ((int< from to) (do (%set p (int+ from 3) (obj-ref p (int+ from 2))) (%set p (int+ from 1) 0)))
          (#t (do (%set p (int- from 4) (obj-ref p from)) (%set p (int- from 1) 0)))))
      (#t ()))
    (match ((int= (int& pc 7) 6) (obj-set! p (match ((int= side 0) %f-wking) (#t %f-bking)) from)) (#t ()))
    (obj-set! p %f-castle (int& (int>> undo 4) 15))
    (obj-set! p %f-ep (int- (int& (int>> undo 8) 255) 1))
    (obj-set! p %f-half (int>> undo 16))
    (%z-move! p from to pc placed (int& undo 15) side flags castle ep)
    (match ((int= side 8) (obj-set! p %f-full (int- (obj-ref p %f-full) 1))) (#t ()))
    p))

; The legal moves of the side to move.
(def legal-moves
  (fn (_ p)
    (def check (in-check? p))
    (List filter (fn (_ m) (match ((make-checked! p m check) (do (unmake! p m) #t)) (#t #f))) (gen-moves p #f))))

(def %perft-count
  (fn (self p depth check ms n)
    (match
      ((null? ms) n)
      (#t (self p depth check (rest ms)
            (match
              ((make-checked! p (first ms) check)
                ((fn (_ k) (unmake! p (first ms)) (int+ n k))
                 (match ((int= depth 1) 1) (#t (perft p (int- depth 1))))))
              (#t n)))))))

; The number of move paths DEPTH plies deep: perft, the move
; generator's check against the published counts.  The heap is
; collected at each node three or more plies from the leaves: x collects
; only when asked.
(def perft
  (fn (_ p depth)
    (when (int< 2 depth) (Heap collect))
    (if (int= depth 0) 1 (%perft-count p depth (in-check? p) (gen-moves p #f) 0))))

; The move named in UCI's long algebraic among P's legal moves, or ().
(def move-parse-uci
  (fn (_ p text)
    (List find (fn (_ m) (str=? (move-uci m) text)) (legal-moves p))))

(provide chess/board
  PAWN KNIGHT BISHOP ROOK QUEEN KING WHITE BLACK FLAG-EP FLAG-CASTLE FLAG-DOUBLE
  pos-piece pos-side pos-castle pos-ep pos-half pos-full pos-king pos-copy pos-middle pos-end pos-phase pos-hash-lo pos-hash-hi
  piece-kind piece-colour piece-letter
  sq-file sq-rank sq-make sq-name sq-parse
  move-make move-from move-to move-promo move-flags move-uci move-parse-uci
  fen-start pos-from-fen pos-fen pos-key parse-int chess-roll
  attacked? in-check? gen-moves make! make-checked! unmake! legal-moves perft)
