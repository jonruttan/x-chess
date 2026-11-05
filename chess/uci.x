; # x-chess -- a chess engine on x-lang
;
; ## chess/uci.x -- the Universal Chess Interface
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; What a chess GUI or another engine speaks to an engine, a line at a
; time: uci, isready, ucinewgame, position, go, stop and quit, and two
; that are not the protocol's but every engine has, d to show the board
; and go perft N to count move paths.  While it thinks the engine reads
; stop, quit and isready between nodes.
;
; IO is (read say ready?): read answers the next line or () at the end
; of input, say writes text, ready? answers whether a line is waiting.

(module chess/uci)

(import chess/board pos-side legal-moves move-uci move-parse-uci gen-moves make! unmake! perft parse-int)
(import chess/search search-best mate-score? mate-in)
(import chess/game game-new game-pos game-play! game-fen)
(import chess/show show-board)
(import x/sys/gc)
(import x/core/doors io-display-to-str int/ int% int*)

(def chess-version "0.1.0")

(def %io-read (fn (_ io) ((List ref 0 io))))
(def %io-say (fn (_ io text) ((List ref 1 io) text)))
(def %io-ready? (fn (_ io) ((List ref 2 io))))

(def %words (fn (_ line) (List reject (fn (_ w) (str=? w "")) (Str8 split " " (Str8 replace "\t" " " line)))))

(def %num (fn (_ s) ((fn (_ n) (if (null? n) 0 n)) (parse-int s))))

; The value after KEY in WORDS, a number, or DFLT.
(def %after
  (fn (self words key dflt)
    (match ((null? words) dflt)
           ((null? (rest words)) dflt)
           ((str=? (first words) key) (%num (first (rest words))))
           (#t (self (rest words) key dflt)))))

; --- position ---------------------------------------------------------------------

; The game WORDS (past "position") set up, or () when it does not read.
(def %position
  (fn (_ words)
    (def moves-at (fn (self ws) (if (null? ws) () (if (str=? (first ws) "moves") (rest ws) (self (rest ws))))))
    (def before-moves (fn (self ws) (if (null? ws) () (if (str=? (first ws) "moves") () (pair (first ws) (self (rest ws)))))))
    (def g
      (guard (e ())
        (match
          ((null? words) ())
          ((str=? (first words) "startpos") (game-new ()))
          ((str=? (first words) "fen") (game-new (Str8 join " " (before-moves (rest words)))))
          (#t ()))))
    (if (null? g) ()
      (if (List all? (fn (_ t)
                       (def m (move-parse-uci (game-pos g) t))
                       (if (null? m) #f (do (game-play! g m) #t)))
            (moves-at words))
        g ()))))

; --- go -------------------------------------------------------------------------------

; How long to think, in milliseconds, for a go of WORDS with SIDE to
; move: movetime if given, else a slice of the clock, else no limit.
(def uci-think-ms
  (fn (_ words side)
    (def movetime (%after words "movetime" 0))
    (def clock (%after words (if (= side 0) "wtime" "btime") 0))
    (def inc (%after words (if (= side 0) "winc" "binc") 0))
    (def togo (%after words "movestogo" 30))
    (match
      ((< 0 movetime) movetime)
      ((< 0 clock)
        ; a share of what is left, never more than half of it
        ((fn (_ ms) (if (< (int/ clock 2) ms) (int/ clock 2) ms))
         ((fn (_ ms) (if (< ms 50) 50 ms)) (+ (int/ clock (if (< togo 1) 30 (+ togo 2))) (int/ (int* inc 3) 4)))))
      (#t 0))))

(def %score-text
  (fn (_ s)
    (if (mate-score? s)
      (Str8 append "mate " (io-display-to-str (mate-in s)))
      (Str8 append "cp " (io-display-to-str s)))))


; The info line for a finished depth's REPORT, (depth score nodes us move).
(def %info-line
  (fn (_ r)
    (def us (List ref 3 r))
    (def ms (int/ us 1000))
    (Str8 append "info depth " (io-display-to-str (List ref 0 r))
      " score " (%score-text (List ref 1 r))
      " nodes " (io-display-to-str (List ref 2 r))
      " time " (io-display-to-str ms)
      " nps " (io-display-to-str (if (< us 1) 0 (int/ (int* (List ref 2 r) 1000000) us)))
      " pv " (Str8 join " " (List map move-uci (List ref 5 r))) "\n")))

; Lines that came while thinking and were not the search's to act on.
(def %pending ())
(def %quit #f)

; The poll the search makes: act on stop, quit and isready.
(def %poll
  (fn (_ io)
    (fn (_)
      (if (not (%io-ready? io)) #f
        (do
          (def line (%io-read io))
          (def w (if (null? line) "quit" (Str8 trim line)))
          (match
            ((str=? w "stop") #t)
            ((str=? w "quit") (do (set! %quit #t) #t))
            ((str=? w "isready") (do (%io-say io "readyok\n") #f))
            (#t (do (set! %pending (List append %pending (list line))) #f))))))))

(def %go
  (fn (_ io g words)
    (def p (game-pos g))
    (if (str=? (if (null? words) "" (first words)) "perft")
      (%perft io p (%after words "perft" 1))
      (do
        (def depth (%after words "depth" 64))
        (def nodes (%after words "nodes" 0))
        (def ms (if (List any? (fn (_ w) (str=? w "infinite")) words) 0 (uci-think-ms words (pos-side p))))
        (def r (if (null? (legal-moves p)) ()
                 (search-best p depth ms nodes (%poll io) (fn (_ r) (%io-say io (%info-line r))))))
        (%io-say io (Str8 append "bestmove " (if (null? r) "0000" (move-uci (List ref 4 r))) "\n"))))))

; go perft N: each legal move's count, then the total.
(def %perft
  (fn (_ io p depth)
    (def counts
      (List map (fn (_ m) (make! p m)
                          (def n (if (< depth 2) 1 (perft p (- depth 1))))
                          (unmake! p m)
                          (pair m n))
        (legal-moves p)))
    (List for-each (fn (_ c) (%io-say io (Str8 append (move-uci (first c)) ": " (io-display-to-str (rest c)) "\n"))) counts)
    (%io-say io (Str8 append "\nNodes searched: " (io-display-to-str (List fold (fn (_ a c) (+ a (rest c))) 0 counts)) "\n\n"))))

; --- the loop -----------------------------------------------------------------------

; Answer one command LINE in game G: the game after it, or #f to quit.
(def %command
  (fn (_ io g line)
    (def words (%words line))
    (def cmd (if (null? words) "" (first words)))
    (match
      ((str=? cmd "uci")
        (do (%io-say io (Str8 append "id name x-chess " chess-version "\nid author Jon Ruttan\nuciok\n")) g))
      ((str=? cmd "isready") (do (%io-say io "readyok\n") g))
      ((str=? cmd "ucinewgame") (game-new ()))
      ((str=? cmd "position")
        ((fn (_ ng) (if (null? ng) (do (%io-say io (Str8 append "info string x-chess: cannot set up: " line "\n")) g) ng))
         (%position (rest words))))
      ((str=? cmd "go") (do (%go io g (rest words)) (if %quit #f g)))
      ((str=? cmd "d") (do (%io-say io (Str8 append (show-board (game-pos g) 0) "\nFen: " (game-fen g) "\n")) g))
      ((str=? cmd "quit") #f)
      (#t g))))

; Speak UCI over IO until quit or the end of input; FIRST, when not (),
; is a line already read.
(def uci-run
  (fn (_ io first-line)
    (set! %pending ())
    (set! %quit #f)
    (def next-line
      (fn (_)
        (if (null? %pending) (%io-read io)
          ((fn (_ l) (set! %pending (rest %pending)) l) (first %pending)))))
    (def go
      (fn (self g line)
        (def ng (if (null? line) #f (%command io g line)))
        (Heap collect)
        (if (eq? ng #f) 0 (self ng (next-line)))))
    (go (game-new ()) (if (null? first-line) (next-line) first-line))))


(provide chess/uci chess-version uci-run uci-think-ms)
