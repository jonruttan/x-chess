; # x-chess -- a chess engine on x-lang
;
; ## chess/player.x -- who chooses a move: this engine or another
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A player is x-chess's own search or a program that speaks UCI
; (chess/engine), asked the same way: a game, a depth and a time, a poll
; and a report for each depth it finishes.  A player is a Vector: 0 the
; engine, () for x-chess's own, 1 its name.

(module chess/player)

(import chess/search search-best)
(import chess/game game-pos)
(import chess/engine engine-start engine-quit! engine-name engine-think engine-new-game!)

(def player-name (fn (_ pl) (Vector ref 1 pl)))

(def player-builtin?
  (fn (_ pl) (null? (Vector ref 0 pl))))

(def %player
  (fn (_ e name)
    (def pl (Vector make 2 ()))
    (Vector set! 0 e pl)
    (Vector set! 1 name pl)
    pl))

(def player-builtin (fn (_) (%player () "x-chess")))

; The player COMMAND names: x-chess's own for "x-chess" or nothing, else
; the program and its arguments, split at spaces, started now.
(def player-start
  (fn (_ command)
    (def words (List reject (fn (_ w) (str=? w "")) (Str8 split " " (if (null? command) "" command))))
    (match
      ((null? words) (player-builtin))
      ((if (null? (rest words)) (str=? (first words) "x-chess") #f) (player-builtin))
      (#t ((fn (_ e) (%player e (engine-name e))) (engine-start words))))))

; The move PL chooses in game G, at most DEPTH plies and MS milliseconds
; (0 for no limit), POLL answering true to stop and INFO handed each
; report: the last report, or () when there is no move.
(def player-think
  (fn (_ pl g depth ms poll info)
    (if (player-builtin? pl)
      (search-best (game-pos g) (if (< depth 1) 64 depth) ms 0 poll info)
      (engine-think (Vector ref 0 pl) g depth ms poll info))))

(def player-new-game!
  (fn (_ pl) (unless (player-builtin? pl) (engine-new-game! (Vector ref 0 pl)))))

(def player-quit!
  (fn (_ pl) (unless (player-builtin? pl) (engine-quit! (Vector ref 0 pl)))))

(provide chess/player player-builtin player-start player-name player-builtin? player-think
  player-new-game! player-quit!)
