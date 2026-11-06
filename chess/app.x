; # x-chess -- a chess engine on x-lang
;
; ## chess/app.x -- the board interface on the terminal
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Takes the terminal as x-browse does: raw, on the alternate screen, the
; cursor hidden, and here the mouse reported as well; all given back as
; they were on the way out.  The size is asked again whenever no key
; comes for a quarter of a second.
;
; While the engine thinks the keys are still read, between its nodes:
; m has it move at once, q stops it and leaves, and any other key waits
; until it has moved.  Each depth it finishes is drawn as it comes.
; Analysing, the engine thinks until a key is pressed.

(module chess/app)

(import x/sys/posix)
(import x/sys/gc)
(import x/repl/term)
(import x/tui/screen)
(import x/core/doors io-display-to-str)
(import chess/game game-pos)
(import chess/player player-think player-quit!)
(import chess/tui tui-make tui-game tui-quit? tui-engine tui-depth tui-ms tui-analysing? tui-message!
  tui-engine-to-move? tui-report! tui-thinking-clear! tui-engine-played! tui-hint! tui-key! tui-loop-key? tui-draw!
  tui-work!)

(def %esc (fn (_ text) (Str8 append "\x1b" text)))

; --- keys --------------------------------------------------------------------------

; A byte reader over standard input, 64 bytes read at a time, with bytes
; that can be put back: (reader) a byte or () at the end, (reader #t)
; whether there are bytes read and not taken, (reader (lit back) BYTES)
; puts BYTES back in front.
(def %reader
  (fn (_)
    (def box (Vector of ()))
    (fn (self . ask)
      (match
        ((null? ask)
          (do (when (null? (Vector ref 0 box)) (Vector set! 0 (Sys fd-read 0 64) box))
              (if (null? (Vector ref 0 box)) ()
                ((fn (_ b) (Vector set! 0 (rest (Vector ref 0 box)) box) b) (first (Vector ref 0 box))))))
        ((eq? (first ask) (lit back)) (Vector set! 0 (List append (first (rest ask)) (Vector ref 0 box)) box))
        (#t (not (null? (Vector ref 0 box))))))))

; Whether a byte will come within MS milliseconds.
(def %waiting? (fn (_ reader ms) (if (reader #t) #t (not (null? (Sys poll (list (pair 0 (list (lit in)))) ms))))))

; The next key: Term's, but a lone escape is the escape key once 30 ms
; pass with nothing after it, and a mouse report, ESC [ < B ; X ; Y M
; (or m on release), is (mouse B X Y PRESS?).
(def %key
  (fn (_ reader)
    (def b (reader))
    (match
      ((null? b) ())
      ((not (= b 27)) (do (reader (lit back) (list b)) (Term key reader)))
      ((not (%waiting? reader 30)) (lit escape))
      (#t ((fn (_ c)
             (match
               ((null? c) (lit escape))
               ((not (= c 91)) (do (reader (lit back) (list 27 c)) (Term key reader)))
               (#t ((fn (_ d)
                      (if (if (null? d) #f (= d 60)) (%mouse reader 0 ())
                        (do (reader (lit back) (if (null? d) (list 27 91) (list 27 91 d))) (Term key reader))))
                    (reader)))))
           (reader))))))

; The rest of an SGR mouse report: numbers apart at ;, ended by M or m.
(def %mouse
  (fn (self reader n acc)
    (def b (reader))
    (match
      ((null? b) (lit escape))
      ((if (< 47 b) (< b 58) #f) (self reader (+ (* n 10) (- b 48)) acc))
      ((= b 59) (self reader 0 (pair n acc)))
      (#t ((fn (_ ns) (list (lit mouse) (List ref 0 ns) (List ref 1 ns) (List ref 2 ns) (= b 77)))
           (List reverse (pair n acc)))))))

; --- the loop ----------------------------------------------------------------------

(def %show!
  (fn (_ st screen)
    (tui-draw! st screen)
    (Term emit 1 (Screen render screen))))

; Keys pressed while the engine thought, for after.
(def %later ())

(def %keep! (fn (_ key) (set! %later (List append %later (list key)))))

; The poll a search makes while it plays: m stops it, q and ctrl-c stop
; it and leave, a key otherwise waits.
(def %playing-poll
  (fn (_ st reader)
    (fn (_)
      (if (not (%waiting? reader 0)) #f
        ((fn (_ key)
           (match
             ((null? key) #t)
             ((if (str? key) (str=? key "m") #f) #t)
             ((if (str? key) (str=? key "q") (eq? key (lit interrupt))) (do (tui-key! st "q") #t))
             (#t (do (%keep! key) #f))))
         (%key reader))))))

; The poll while analysing: any key ends it, to be acted on.
(def %analysing-poll (fn (_ reader) (fn (_) (%waiting? reader 0))))

; The engine thinks in the game, POLL asked between nodes, each report
; drawn; MS of 0 thinks until stopped.  Its last report, or ().
(def %think
  (fn (_ st screen poll ms)
    (def g (tui-game st))
    (def p (game-pos g))
    (tui-thinking-clear! st)
    (%show! st screen)
    (def r (player-think (tui-engine st) g (if (= ms 0) 64 (tui-depth st)) ms poll
             (fn (_ r) (tui-report! st p r) (%show! st screen))))
    (Heap collect)
    r))

(def %engine-move!
  (fn (_ st screen reader)
    (def r (%think st screen (%playing-poll st reader) (tui-ms st)))
    (match
      ((tui-quit? st) ())
      ((null? r) (tui-message! st "The engine has no move."))
      (#t (tui-engine-played! st (List ref 4 r) r)))))

(def %hint!
  (fn (_ st screen reader)
    (def r (%think st screen (%playing-poll st reader) (%min 3000 (tui-ms st))))
    (unless (null? r) (tui-hint! st (List ref 4 r)))))

(def %min (fn (_ a b) (if (< a b) a b)))

; The next key, the screen kept the terminal's size while it waits.
(def %wait-key
  (fn (self st screen reader)
    (if (%waiting? reader 250) (%key reader)
      (do ((fn (_ size)
             (unless (if (= (first size) (Screen cols screen)) (= (rest size) (Screen rows screen)) #f)
               (do (Screen resize screen (rest size) (first size))
                   (%show! st screen))))
           (Term window 0))
          (self st screen reader)))))

(def %act!
  (fn (_ st screen reader key)
    (match
      ((null? key) (tui-key! st "q"))
      ((not (tui-loop-key? st key)) (tui-key! st key))
      ((str=? key "i") (%hint! st screen reader))
      ((str=? key "m") (%engine-move! st screen reader))
      (#t (tui-key! st key)))))

(def %loop
  (fn (self st screen reader)
    (%show! st screen)
    (Heap collect)
    (match
      ((tui-quit? st) ())
      ((not (null? %later))
        ((fn (_ key) (set! %later (rest %later)) (%act! st screen reader key) (self st screen reader)) (first %later)))
      ((tui-work! st) (self st screen reader))
      ((tui-engine-to-move? st) (do (%engine-move! st screen reader) (self st screen reader)))
      ((tui-analysing? st)
        (do (%think st screen (%analysing-poll reader) 0)
            (%act! st screen reader (%wait-key st screen reader))
            (self st screen reader)))
      (#t (do (%act! st screen reader (%wait-key st screen reader)) (self st screen reader))))))

; Play on the terminal with OPTS as play-run takes them: the exit status.
(def app-run
  (fn (_ opts)
    (def size (Term window 0))
    (def st (tui-make opts))
    (def screen (Screen make (rest size) (first size)))
    (def token (Term raw! 0))
    (set! %later ())
    (Term emit 1 (Str8 append (%esc "[?1049h") (%esc "[?25l") (%esc "[?1000h") (%esc "[?1006h")))
    (def failed (guard (e e) (do (%loop st screen (%reader)) ())))
    (Term emit 1 (Str8 append (%esc "[?1006l") (%esc "[?1000l") (%esc "[0m") (%esc "[?25h") (%esc "[?1049l")))
    (Term restore! 0 token)
    (player-quit! (tui-engine st))
    (if (null? failed) 0
      (do (Sys fd-write 2 (Str8 append "x-chess: " (if (Err err? failed) (failed msg) (io-display-to-str failed)) "\n")) 1))))

(provide chess/app app-run)
