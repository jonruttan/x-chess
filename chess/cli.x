; # x-chess -- a chess engine on x-lang
;
; ## chess/cli.x -- the command line, and the terminal
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;   x -l chess -- [--white|--black|--both] [--fen FEN] [--time S] [--depth N] [--think] [--engine CMD]
;                  [--book FILE|--no-book]
;   x -l chess -- --puzzle | --puzzles FILE [--theme THEME] [--rating LOW-HIGH]
;   x -l chess -- --uci
;   x -l chess -- --perft N [--fen FEN]
;   x -l chess -- --match GAMES [--engine CMD [--engine CMD]] [--time S] [--depth N]
;   x -l chess -- --tables
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
(import x/core/doors str-make str-byte-ref str-byte-len str-byte-sub io-display-to-str int/ int%)
(import chess/board fen-start pos-from-fen perft parse-int)
(import chess/uci chess-version uci-run)
(import chess/play play-run)
(import chess/player player-builtin player-start player-quit!)
(import chess/match match-run)
(import chess/app app-run)
(import chess/puzzle puzzle-set puzzle-list-source puzzle-file-source puzzle-filter puzzle-range)
(import x/sys/date)
(import chess/book book-use!)
(import chess/tables tables-dir tables-allow-build! tables-build!)

(def %usage
  (Str8 join "\n"
    (list "usage: x -l chess -- [--white|--black|--both] [--fen FEN] [--time SECONDS] [--depth N] [--think] [--engine CMD] [--line] [--letters] [--coach]"
          "                         [--book FILE|--no-book]"
          "       x -l chess -- --puzzle | --puzzles FILE [--theme THEME] [--rating LOW-HIGH]"
          "       x -l chess -- --uci"
          "       x -l chess -- --perft N [--fen FEN]"
          "       x -l chess -- --match GAMES [--engine CMD [--engine CMD]] [--time SECONDS] [--depth N] [--fen FEN]"
          "       x -l chess -- --tables"
          ""
          "A game against the engine on a terminal, the board filling it (? lists the keys);"
          "--line plays it a line at a time instead (help lists the commands), --letters draws"
          "the pieces as letters, --coach judges your moves against the engine's."
          "--puzzle sets the puzzles made for x-chess on the board, --puzzles those of FILE,"
          "a CSV of the lichess puzzle database; --theme takes those with a theme of the"
          "database's (mateIn2, mate, fork, crushing, ...), --rating those rated in a range."
          "Fed lines, it speaks UCI when the first is `uci`, else plays them as moves."
          "--engine plays a UCI engine, CMD its program and arguments, in place of x-chess."
          "--match plays games between two engines (x-chess the first unless two are named),"
          "the PGN on standard output and the score on standard error."
          "It opens from its own book; --book FILE plays from a Polyglot book instead,"
          "--no-book from none.  --tables builds the endgame tables now and keeps them."
          "")))

(def %say (fn (_ fd text) (Sys fd-write fd text)))

(def %flag
  (list (pair "--white" (pair (lit side) (lit white)))
        (pair "--black" (pair (lit side) (lit black)))
        (pair "--both" (pair (lit side) (lit both)))
        (pair "--uci" (pair (lit uci) #t))
        (pair "--think" (pair (lit think) #t))
        (pair "--line" (pair (lit line) #t))
        (pair "--letters" (pair (lit letters) #t))
        (pair "--coach" (pair (lit coach) #t))
        (pair "--puzzle" (pair (lit puzzle) #t))
        (pair "--help" (pair (lit help) #t))
        (pair "-h" (pair (lit help) #t))
        (pair "--version" (pair (lit version) #t))
        (pair "--no-book" (pair (lit book) (lit none)))
        (pair "--tables" (pair (lit tables) #t))))

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
      ((str=? a "--book")
        (if (null? value) (list (pair (lit error) "--book takes a Polyglot file"))
          (self (List drop 2 args) (pair (pair (lit book) value) opts))))
      ((str=? a "--time") (number (lit seconds) 1 "a number of seconds"))
      ((str=? a "--depth") (number (lit depth) 1 "a number of plies"))
      ((str=? a "--perft") (number (lit perft) 0 "a depth"))
      ((str=? a "--match") (number (lit match) 1 "a number of games"))
      ((str=? a "--engine")
        (if (null? value) (list (pair (lit error) "--engine takes a command"))
          (self (List drop 2 args) (pair (pair (lit engine) value) opts))))
      ((str=? a "--puzzles")
        (if (null? value) (list (pair (lit error) "--puzzles takes a file"))
          (self (List drop 2 args) (pair (pair (lit puzzles) value) opts))))
      ((str=? a "--theme")
        (if (null? value) (list (pair (lit error) "--theme takes a theme: mateIn2, mate, fork, ..."))
          (self (List drop 2 args) (pair (pair (lit theme) value) opts))))
      ((str=? a "--rating")
        ((fn (_ r) (if (null? r) (list (pair (lit error) "--rating takes a range: LOW-HIGH, LOW- or -HIGH"))
                     (self (List drop 2 args) (pair (pair (lit rating) r) opts))))
         (if (null? value) () (puzzle-range value))))
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
      (if (null? (%opt opts (lit depth))) () (list (pair (lit depth) (%opt opts (lit depth)))))
      (if (null? (%opt opts (lit think))) () (list (pair (lit think) #t)))
      (if (null? (%opt opts (lit letters))) () (list (pair (lit letters) #t)))
      (if (null? (%opt opts (lit coach))) () (list (pair (lit coach) #t))))))

; The puzzles OPTS ask for, those of --theme and --rating: a source, or
; ().  Raises when the file cannot be opened.
(def %puzzles
  (fn (_ opts)
    (def theme (if (null? (%opt opts (lit theme))) "" (%opt opts (lit theme))))
    (def range (if (null? (%opt opts (lit rating))) (pair 0 0) (%opt opts (lit rating))))
    (def chosen
      (fn (_ source) (puzzle-filter source theme (first range) (rest range))))
    (match ((not (null? (%opt opts (lit puzzles)))) (chosen (puzzle-file-source (%opt opts (lit puzzles)))))
           ((not (null? (%opt opts (lit puzzle)))) (chosen (puzzle-list-source (puzzle-set))))
           (#t ()))))

; The --engine commands in OPTS, in the order given.
(def %engines
  (fn (_ opts)
    (List reverse (List map rest (List filter (fn (_ o) (eq? (first o) (lit engine))) opts)))))

; Today as PGN dates it.
(def %pgn-date
  (fn (_) (Str8 replace "-" "." (Str8 slice 0 10 (Date ->iso (Date local (Sys now)))))))

(def %game-session
  (fn (_ io opts first-line board)
    (def engines (%engines opts))
    (guard (e (do (%say 2 (Str8 append "x-chess: " (e msg) "\n")) 2))
      (do (def puzzles (%puzzles opts))
          (when (if (null? puzzles) #f (not board)) (Err raise (lit usage) "puzzles are solved on the board, on a terminal" ()))
          (def pl (player-start (if (null? engines) () (first engines))))
          ; the board has no line to say the endgame tables are building on
          (if board (do (tables-allow-build! #f) (app-run (List append (list (pair (lit engine) pl) (pair (lit puzzles) puzzles)) (%game-opts opts))))
            (play-run io (pair (pair (lit engine) pl) (%game-opts opts)) first-line))))))

(def %session
  (fn (_ opts)
    ; the launcher parks the caller's stdin on fd 3 while its boot
    ; stream holds fd 0; it is taken back, as x-grep and the REPL do
    (guard (e ()) (do (Sys dup2 3 0) (Sys close 3)))
    (def tty (if (Term tty? 0) (Sys isatty 1) #f))
    (def io (%io tty))
    (match
      ((not (null? (%opt opts (lit uci)))) (uci-run io ()))
      (tty (%game-session io opts () (null? (%opt opts (lit line)))))
      (#t ((fn (_ line)
             (match ((null? line) 0)
                    ((str=? (Str8 trim line) "uci") (uci-run io line))
                    (#t (%game-session io opts line #f))))
           (%pipe-line))))))

; --match: the PGN on standard output, the score on standard error.
(def %match-main
  (fn (_ opts)
    (def engines (%engines opts))
    (def secs (%opt opts (lit seconds)))
    (def started ())
    (def start (fn (_ cmd) ((fn (_ pl) (set! started (pair pl started)) pl) (player-start cmd))))
    (def status
      (guard (e (do (%say 2 (Str8 append "x-chess: " (e msg) "\n")) 2))
        (do (def a (if (< (List length engines) 2) (player-builtin) (start (first engines))))
            (def b (match ((null? engines) (player-builtin))
                          ((null? (rest engines)) (start (first engines)))
                          (#t (start (List ref 1 engines)))))
            (match-run a b (%opt opts (lit match))
              (list (pair (lit fen) (%opt opts (lit fen)))
                    (pair (lit depth) (if (null? (%opt opts (lit depth))) 0 (%opt opts (lit depth))))
                    (pair (lit ms) (if (null? secs) 1000 (* secs 1000)))
                    (pair (lit date) (%pgn-date)))
              (fn (_ text) (%say 1 text))
              (fn (_ text) (%say 2 text)))
            0)))
    (List for-each player-quit! started)
    status))

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
      ((< 2 (List length (%engines opts))) (do (%say 2 "x-chess: at most two engines play\n") 2))
      ((not (null? (%opt opts (lit tables)))) (%tables-main))
      ((%bad-book? (%opt opts (lit book)))
        (do (%say 2 (Str8 append "x-chess: no book at " (%opt opts (lit book)) "\n")) 2))
      ((not (null? (%opt opts (lit match)))) (do (%use-book! (%opt opts (lit book))) (%match-main opts)))
      (#t (do (%use-book! (%opt opts (lit book))) (tables-allow-build! #t) (%session opts))))))

; --book FILE plays from FILE, --no-book from none, neither from the
; built-in book.
(def %use-book!
  (fn (_ b)
    (match ((null? b) ()) ((eq? b (lit none)) (book-use! ())) (#t (book-use! b)))))

(def %bad-book? (fn (_ b) (if (str? b) (not (File exists? b)) #f)))

; Build the endgame tables and keep them where they are looked for.
(def %tables-main
  (fn (_)
    (def dir (tables-dir))
    (def secs (fn (_ us) (Str8 append (io-display-to-str (int/ us 1000000)) "." (io-display-to-str (int/ (int% us 1000000) 100000)) " s")))
    (def times (tables-build! dir))
    (%say 1 (Str8 append "x-chess: KQK " (secs (first times)) ", KRK " (secs (List ref 1 times))
              ", KPK " (secs (List ref 2 times)) (if (null? dir) ", kept in memory only\n" (Str8 append ", kept in " dir "\n"))))
    0))

(provide chess/cli chess-main chess-options)
