; # x-chess -- a chess engine on x-lang
;
; @description `x -l chess -- [OPTIONS]`.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
(module chess/run)
(import chess/base)

(set! %lang-name "chess")
(set! %repl-prompt "chess> ")

; The operands: what follows the "--" after the launcher's own options.
; x-os's launcher passes the engine's own flags ahead of them, with no
; "--" between; they are left out, so `x -l chess` there is a REPL too.
(def %engine-flag?
  (fn (_ a) (List any? (fn (_ f) (str=? a f)) (list "--batch" "--quiet" "--no-color"))))
(def %operands
  (fn (self l) (if (if (null? l) #f (%engine-flag? (first l))) (self (rest l)) l)))

; With no operands the session goes on to the REPL.
(def main
  (fn (_)
    (let ((ops (%operands (rest (Sys args (lit program))))))
      (unless (null? ops) (Sys exit (chess-main ops))))))

(provide chess/run main)
