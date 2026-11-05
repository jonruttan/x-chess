; # x-chess -- a chess engine on x-lang
;
; ## chess/play.x -- playing a game at the terminal
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A move is typed in SAN (Nf3, exd5, O-O, e8=Q) or long algebraic
; (g1f3); anything else is a command, `help` lists them.  The engine
; answers each move of yours; `go` has it play the side to move and you
; take the other, `both` has you play both sides.
;
; IO is (read say ready?) as in chess/uci.x; read takes the prompt.

(module chess/play)

(import x/sys/gc)
(import x/core/doors io-display-to-str int/ int% int*)
(import chess/board pos-side in-check? legal-moves parse-int)
(import chess/search mate-score? mate-in)
(import chess/game game-new game-pos game-fen game-moves game-play! game-undo! game-result game-movetext)
(import chess/san move-san moves-san move-parse)
(import chess/player player-builtin player-start player-name player-think player-quit!)
(import chess/show show-board)
(import chess/uci chess-version)

(def %help
  (Str8 join "\n"
    (list "Type a move in SAN (e4, Nf3, exd5, O-O, e8=Q) or long algebraic (e2e4)."
          "Commands:"
          "  go             the engine plays the side to move; you take the other"
          "  white, black   play that side against the engine"
          "  both           play both sides; go asks the engine for one move"
          "  undo           take back your last move"
          "  new            a new game"
          "  fen [FEN]      show the position as FEN, or set it up"
          "  moves          the legal moves"
          "  pgn            the moves of the game"
          "  hint           the move the engine would play"
          "  time SECONDS   how long the engine thinks (now %t)"
          "  depth N        how deep it looks at most (now %d)"
          "  board, flip    show the board, turn it around"
          "  think          show the engine's thinking, or stop showing it"
          "  engine [CMD]   play a UCI engine, or x-chess again; alone, name the engine"
          "  help, quit"
          "")))

; The session: a Vector of the game, who you play (white black both),
; the thinking time in milliseconds, the depth limit, the side the
; board is seen from, and whether the board is to be shown.
(def %s-game 0)
(def %s-human 1)
(def %s-ms 2)
(def %s-depth 3)
(def %s-view 4)
(def %s-fresh 5)
(def %s-engine 6)
(def %s-think 7)

(def %get (fn (_ st i) (Vector ref i st)))
(def %put! (fn (_ st i v) (Vector set! i v st)))

(def %say (fn (_ io text) ((List ref 1 io) text)))

(def %side-name (fn (_ side) (if (= side 0) "White" "Black")))

; Whether the engine plays the side to move.
(def %engine-to-move?
  (fn (_ st)
    (def side (pos-side (game-pos (%get st %s-game))))
    (match ((eq? (%get st %s-human) (lit both)) #f)
           ((eq? (%get st %s-human) (lit white)) (= side 8))
           (#t (= side 0)))))

; A score for people: +0.35 from the side to move's view, or mate in N.
(def %score-text
  (fn (_ s)
    (if (mate-score? s)
      (Str8 append "mate in " (io-display-to-str (if (< 0 (mate-in s)) (mate-in s) (- 0 (mate-in s))))
        (if (< 0 s) "" " against"))
      (Str8 append (if (< s 0) "-" "+")
        (io-display-to-str (int/ (if (< s 0) (- 0 s) s) 100)) "."
        ((fn (_ c) (Str8 append (if (< c 10) "0" "") (io-display-to-str c))) (int% (if (< s 0) (- 0 s) s) 100))))))

; The engine's choice in ST's game: its last report, each depth's shown
; as it finishes when thinking is shown.
(def %think
  (fn (_ io st)
    (def g (%get st %s-game))
    (player-think (%get st %s-engine) g (%get st %s-depth) (%get st %s-ms) (fn (_) #f)
      (fn (_ r) (when (%get st %s-think) (%say io (%thinking-text (game-pos g) r)))))))

; A report as a line of thinking: depth, score, the line in SAN, the work.
(def %thinking-text
  (fn (_ p r)
    (Str8 append "  " (Str8 pad-left 2 #\space (io-display-to-str (List ref 0 r))) "  "
      (Str8 pad-left 7 #\space (%score-text (List ref 1 r))) "  "
      (Str8 join " " (moves-san p (List ref 5 r)))
      "  (" (io-display-to-str (List ref 2 r)) " nodes, " (%seconds (List ref 3 r)) ")\n")))

(def %seconds
  (fn (_ us)
    (Str8 append (io-display-to-str (int/ us 1000000)) "." (io-display-to-str (int/ (int% us 1000000) 100000)) " s")))

(def %report-text
  (fn (_ r)
    (Str8 append "depth " (io-display-to-str (List ref 0 r)) ", " (%score-text (List ref 1 r)) ", "
      (io-display-to-str (List ref 2 r)) " nodes, "
      (io-display-to-str (int/ (List ref 3 r) 1000000)) "."
      (io-display-to-str (int/ (int% (List ref 3 r) 1000000) 100000)) " s")))

; The engine plays the side to move.
(def %engine-move!
  (fn (_ io st)
    (def g (%get st %s-game))
    (def r (%think io st))
    (if (null? r)
      (do (%say io (Str8 append (player-name (%get st %s-engine)) " has no move: you play both sides.\n"))
          (%put! st %s-human (lit both)))
      (do (def san (move-san (game-pos g) (List ref 4 r)))
          (game-play! g (List ref 4 r))
          (%put! st %s-fresh #t)
          (%say io (Str8 append (player-name (%get st %s-engine)) " plays " san "  (" (%report-text r) ")\n"))))))

; Play against the engine COMMAND names (x-chess's own when ()), the one
; played until now let go.
(def %engine!
  (fn (_ io st command)
    (if (null? command)
      (%say io (Str8 append "The engine is " (player-name (%get st %s-engine)) ".\n"))
      (guard (e (%say io (Str8 append "x-chess: " (e msg) "\n")))
        (do (def pl (player-start command))
            (player-quit! (%get st %s-engine))
            (%put! st %s-engine pl)
            (%say io (Str8 append "The engine is " (player-name pl) ".\n")))))))

(def %show
  (fn (_ io st)
    (def p (game-pos (%get st %s-game)))
    (%put! st %s-fresh #f)
    (%say io (Str8 append (show-board p (%get st %s-view)) "\n"))))

(def %status
  (fn (_ io st)
    (def p (game-pos (%get st %s-game)))
    (%say io (Str8 append (%side-name (pos-side p)) " to move" (if (in-check? p) ", in check" "") ".\n"))))

; --- commands ----------------------------------------------------------------------

(def %words (fn (_ line) (List reject (fn (_ w) (str=? w "")) (Str8 split " " (Str8 replace "\t" " " line)))))

(def %num (fn (_ s) ((fn (_ n) (if (null? n) 0 n)) (parse-int s))))

; Your side after choosing WHO: the board turns to face you.
(def %play-as!
  (fn (_ st who)
    (%put! st %s-human who)
    (%put! st %s-view (if (eq? who (lit black)) 8 0))
    (%put! st %s-fresh #t)))

(def %help-text
  (fn (_ st)
    (Str8 replace "%d" (io-display-to-str (%get st %s-depth))
      (Str8 replace "%t" (Str8 append (io-display-to-str (int/ (%get st %s-ms) 1000)) " s") %help))))

; Act on LINE: #f to quit, else #t.
(def %command
  (fn (_ io st line)
    (def words (%words line))
    (def cmd (if (null? words) "" (Str8 downcase (first words))))
    (def arg (if (null? words) () (if (null? (rest words)) () (Str8 join " " (rest words)))))
    (def g (%get st %s-game))
    (match
      ((str=? cmd "") #t)
      ((if (str=? cmd "quit") #t (str=? cmd "exit")) #f)
      ((str=? cmd "help") (do (%say io (%help-text st)) #t))
      ((str=? cmd "board") (do (%show io st) #t))
      ((str=? cmd "flip") (do (%put! st %s-view (- 8 (%get st %s-view))) (%show io st) #t))
      ((str=? cmd "white") (do (%play-as! st (lit white)) #t))
      ((str=? cmd "black") (do (%play-as! st (lit black)) #t))
      ((str=? cmd "both") (do (%put! st %s-human (lit both)) #t))
      ((str=? cmd "think")
        (do (%put! st %s-think (not (%get st %s-think)))
            (%say io (if (%get st %s-think) "Thinking is shown.\n" "Thinking is not shown.\n"))
            #t))
      ((str=? cmd "engine") (do (%engine! io st arg) #t))
      ((str=? cmd "new") (do (%put! st %s-game (game-new ())) (%put! st %s-fresh #t) #t))
      ((str=? cmd "undo") (do (%undo! io st) #t))
      ((str=? cmd "moves")
        (do (%say io (Str8 append (Str8 join " " (List map (fn (_ m) (move-san (game-pos g) m)) (legal-moves (game-pos g)))) "\n")) #t))
      ((str=? cmd "pgn") (do (%say io (Str8 append (game-movetext g) "\n")) #t))
      ((str=? cmd "fen")
        (do (if (null? arg) (%say io (Str8 append (game-fen g) "\n"))
              (guard (e (%say io (Str8 append "x-chess: " (e msg) "\n")))
                (do (%put! st %s-game (game-new arg)) (%put! st %s-fresh #t))))
            #t))
      ((str=? cmd "time")
        (do (if (< 0 (%num arg)) (%put! st %s-ms (int* 1000 (%num arg))) (%say io "x-chess: time takes a number of seconds\n")) #t))
      ((str=? cmd "depth")
        (do (if (< 0 (%num arg)) (%put! st %s-depth (%num arg)) (%say io "x-chess: depth takes a number of plies\n")) #t))
      ((str=? cmd "hint")
        (do (if (null? (game-result g))
              ((fn (_ r) (%say io (Str8 append (player-name (%get st %s-engine)) " suggests " (move-san (game-pos g) (List ref 4 r)) "  (" (%report-text r) ")\n")))
               (%think io st))
              (%say io "The game is over.\n"))
            #t))
      ((str=? cmd "go")
        (do (if (null? (game-result g))
              (do (unless (eq? (%get st %s-human) (lit both))
                    (%play-as! st (if (= (pos-side (game-pos g)) 0) (lit black) (lit white))))
                  (%engine-move! io st))
              (%say io "The game is over.\n"))
            #t))
      (#t (do (%move! io st (first words)) #t)))))

(def %move!
  (fn (_ io st text)
    (def g (%get st %s-game))
    (def m (if (null? (game-result g)) (move-parse (game-pos g) text) ()))
    (match
      ((not (null? (game-result g))) (%say io "The game is over: new starts another, undo takes a move back.\n"))
      ((null? m) (%say io (Str8 append "Not a legal move here: " text ".  moves lists them, help the commands.\n")))
      (#t (do (game-play! g m) (%put! st %s-fresh #t))))))

; Take back your last move, and the engine's reply to it.
(def %undo!
  (fn (_ io st)
    (def g (%get st %s-game))
    (if (null? (game-moves g)) (%say io "There is no move to take back.\n")
      (do (game-undo! g)
          (when (if (%engine-to-move? st) (not (null? (game-moves g))) #f) (game-undo! g))
          (%put! st %s-fresh #t)))))

; --- the loop -----------------------------------------------------------------------

; One turn: announce a finished game, let the engine move, or read a
; line.  Answers the exit status when the session ends, else ().
(def %turn
  (fn (_ io st first-line)
    (def g (%get st %s-game))
    (def result (game-result g))
    (Heap collect)
    (match
      ((if (null? result) (if (null? first-line) (%engine-to-move? st) #f) #f)
        (do (%engine-move! io st) ()))
      (#t (%read-turn io st result first-line)))))

(def %read-turn
  (fn (_ io st result first-line)
    (when (null? first-line)
      (when (%get st %s-fresh)
        (%show io st)
        (if (null? result) (%status io st)
          (%say io (Str8 append "Game over: " (rest result) ", " (first result) ".\n")))))
    (def p (game-pos (%get st %s-game)))
    (def line (if (null? first-line) ((List ref 0 io) (Str8 append (Str8 downcase (%side-name (pos-side p))) "> ")) first-line))
    (match ((null? line) 0)
           ((%command io st line) ())
           (#t 0))))

; Play over IO.  OPTS is an alist: fen, side (white black both), ms,
; depth, engine (a player, x-chess's own when absent) and think (#t to
; show the engine's thinking).  FIRST, when not (), is a line already
; read.  Answers the exit status; the engine played last is let go.
(def play-run
  (fn (_ io opts first-line)
    (def opt (fn (_ k d) ((fn (_ p) (if (null? p) d (rest p))) (Assoc find k opts))))
    (def st (Vector make 8 ()))
    (%put! st %s-game (game-new (opt (lit fen) ())))
    (%put! st %s-ms (opt (lit ms) 5000))
    (%put! st %s-depth (opt (lit depth) 64))
    (%put! st %s-engine (opt (lit engine) (player-builtin)))
    (%put! st %s-think (opt (lit think) #f))
    (%play-as! st (opt (lit side) (lit white)))
    (when (null? first-line)
      (%say io (Str8 append "x-chess " chess-version ": you play " (match ((eq? (%get st %s-human) (lit black)) "black") ((eq? (%get st %s-human) (lit both)) "both sides") (#t "white"))
                 "; help lists the commands.\n")))
    (def go
      (fn (self line)
        (def status (%turn io st line))
        (if (null? status) (self ()) status)))
    (def status (go first-line))
    (player-quit! (%get st %s-engine))
    status))

(provide chess/play play-run)
