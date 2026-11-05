; # x-chess -- a chess engine on x-lang
;
; ## chess/base.x -- what the entry and the specs reach
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(import chess/board PAWN KNIGHT BISHOP ROOK QUEEN KING WHITE BLACK FLAG-EP FLAG-CASTLE FLAG-DOUBLE
  pos-piece pos-side pos-castle pos-ep pos-half pos-full pos-king pos-copy pos-middle pos-end pos-phase
  piece-kind piece-colour piece-letter
  sq-file sq-rank sq-make sq-name sq-parse
  move-make move-from move-to move-promo move-flags move-uci move-parse-uci
  fen-start pos-from-fen pos-fen pos-key parse-int
  attacked? in-check? gen-moves make! make-checked! unmake! legal-moves perft)
(import chess/search MATE evaluate search-best mate-score? mate-in)
(import chess/san move-san moves-san move-parse)
(import chess/game game-new game-pos game-start game-fen game-moves game-play! game-undo! game-repeats game-result game-movetext)
(import chess/show show-board)
(import chess/uci chess-version uci-run uci-think-ms)
(import chess/play play-run)
(import chess/cli chess-main chess-options)

(provide chess/base
  PAWN KNIGHT BISHOP ROOK QUEEN KING WHITE BLACK FLAG-EP FLAG-CASTLE FLAG-DOUBLE
  pos-piece pos-side pos-castle pos-ep pos-half pos-full pos-king pos-copy pos-middle pos-end pos-phase
  piece-kind piece-colour piece-letter
  sq-file sq-rank sq-make sq-name sq-parse
  move-make move-from move-to move-promo move-flags move-uci move-parse-uci
  fen-start pos-from-fen pos-fen pos-key parse-int
  attacked? in-check? gen-moves make! make-checked! unmake! legal-moves perft
  MATE evaluate search-best mate-score? mate-in
  move-san moves-san move-parse
  game-new game-pos game-start game-fen game-moves game-play! game-undo! game-repeats game-result game-movetext
  show-board chess-version uci-run uci-think-ms play-run chess-main chess-options)
