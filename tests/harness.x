; # x-chess -- a chess engine on x-lang
;
; ## tests/harness.x -- what the spec harness adds to the dialect
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The lang kit's generator writes tests/lib/harness.gen.x: the dialect
; lang.xon declares, the bundle's root on the import path, then this file.
(import chess/base)
(import x/sys/gc)

; What RUN, uci-run or play-run with its other arguments given, writes
; when it reads LINES: the IO it is handed reads them in turn, then the
; end of input, and nothing is ever waiting while it thinks.  The heap
; is collected first: x collects only when asked, and a spec file's
; cases run in one process.
(def spec-session
  (fn (_ run lines)
    (Heap collect)
    (def in lines)
    (def out ())
    (def io (list (fn (_ . prompt) (if (null? in) () ((fn (_ l) (set! in (rest in)) l) (first in))))
                  (fn (_ text) (set! out (pair text out)))
                  (fn (_) #f)))
    (run io)
    (Str8 join "" (List reverse out))))

; Each line of TEXT written as a line of its own, so a spec's expected
; output can be the whole of it.
(def spec-lines
  (fn (_ text) (List for-each (fn (_ l) (display l) (display "\n")) (Str8 split "\n" text))))

; TEXT with what changes from run to run taken out: an info line's time
; and nps, and the statistics after a move an engine plays or suggests
; and after a line of its thinking.
(def spec-untimed
  (fn (_ text)
    (def drop-timing
      (fn (self ws)
        (match ((null? ws) ())
               ((if (str=? (first ws) "time") #t (str=? (first ws) "nps")) (self (rest (rest ws))))
               (#t (pair (first ws) (self (rest ws)))))))
    (def cut-stats
      (fn (_ l)
        (def at (Str8 split "  (" l))
        (if (null? (rest at)) l (first at))))
    (Str8 join "\n"
      (List map
        (fn (_ l)
          (match ((Str8 starts? "info depth" l) (Str8 join " " (drop-timing (Str8 split " " l))))
                 ((Str8 includes? " plays " l) (cut-stats l))
                 ((Str8 includes? " suggests " l) (cut-stats l))
                 ((Str8 starts? "  " l) (cut-stats l))
                 (#t l)))
        (Str8 split "\n" text)))))
