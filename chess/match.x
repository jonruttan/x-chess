; # x-chess -- a chess engine on x-lang
;
; ## chess/match.x -- two players, a number of games
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The players take white in turn, the first in the first game.  Each
; game is written as PGN when it ends, and a line for it is reported;
; the score follows the last.  A game still going after 600 plies is
; drawn, and a player with no move to give loses it.

(module chess/match)

(import x/sys/gc)
(import x/core/doors io-display-to-str int/ int%)
(import chess/board pos-side)
(import chess/game game-new game-pos game-play! game-result game-pgn game-moves)
(import chess/player player-name player-think player-new-game!)

(def %limit 600)

; Game G played out between WHITE and BLACK: its result, a pair of the
; PGN result and why.
(def %play-out
  (fn (self g white black depth ms)
    (def over (game-result g))
    (def mover (if (= (pos-side (game-pos g)) 0) white black))
    (Heap collect)
    (match
      ((not (null? over)) over)
      ((< (- %limit 1) (List length (game-moves g))) (pair "1/2-1/2" "the move limit"))
      (#t ((fn (_ r)
             (if (null? r)
               (pair (if (eq? mover white) "0-1" "1-0") (Str8 append (player-name mover) " gave no move"))
               (do (game-play! g (List ref 4 r)) (self g white black depth ms))))
           (player-think mover g depth ms (fn (_) #f) (fn (_ r) ())))))))

; Half-points: 2 for a win, 1 for a draw.
(def %half-points
  (fn (_ result white?)
    (match ((str=? result "1/2-1/2") 1)
           ((str=? result "1-0") (if white? 2 0))
           (#t (if white? 0 2)))))

(def %points-text
  (fn (_ halves)
    (Str8 append (io-display-to-str (int/ halves 2)) (if (= (int% halves 2) 1) ".5" ""))))

; Play GAMES games between players A and B.  OPTS is an alist: fen,
; depth, ms, event, date.  SAY takes the PGN, REPORT the lines about the
; games.  Answers the half-points of A and B, a pair.
(def match-run
  (fn (_ a b games opts say report)
    (def opt (fn (_ k d) ((fn (_ p) (if (null? p) d (rest p))) (Assoc find k opts))))
    (def go
      (fn (self i ha hb)
        (if (< games (+ i 1))
          (do (report (Str8 append "Score: " (player-name a) " " (%points-text ha) ", "
                        (player-name b) " " (%points-text hb) "\n"))
              (pair ha hb))
          (do
            (def a-white (= (int% i 2) 0))
            (def white (if a-white a b))
            (def black (if a-white b a))
            (player-new-game! white)
            (player-new-game! black)
            (def g (game-new (opt (lit fen) ())))
            (def result (%play-out g white black (opt (lit depth) 0) (opt (lit ms) 1000)))
            (say (game-pgn g
                   (list (pair "Event" (opt (lit event) "x-chess match"))
                         (pair "Site" "?")
                         (pair "Date" (opt (lit date) "????.??.??"))
                         (pair "Round" (io-display-to-str (+ i 1)))
                         (pair "White" (player-name white))
                         (pair "Black" (player-name black)))
                   (first result)))
            (say "\n")
            (report (Str8 append "Game " (io-display-to-str (+ i 1)) " of " (io-display-to-str games) ": "
                      (player-name white) " - " (player-name black) "  " (first result) " (" (rest result) ")\n"))
            (self (+ i 1)
              (+ ha (%half-points (first result) a-white))
              (+ hb (%half-points (first result) (not a-white))))))))
    (go 0 0 0)))

(provide chess/match match-run)
