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
(import chess/search MATE evaluate search-best best-move mate-score? mate-in)
(import chess/book polyglot-key polyglot-hex book-moves book-pick book-current book-use!)
(import chess/tables tables-dir tables-allow-build! tables-load! tables-build! tables-loaded? tables-longest tables-men table-probe)
(import chess/san move-san moves-san move-parse)
(import chess/game game-new game-pos game-start game-fen game-moves game-play! game-undo! game-repeats game-result game-movetext
  game-pgn)
(import chess/player player-builtin player-start player-name player-builtin? player-think
  player-new-game! player-quit!)
(import chess/match match-run)
(import chess/tui tui-make tui-game tui-quit? tui-engine tui-depth tui-ms tui-analysing? tui-message!
  tui-engine-to-move? tui-report! tui-thinking-clear! tui-engine-played! tui-hint! tui-key! tui-loop-key? tui-draw!)
(import chess/app app-run)
(import chess/show show-board)
(import chess/engine engine-start engine-quit! engine-name engine-send! engine-line engine-ready!
  engine-option! engine-new-game! engine-think engine-info-report)
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
  MATE evaluate search-best best-move mate-score? mate-in
  polyglot-key polyglot-hex book-moves book-pick book-current book-use!
  tables-dir tables-allow-build! tables-load! tables-build! tables-loaded? tables-longest tables-men table-probe
  move-san moves-san move-parse
  game-new game-pos game-start game-fen game-moves game-play! game-undo! game-repeats game-result game-movetext
  game-pgn player-builtin player-start player-name player-builtin? player-think player-new-game! player-quit!
  match-run tui-make tui-game tui-quit? tui-engine tui-depth tui-ms tui-analysing? tui-message!
  tui-engine-to-move? tui-report! tui-thinking-clear! tui-engine-played! tui-hint! tui-key! tui-loop-key? tui-draw!
  app-run
  show-board chess-version uci-run uci-think-ms play-run chess-main chess-options
  engine-start engine-quit! engine-name engine-send! engine-line engine-ready!
  engine-option! engine-new-game! engine-think engine-info-report)
