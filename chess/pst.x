; # x-chess -- a chess engine on x-lang
;
; ## chess/pst.x -- what a piece is worth on each square
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Tomasz Michniewski's Simplified Evaluation Function: a value for each
; kind of piece, and a table of what each square adds to it, written as
; white sees the board, the eighth rank first.  The king has two tables,
; one for the middle game and one for the end, and the evaluation blends
; them by how much material is left (the phase, 24 with every piece on).
;
; Each table here is turned into slots of one Vector, at piece * 128 +
; square + 1 for a 0x88 square, with black's values negated, so a
; position's score is a sum the board keeps as pieces move.

(module chess/pst)

(import x/core/doors int+ int- int* int& int>> obj-set!)

(def %worth (list 0 100 320 330 500 900 0))

(def %phase-weight (list 0 0 1 1 2 4 0))

(def %pawn
  (list   0   0   0   0   0   0   0   0
         50  50  50  50  50  50  50  50
         10  10  20  30  30  20  10  10
          5   5  10  25  25  10   5   5
          0   0   0  20  20   0   0   0
          5  -5 -10   0   0 -10  -5   5
          5  10  10 -20 -20  10  10   5
          0   0   0   0   0   0   0   0))

(def %knight
  (list -50 -40 -30 -30 -30 -30 -40 -50
        -40 -20   0   0   0   0 -20 -40
        -30   0  10  15  15  10   0 -30
        -30   5  15  20  20  15   5 -30
        -30   0  15  20  20  15   0 -30
        -30   5  10  15  15  10   5 -30
        -40 -20   0   5   5   0 -20 -40
        -50 -40 -30 -30 -30 -30 -40 -50))

(def %bishop
  (list -20 -10 -10 -10 -10 -10 -10 -20
        -10   0   0   0   0   0   0 -10
        -10   0   5  10  10   5   0 -10
        -10   5   5  10  10   5   5 -10
        -10   0  10  10  10  10   0 -10
        -10  10  10  10  10  10  10 -10
        -10   5   0   0   0   0   5 -10
        -20 -10 -10 -10 -10 -10 -10 -20))

(def %rook
  (list   0   0   0   0   0   0   0   0
          5  10  10  10  10  10  10   5
         -5   0   0   0   0   0   0  -5
         -5   0   0   0   0   0   0  -5
         -5   0   0   0   0   0   0  -5
         -5   0   0   0   0   0   0  -5
         -5   0   0   0   0   0   0  -5
          0   0   0   5   5   0   0   0))

(def %queen
  (list -20 -10 -10  -5  -5 -10 -10 -20
        -10   0   0   0   0   0   0 -10
        -10   0   5   5   5   5   0 -10
         -5   0   5   5   5   5   0  -5
          0   0   5   5   5   5   0  -5
        -10   5   5   5   5   5   0 -10
        -10   0   5   0   0   0   0 -10
        -20 -10 -10  -5  -5 -10 -10 -20))

(def %king-middle
  (list -30 -40 -40 -50 -50 -40 -40 -30
        -30 -40 -40 -50 -50 -40 -40 -30
        -30 -40 -40 -50 -50 -40 -40 -30
        -30 -40 -40 -50 -50 -40 -40 -30
        -20 -30 -30 -40 -40 -30 -30 -20
        -10 -20 -20 -20 -20 -20 -20 -10
         20  20   0   0   0   0  20  20
         20  30  10   0   0  10  30  20))

(def %king-end
  (list -50 -40 -30 -20 -20 -30 -40 -50
        -30 -20 -10   0   0 -10 -20 -30
        -30 -10  20  30  30  20 -10 -30
        -30 -10  30  40  40  30 -10 -30
        -30 -10  30  40  40  30 -10 -30
        -30 -10  20  30  30  20 -10 -30
        -30 -30   0   0   0   0 -30 -30
        -50 -30 -30 -30 -30 -30 -30 -50))

; The Vector for one phase: KING is that phase's king table.
(def %build
  (fn (_ king)
    (def v (Vector make 1920 0))
    (def tables (list () %pawn %knight %bishop %rook %queen king))
    (List for-each
      (fn (_ kind)
        (def worth (List ref kind %worth))
        (def table (List ref kind tables))
        (List for-each
          (fn (_ i)
            (def file (int& i 7))
            (def row (int>> i 3))
            (def value (int+ worth (List ref i table)))
            ; white's square: the table's row 0 is the eighth rank
            (obj-set! v (int+ (int+ (int* kind 128) (int+ (int* (int- 7 row) 16) file)) 1) value)
            ; black's: the same table read from the other side, negated
            (obj-set! v (int+ (int+ (int* (int+ kind 8) 128) (int+ (int* row 16) file)) 1) (int- 0 value)))
          (List range 0 64)))
      (List range 1 7))
    v))

(def pst-middle (%build %king-middle))
(def pst-end (%build %king-end))

; What each piece code counts toward the phase.
(def pst-phase
  (do (def v (Vector make 15 0))
      (List for-each
        (fn (_ kind)
          (obj-set! v (int+ kind 1) (List ref kind %phase-weight))
          (obj-set! v (int+ kind 9) (List ref kind %phase-weight)))
        (List range 1 7))
      v))

(def pst-worth (fn (_ kind) (List ref kind %worth)))

(provide chess/pst pst-middle pst-end pst-phase pst-worth)
