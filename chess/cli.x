; # x-chess -- a chess engine on x-lang
;
; ## chess/cli.x -- the command line, and the terminal
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;   x -l chess -- [--white|--black|--both] [--fen FEN] [--time S] [--depth N]
;   x -l chess -- --uci
;   x -l chess -- --perft N [--fen FEN]
;
; On a terminal it is a game against the engine.  Otherwise it reads
; lines: when the first is `uci` it speaks UCI, as a chess GUI expects
; of an engine it starts, and else it takes them as moves and commands,
; which is how the game is played from a script.

(module chess/cli)

(import x/sys/gc)
(import x/sys/file)
(import x/repl/term)
(import x/repl/line)
(import x/core/doors str-make str-byte-ref str-byte-len str-byte-sub io-display-to-str)
(import chess/board fen-start pos-from-fen perft parse-int)
(import chess/uci chess-version uci-run)
(import chess/play play-run)

(def %usage
  (Str8 join "\n"
    (list "usage: x -l chess -- [--white|--black|--both] [--fen FEN] [--time SECONDS] [--depth N]"
          "       x -l chess -- --uci"
          "       x -l chess -- --perft N [--fen FEN]"
          ""
          "A game against the engine on a terminal; help lists the commands there."
          "Fed lines, it speaks UCI when the first is `uci`, else plays them as moves."
          "")))

(def %say (fn (_ fd text) (Sys fd-write fd text)))

(def %flag
  (list (pair "--white" (pair (lit side) (lit white)))
        (pair "--black" (pair (lit side) (lit black)))
        (pair "--both" (pair (lit side) (lit both)))
        (pair "--uci" (pair (lit uci) #t))
        (pair "--help" (pair (lit help) #t))
        (pair "-h" (pair (lit help) #t))
        (pair "--version" (pair (lit version) #t))))

; The options in ARGS as an alist, or ((error . TEXT)).
(def chess-options
  (fn (self args opts)
    (def a (if (null? args) "" (first args)))
    (def value (if (null? args) () (if (null? (rest args)) () (first (rest args)))))
    (def number
      (fn (_ key min what)
        ((fn (_ n) (if (if (null? n) #t (< n min))
                     (list (pair (lit error) (Str8 append a " takes " what)))
                     (self (List drop 2 args) (pair (pair key n) opts))))
         (if (null? value) () (parse-int value)))))
    (match
      ((null? args) opts)
      ((not (null? (Assoc find a %flag))) (self (rest args) (pair (rest (Assoc find a %flag)) opts)))
      ((str=? a "--fen")
        (if (null? value) (list (pair (lit error) "--fen takes a position"))
          (self (List drop 2 args) (pair (pair (lit fen) value) opts))))
      ((str=? a "--time") (number (lit seconds) 1 "a number of seconds"))
      ((str=? a "--depth") (number (lit depth) 1 "a number of plies"))
      ((str=? a "--perft") (number (lit perft) 0 "a depth"))
      (#t (list (pair (lit error) (Str8 append "no such option: " a)))))))

(def %opt (fn (_ opts k) ((fn (_ p) (if (null? p) () (rest p))) (Assoc find k opts))))

; --- input ----------------------------------------------------------------------
;
; On a terminal a line is read with the line editor; otherwise fd 0 is
; read in blocks and cut at newlines.

(def %in "")
(def %in-eof #f)

(def %newline-at
  (fn (_ s)
    (def n (str-byte-len s))
    (def go (fn (self i) (if (= i n) -1 (if (= (str-byte-ref s i) 10) i (self (+ i 1))))))
    (go 0)))

(def %fill!
  (fn (_)
    (def buf (str-make 4096))
    (def n (File read 0 buf 4096))
    (if (if (number? n) (< 0 n) #f)
      (set! %in (Str8 append %in (str-byte-sub buf 0 n)))
      (set! %in-eof #t))))

(def %strip-cr
  (fn (_ s)
    (def n (str-byte-len s))
    (if (if (< 0 n) (= (str-byte-ref s (- n 1)) 13) #f) (str-byte-sub s 0 (- n 1)) s)))

(def %pipe-line
  (fn (self)
    (def nl (%newline-at %in))
    (match
      ((< -1 nl)
        ((fn (_ line) (set! %in (str-byte-sub %in (+ nl 1) (- (str-byte-len %in) (+ nl 1)))) (%strip-cr line))
         (str-byte-sub %in 0 nl)))
      (%in-eof (if (= (str-byte-len %in) 0) () ((fn (_ line) (set! %in "") (%strip-cr line)) %in)))
      (#t (do (%fill!) (self))))))

(def %tty-line
  (fn (_ . prompt)
    (def r (Line read (if (null? prompt) "" (first prompt))))
    (match ((str? r) r)
           ((eq? r (lit eof)) ())
           (#t ""))))

(def %ready?
  (fn (_)
    (if (< -1 (%newline-at %in)) #t
      (not (null? (Sys poll (list (pair 0 (list (lit in)))) 0))))))

; The IO the sessions take: (read say ready?).
(def %io
  (fn (_ tty)
    (list (if tty %tty-line (fn (_ . prompt) (%pipe-line)))
          (fn (_ text) (%say 1 text))
          %ready?)))

; --- main -----------------------------------------------------------------------

(def %perft-main
  (fn (_ opts)
    (def fen (if (null? (%opt opts (lit fen))) fen-start (%opt opts (lit fen))))
    (guard (e (do (%say 2 (Str8 append "x-chess: " (e msg) "\n")) 1))
      (do (%say 1 (Str8 append (io-display-to-str (perft (pos-from-fen fen) (%opt opts (lit perft)))) "\n")) 0))))

; The options a game takes from OPTS: a bad --fen refused before play.
(def %game-opts
  (fn (_ opts)
    (def secs (%opt opts (lit seconds)))
    (List append
      (if (null? (%opt opts (lit fen))) () (list (pair (lit fen) (%opt opts (lit fen)))))
      (if (null? (%opt opts (lit side))) () (list (pair (lit side) (%opt opts (lit side)))))
      (if (null? secs) () (list (pair (lit ms) (* secs 1000))))
      (if (null? (%opt opts (lit depth))) () (list (pair (lit depth) (%opt opts (lit depth))))))))

(def %session
  (fn (_ opts)
    ; the launcher parks the caller's stdin on fd 3 while its boot
    ; stream holds fd 0; it is taken back, as x-grep and the REPL do
    (guard (e ()) (do (Sys dup2 3 0) (Sys close 3)))
    (def tty (if (Term tty? 0) (Sys isatty 1) #f))
    (def io (%io tty))
    (match
      ((not (null? (%opt opts (lit uci)))) (uci-run io ()))
      (tty (play-run io (%game-opts opts) ()))
      (#t ((fn (_ line)
             (match ((null? line) 0)
                    ((str=? (Str8 trim line) "uci") (uci-run io line))
                    (#t (play-run io (%game-opts opts) line))))
           (%pipe-line))))))

; Run the command line ARGS; answers the exit status.
(def chess-main
  (fn (_ args)
    (def opts (chess-options args ()))
    (def fen (%opt opts (lit fen)))
    (def bad-fen (if (null? fen) () (guard (e (e msg)) (do (pos-from-fen fen) ()))))
    (match
      ((not (null? (%opt opts (lit error))))
        (do (%say 2 (Str8 append "x-chess: " (%opt opts (lit error)) "\n" %usage)) 2))
      ((not (null? (%opt opts (lit help)))) (do (%say 1 %usage) 0))
      ((not (null? (%opt opts (lit version)))) (do (%say 1 (Str8 append "x-chess " chess-version "\n")) 0))
      ((not (null? bad-fen)) (do (%say 2 (Str8 append "x-chess: " bad-fen "\n")) 2))
      ((not (null? (%opt opts (lit perft)))) (%perft-main opts))
      (#t (%session opts)))))

(provide chess/cli chess-main chess-options)
