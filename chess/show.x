; # x-chess -- a chess engine on x-lang
;
; ## chess/show.x -- the board as text
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; FEN's letters on a grid, white's in upper case, a dot for an empty
; square, seen from white's side or from black's.

(module chess/show)

(import chess/board pos-piece piece-letter sq-make)
(import x/core/doors str-byte-sub)

; P's board as lines of text, from the side of SIDE (0 white, 8 black).
(def show-board
  (fn (_ p side)
    (def ranks (if (= side 0) (list 7 6 5 4 3 2 1 0) (list 0 1 2 3 4 5 6 7)))
    (def files (if (= side 0) (list 0 1 2 3 4 5 6 7) (list 7 6 5 4 3 2 1 0)))
    (def row
      (fn (_ rank)
        (Str8 append (str-byte-sub "12345678" rank 1) " | "
          (Str8 join " " (List map (fn (_ f) (piece-letter (pos-piece p (sq-make f rank)))) files))
          " |")))
    (Str8 join "\n"
      (List append
        (list "  +-----------------+")
        (List map row ranks)
        (list "  +-----------------+"
              (Str8 append "    " (Str8 join " " (List map (fn (_ f) (str-byte-sub "abcdefgh" f 1)) files))))))))


(provide chess/show show-board)
