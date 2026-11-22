; # x-chess -- a chess engine on x-lang
;
; ## chess/san.x -- standard algebraic notation
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A move's SAN is written from the position before it: the piece's
; letter, as much of the from square as tells it apart from another
; piece of its kind that could go to the same square, x for a capture,
; the square, =Q for a promotion, and + or # for check or mate.  A pawn
; names its file only when it captures; castling is O-O or O-O-O.
;
; Reading is the other way round: the text is compared with every legal
; move's SAN, the check marks and annotations left off both, so what
; reads is exactly what is written.  Long algebraic, e2e4 or e7e8q, is
; read too, and 0-0 for O-O.

(module chess/san)

(import x/core/doors int& str-byte-ref str-byte-len str-byte-sub)
(import chess/board pos-piece in-check? legal-moves make! unmake! sq-name sq-file sq-rank
  move-from move-to move-promo move-flags move-uci)

(def %letters ".PNBRQK")

; The from square's part of the SAN: what tells M apart from the other
; legal moves of the same kind of piece to the same square.
(def %disambiguation
  (fn (_ p m moves)
    (def from (move-from m))
    (def kind (int& (pos-piece p from) 7))
    (def rivals
      (List filter
        (fn (_ o) (if (= (move-to o) (move-to m))
                    (if (= (move-from o) from) #f (= (int& (pos-piece p (move-from o)) 7) kind))
                    #f))
        moves))
    (def name (sq-name from))
    (match
      ((null? rivals) "")
      ((not (List any? (fn (_ o) (= (sq-file (move-from o)) (sq-file from))) rivals)) (str-byte-sub name 0 1))
      ((not (List any? (fn (_ o) (= (sq-rank (move-from o)) (sq-rank from))) rivals)) (str-byte-sub name 1 1))
      (#t name))))


; M's SAN without its check mark, among MOVES, P's legal moves.
(def %san-bare
  (fn (_ p m moves)
    (def from (move-from m))
    (def to (move-to m))
    (def kind (int& (pos-piece p from) 7))
    (def capture (if (< 0 (pos-piece p to)) #t (= (move-flags m) 1)))
    (def promo (move-promo m))
    (match
      ((= (move-flags m) 2) (if (< from to) "O-O" "O-O-O"))
      ((= kind 1)
        (Str8 append (if capture (Str8 append (str-byte-sub (sq-name from) 0 1) "x") "")
          (sq-name to) (if (= promo 0) "" (Str8 append "=" (str-byte-sub %letters promo 1)))))
      (#t (Str8 append (str-byte-sub %letters kind 1) (%disambiguation p m moves)
            (if capture "x" "") (sq-name to))))))

; The check mark M earns: "#" for mate, "+" for check, else "".
(def %san-mark
  (fn (_ p m)
    (make! p m)
    (def mark (if (in-check? p) (if (null? (legal-moves p)) "#" "+") ""))
    (unmake! p m)
    mark))

; M's SAN in P.
(def move-san
  (fn (_ p m)
    (Str8 append (%san-bare p m (legal-moves p)) (%san-mark p m))))

; MOVES, made one after another from P, as SAN; P is as it was after.
(def moves-san
  (fn (_ p moves)
    (def go
      (fn (self ms acc)
        (if (null? ms) (List reverse acc)
          (do (def s (move-san p (first ms)))
              (make! p (first ms))
              (def r (self (rest ms) (pair s acc)))
              (unmake! p (first ms))
              r))))
    (go moves ())))

; TEXT with the trailing check marks and annotations left off, and 0
; read as O.
(def %san-clean
  (fn (_ text)
    (def cut
      (fn (self n)
        (if (= n 0) 0
          (if (List any? (fn (_ c) (= c (str-byte-ref text (- n 1)))) (list 43 35 33 63)) (self (- n 1)) n))))
    (Str8 replace "0" "O" (str-byte-sub text 0 (cut (str-byte-len text))))))

; The legal move TEXT names in P, SAN or long algebraic, or ().
(def move-parse
  (fn (_ p text)
    (def moves (legal-moves p))
    (def clean (%san-clean (Str8 trim text)))
    (def by-san (List find (fn (_ m) (str=? (%san-bare p m moves) clean)) moves))
    (if (null? by-san)
      (List find (fn (_ m) (str=? (move-uci m) (Str8 downcase clean))) moves)
      by-san)))

(provide chess/san move-san moves-san move-parse)
