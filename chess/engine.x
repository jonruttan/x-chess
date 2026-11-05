; # x-chess -- a chess engine on x-lang
;
; ## chess/engine.x -- another engine, spoken to over UCI
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A program that speaks UCI, started with its standard input and output
; on pipes: uci and uciok, isready and readyok, then a position and a go
; for each move, its info lines read as reports while it thinks.  A
; report is the search's: (depth score nodes microseconds move line),
; the score from the side to move's view, a mate as the search scores
; one.
;
; An engine is a Vector: 0 the process, 1 the descriptor written to,
; 2 the one read from, 3 the text read and not yet a whole line, 4 the
; whole lines not yet taken, 5 its name, 6 the command.

(module chess/engine)

(import x/sys/posix)
(import x/core/doors io-display-to-str int- int* int/)
(import chess/board pos-copy make! move-uci move-parse-uci fen-start parse-int)
(import chess/search MATE)
(import chess/game game-pos game-start game-moves)

(def %get (fn (_ e i) (Vector ref i e)))
(def %put! (fn (_ e i v) (Vector set! i v e)))

(def engine-name (fn (_ e) (%get e 5)))

; Wall-clock microseconds: another process's thinking takes none of ours.
(def %wall (fn (_) ((fn (_ t) (+ (* (first t) 1000000) (rest t))) (Sys time-of-day))))

(def engine-send!
  (fn (_ e text)
    (guard (x ()) (Sys fd-write (%get e 1) (Str8 append text "\n")))))

; Text read into the engine's buffer, split into whole lines and the rest.
(def %take-text!
  (fn (_ e text)
    (def parts (Str8 split "\n" (Str8 append (%get e 3) (Str8 replace "\r" "" text))))
    (%put! e 3 (List last parts))
    (%put! e 4 (List append (%get e 4) (List init parts)))))

; The next line from the engine: a string, () when none comes within MS
; milliseconds, or the symbol eof when the engine has gone.
(def engine-line
  (fn (self e ms)
    (match
      ((not (null? (%get e 4)))
        ((fn (_ l) (%put! e 4 (rest (%get e 4))) l) (first (%get e 4))))
      ((null? (Sys poll (list (pair (%get e 2) (list (lit in)))) ms)) ())
      (#t ((fn (_ bytes)
             (if (null? bytes) (lit eof)
               (do (%take-text! e (bytes->str bytes)) (self e 0))))
           (Sys fd-read (%get e 2) 4096))))))

; Lines until one that starts with WORD, within MS milliseconds: that
; line, or () when it never comes.  SEEN is handed each line before it.
(def %await
  (fn (_ e word ms seen)
    (def t-end (+ (%wall) (int* ms 1000)))
    (def go
      (fn (self)
        (def l (engine-line e 100))
        (match
          ((eq? l (lit eof)) ())
          ((< t-end (%wall)) ())
          ((null? l) (self))
          ((Str8 starts? word l) l)
          (#t (do (seen l) (self))))))
    (go)))

; Start the engine COMMAND, a list of the program and its arguments, and
; agree on UCI.  Raises a chess Err when it cannot be started or does
; not answer uciok.
(def engine-start
  (fn (_ command)
    ; an engine that has gone makes a write fail, not end this process:
    ; SIGPIPE (13 on Darwin and Linux) is ignored from the first engine on
    (Sys signal 13 (Sys sig-ign))
    (def to (Sys pipe))
    (def from (Sys pipe))
    (def pid (Sys fork))
    (when (= pid 0)
      (guard (x (Sys exit 127))
        (do (Sys dup2 (first to) 0)
            (Sys dup2 (rest from) 1)
            (Sys close (first to)) (Sys close (rest to))
            (Sys close (first from)) (Sys close (rest from))
            (Sys exec (first command) (rest command))))
      (Sys exit 127))
    (Sys close (first to))
    (Sys close (rest from))
    (def e (Vector make 7 ()))
    (%put! e 0 pid)
    (%put! e 1 (rest to))
    (%put! e 2 (first from))
    (%put! e 3 "")
    (%put! e 5 (first command))
    (%put! e 6 command)
    (engine-send! e "uci")
    (def ok
      (%await e "uciok" 10000
        (fn (_ l) (when (Str8 starts? "id name " l) (%put! e 5 (Str8 trim (Str8 slice 8 (Str8 length l) l)))))))
    (when (null? ok)
      (engine-quit! e)
      (Err raise (lit chess) (Str8 append "cannot start the engine " (Str8 join " " command) ": no uciok") command))
    (engine-ready! e)
    e))

(def engine-ready!
  (fn (_ e)
    (engine-send! e "isready")
    (%await e "readyok" 10000 (fn (_ l) ()))))

(def engine-option!
  (fn (_ e name value)
    (engine-send! e (Str8 append "setoption name " name " value " value))))

(def engine-new-game!
  (fn (_ e)
    (engine-send! e "ucinewgame")
    (engine-ready! e)))

; Ask the engine to stop, wait a little, and close its pipes.
(def engine-quit!
  (fn (_ e)
    (engine-send! e "quit")
    (guard (x ()) (Sys close (%get e 1)))
    (guard (x ()) (Sys close (%get e 2)))
    (guard (x ()) (Sys wait (%get e 0)))))

; --- thinking ------------------------------------------------------------------------

; A UCI score after "score": cp N, or mate N in moves, as the search scores.
(def %score
  (fn (_ kind n)
    (match
      ((str=? kind "cp") n)
      ((< 0 n) (- MATE (- (* 2 n) 1)))
      (#t (- 0 (- MATE (* 2 (- 0 n))))))))

; The moves TEXTS name, played from P on as far as they are legal.
(def %line
  (fn (_ p texts)
    (def q (pos-copy p))
    (def go
      (fn (self ts acc)
        (def m (if (null? ts) () (move-parse-uci q (first ts))))
        (if (null? m) (List reverse acc)
          (do (make! q m) (self (rest ts) (pair m acc))))))
    (go texts ())))

(def %num (fn (_ s) ((fn (_ n) (if (null? n) 0 n)) (parse-int s))))

; The report an info line WORDS makes in P, or () when it has no pv or score.
(def engine-info-report
  (fn (_ p words)
    (def walk
      (fn (self ws depth score nodes ms pv)
        (match
          ((null? ws)
            (if (if (null? pv) #t (null? score)) ()
              (list depth score nodes (int* ms 1000) (first pv) pv)))
          ((null? (rest ws)) (self () depth score nodes ms pv))
          ((str=? (first ws) "depth") (self (List drop 2 ws) (%num (List ref 1 ws)) score nodes ms pv))
          ((str=? (first ws) "nodes") (self (List drop 2 ws) depth score (%num (List ref 1 ws)) ms pv))
          ((str=? (first ws) "time") (self (List drop 2 ws) depth score nodes (%num (List ref 1 ws)) pv))
          ((str=? (first ws) "score")
            (if (null? (List drop 2 ws)) (self () depth score nodes ms pv)
              (self (List drop 3 ws) depth (%score (List ref 1 ws) (%num (List ref 2 ws))) nodes ms pv)))
          ((str=? (first ws) "pv") (self () depth score nodes ms (%line p (rest ws))))
          (#t (self (rest ws) depth score nodes ms pv)))))
    (walk words 0 () 0 0 ())))

(def %words (fn (_ line) (List reject (fn (_ w) (str=? w "")) (Str8 split " " line))))

; The position command for game G.
(def %position-text
  (fn (_ g)
    (def moves (game-moves g))
    (Str8 append "position "
      (if (str=? (game-start g) fen-start) "startpos" (Str8 append "fen " (game-start g)))
      (if (null? moves) "" (Str8 append " moves " (Str8 join " " (List map move-uci moves)))))))

; The go command for at most DEPTH plies and MS milliseconds (0 for no
; limit on either).
(def %go-text
  (fn (_ depth ms)
    (Str8 append "go"
      (if (< 0 depth) (Str8 append " depth " (io-display-to-str depth)) "")
      (if (< 0 ms) (Str8 append " movetime " (io-display-to-str ms)) "")
      (if (if (< depth 1) (< ms 1) #f) " infinite" ""))))

; Have engine E choose a move in game G, as search-best does: INFO is
; handed each report, POLL asked between lines whether to stop.  The last
; report with the move the engine chose, or () when it has none.
(def engine-think
  (fn (_ e g depth ms poll info)
    (def p (game-pos g))
    (def t0 (%wall))
    (engine-send! e (%position-text g))
    (engine-send! e (%go-text depth ms))
    (def go
      (fn (self last stopped)
        (def l (engine-line e 50))
        (match
          ((eq? l (lit eof)) (Err raise (lit chess) (Str8 append (engine-name e) " has stopped") ()))
          ((null? l)
            (if (if stopped #f (poll)) (do (engine-send! e "stop") (self last #t)) (self last stopped)))
          ((Str8 starts? "info " l)
            ((fn (_ r) (if (null? r) (self last stopped) (do (info r) (self r stopped))))
             (engine-info-report p (%words l))))
          ((Str8 starts? "bestmove" l) (%best p (%words l) last (- (%wall) t0)))
          (#t (self last stopped)))))
    (go () #f)))

; The final report for "bestmove MOVE ...": LAST's figures, the chosen move.
(def %best
  (fn (_ p words last us)
    (def m (if (null? (rest words)) () (move-parse-uci p (List ref 1 words))))
    (match
      ((null? m) ())
      ((null? last) (list 0 0 0 us m (list m)))
      ((= (List ref 4 last) m) (list (List ref 0 last) (List ref 1 last) (List ref 2 last) us m (List ref 5 last)))
      (#t (list (List ref 0 last) (List ref 1 last) (List ref 2 last) us m (list m))))))

(provide chess/engine engine-start engine-quit! engine-name engine-send! engine-line engine-ready!
  engine-option! engine-new-game! engine-think engine-info-report)
