; # x-chess -- a chess engine on x-lang
;
; ## chess/tui.x -- the board on a whole terminal: its state, keys and drawing
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; What the terminal shows and what a key does to it, kept apart from the
; terminal itself (chess/app) so that a spec can press keys and read the
; screen back.  The board takes the left of the screen, its squares as
; large as the terminal allows; beside it a bar shows who stands better,
; and to the right are the engine's thinking and the moves.  The side at
; the top and the side at the bottom each have a strip with their name,
; what they have taken and their clock.
;
; A move is made by typing it (SAN or long algebraic, then Enter), by
; clicking its square and then where it goes, or with the arrows and
; Enter.  Keys that cannot begin a move are commands: ? lists them.
;
; The state is a Vector; the slots are named below.

(module chess/tui)

(import x/tui/screen)
(import x/tui/style)
(import x/sys/file)
(import x/core/doors io-display-to-str int/ int% int* int+ int-)
(import chess/board PAWN KNIGHT BISHOP ROOK QUEEN KING pos-piece pos-side pos-full pos-copy piece-kind piece-colour
  sq-file sq-rank sq-make sq-name move-from move-to move-promo move-uci move-parse-uci make! in-check? legal-moves
  pos-from-fen pos-fen fen-start parse-int)
(import chess/search mate-score? mate-in)
(import chess/game game-new game-pos game-start game-moves game-play! game-undo! game-result game-pgn)
(import chess/san move-san moves-san move-parse)
(import chess/player player-builtin player-start player-name player-quit!)
(import chess/puzzle puzzle-fen puzzle-title puzzle-rating puzzle-id puzzle-solution puzzle-judge puzzle-set
  puzzle-list-source puzzle-file-source puzzle-filter puzzle-range puzzle-library puzzle-counts puzzle-count)
(import chess/record record-path record-load record-add! record-solved? record-unsolved record-score)
(import chess/daily daily-path daily-fetch daily-get)

(def %game 0)
(def %view 1)       ; the side at the bottom: 0 white, 8 black
(def %cursor 2)     ; the square the arrows move, 0x88
(def %sel 3)        ; the square picked up, or -1
(def %human 4)      ; white, black or both
(def %engine 5)     ; the player the engine is
(def %ms 6)
(def %depth 7)
(def %thinking 8)   ; lines of the engine's thinking, newest first
(def %msg 9)
(def %input 10)     ; a move being typed
(def %review 11)    ; the ply shown when going back through the game, or -1
(def %show-think 12)
(def %letters 13)   ; letters for the pieces, not their figures
(def %analyse 14)
(def %quit 15)
(def %stats 16)     ; the line about the search in hand
(def %eval 17)      ; the last score, white's view, or ()
(def %help 18)
(def %cursor-on 19)
(def %hint 20)      ; a move shown as a hint, or 0
(def %command 21)   ; a : command being typed, or ()
(def %promo 22)     ; the squares of a promotion waiting for its piece, or ()
(def %start-cache 23) ; (start FEN . its position), parsed once a game
(def %san-cache 24)   ; (start FEN, moves, sans): the SAN of the moves last drawn
(def %puzzle 25)      ; puzzles being solved: see tui-puzzles!, or ()
(def %coach 26)       ; whether your moves are judged
(def %expect 27)      ; the reply the engine expects of you: (score move . san), or ()
(def %choose 28)      ; whether the choice of puzzles is shown
(def %band 29)        ; the rating band the choice picks from, an index of %bands
(def %record 30)      ; the puzzles finished, read at first need: see chess/record
(def %record-path 31) ; the file they are kept in
(def %counts-read 32) ; (the library's counts, or ()) once read: see %library-counts
(def %pending 33)     ; work to do once the screen is drawn: a function of the state, or ()
(def %daily 34)       ; (path . fetch) for the puzzle of the day: see chess/daily
(def %theme 35)       ; how the board is drawn: one of %themes
(def %slots 36)

(def %get (fn (_ st i) (Vector ref i st)))
(def %max (fn (_ a b) (if (< a b) b a)))
(def %min (fn (_ a b) (if (< a b) a b)))
(def %put! (fn (_ st i v) (Vector set! i v st)))

; A board view of game G: OPTS as play-run takes them.
(def tui-make
  (fn (_ opts)
    (def opt (fn (_ k d) ((fn (_ p) (if (null? p) d (rest p))) (Assoc find k opts))))
    (def st (Vector make %slots ()))
    (%put! st %game (game-new (opt (lit fen) ())))
    (%put! st %human (opt (lit side) (lit white)))
    (%put! st %view (if (eq? (%get st %human) (lit black)) 8 0))
    (%put! st %cursor (if (eq? (%get st %human) (lit black)) 100 4))
    (%put! st %sel -1)
    (%put! st %engine (opt (lit engine) (player-builtin)))
    (%put! st %ms (opt (lit ms) 5000))
    (%put! st %depth (opt (lit depth) 64))
    (%put! st %thinking ())
    (%put! st %msg "")
    (%put! st %input "")
    (%put! st %review -1)
    (%put! st %show-think #t)
    (%put! st %letters (opt (lit letters) #f))
    (%put! st %analyse #f)
    (%put! st %quit #f)
    (%put! st %stats "")
    (%put! st %help #f)
    (%put! st %cursor-on #f)
    (%put! st %hint 0)
    (%put! st %coach (opt (lit coach) #f))
    (%put! st %choose #f)
    (%put! st %band 0)
    (%put! st %record-path (opt (lit record) (record-path)))
    (%put! st %daily (opt (lit daily) (pair (daily-path) daily-fetch)))
    (%put! st %theme ((fn (_ t) (if (null? t) (first %themes) t)) (tui-theme (opt (lit board) ""))))
    (unless (null? (opt (lit puzzles) ())) (tui-puzzles! st (opt (lit puzzles) ())))
    st))

(def tui-game (fn (_ st) (%get st %game)))
(def tui-quit? (fn (_ st) (%get st %quit)))
(def tui-engine (fn (_ st) (%get st %engine)))
(def tui-depth (fn (_ st) (%get st %depth)))
(def tui-ms (fn (_ st) (%get st %ms)))
(def tui-analysing? (fn (_ st) (%get st %analyse)))
(def tui-message! (fn (_ st text) (%put! st %msg text)))

(def %side-name (fn (_ side) (if (= side 0) "White" "Black")))

; Whether the engine is to move: not over, not looking back, not
; analysing, and the side to move not yours.
(def tui-engine-to-move?
  (fn (_ st)
    (def side (pos-side (game-pos (%get st %game))))
    (match
      ((not (null? (%get st %puzzle))) #f)
      ((%get st %analyse) #f)
      ((not (null? (game-result (%get st %game)))) #f)
      ((< -1 (%get st %review)) #f)
      ((eq? (%get st %human) (lit both)) #f)
      ((eq? (%get st %human) (lit white)) (= side 8))
      (#t (= side 0)))))

; --- the engine's reports ---------------------------------------------------------

; A score for people, white's view: +0.35, or #3 for mate in three.
(def %score-text
  (fn (_ s)
    (if (mate-score? s)
      (Str8 append "#" (io-display-to-str (mate-in s)))
      (Str8 append (if (< s 0) "-" "+")
        (io-display-to-str (int/ (if (< s 0) (- 0 s) s) 100)) "."
        ((fn (_ c) (Str8 append (if (< c 10) "0" "") (io-display-to-str c))) (int% (if (< s 0) (- 0 s) s) 100))))))

(def %seconds
  (fn (_ us) (Str8 append (io-display-to-str (int/ us 1000000)) "." (io-display-to-str (int/ (int% us 1000000) 100000)) " s")))

; Report R of a search of P: a line of thinking, the score turned to
; white's view, and the figures the panel heads them with.
(def tui-report!
  (fn (_ st p r)
    (def white-score (if (= (pos-side p) 0) (List ref 1 r) (- 0 (List ref 1 r))))
    (def line (Str8 append (Str8 pad-left 3 #\space (io-display-to-str (List ref 0 r))) " "
                (Str8 pad-left 6 #\space (%score-text white-score)) "  "
                (Str8 join " " (moves-san p (List ref 5 r)))))
    (%put! st %thinking (List take 12 (pair line (%get st %thinking))))
    (%put! st %eval white-score)
    (%put! st %stats
      (Str8 append "depth " (io-display-to-str (List ref 0 r)) " · "
        (io-display-to-str (List ref 2 r)) " nodes · " (%seconds (List ref 3 r))))))

(def tui-thinking-clear!
  (fn (_ st) (%put! st %thinking ()) (%put! st %stats "")))

; The engine's move M made; R, when given, is the report it came from,
; which the coach judges your last move by.
(def tui-engine-played!
  (fn (_ st m . more)
    (def r (if (null? more) () (first more)))
    (def g (%get st %game))
    (def said (%coach-says st r))
    (def san (move-san (game-pos g) m))
    (game-play! g m)
    (%put! st %hint 0)
    (%put! st %msg (Str8 append said (player-name (%get st %engine)) " plays " san))
    (%put! st %expect (%expectation st r))
    (%after-move! st)))

; --- the coach ----------------------------------------------------------------------
;
; When the engine moves, the second move of its line is the reply it
; expects of you, and its score the one it expects to see next.  Its
; next score, less that, is what your move cost: from 70 an inaccuracy,
; from 150 a mistake, from 300 a blunder.

(def %expectation
  (fn (_ st r)
    (def line (if (null? r) () (List ref 5 r)))
    (if (if (null? line) #t (null? (rest line))) ()
      ((fn (_ m) (list (List ref 1 r) (move-uci m) (move-san (game-pos (%get st %game)) m))) (first (rest line))))))

; What the coach says of your last move, given the engine's report R.
(def %coach-says
  (fn (_ st r)
    (def e (%get st %expect))
    (def ms (game-moves (%get st %game)))
    (if (if (%get st %coach) (if (null? r) #f (if (null? e) #f (not (null? ms)))) #f)
      (%verdict (- (List ref 1 r) (first e)) (str=? (move-uci (List last ms)) (List ref 1 e)) (List ref 2 e))
      "")))

(def %verdict
  (fn (_ loss best better)
    (def worse (fn (_ what) (Str8 append what ": " better " was better.  ")))
    (match (best "Best.  ")
           ((< 299 loss) (worse "A blunder"))
           ((< 149 loss) (worse "A mistake"))
           ((< 69 loss) (worse "An inaccuracy"))
           (#t "Good.  "))))

(def %coach!
  (fn (_ st)
    (%put! st %coach (not (%get st %coach)))
    (%put! st %expect ())
    (%put! st %msg (if (%get st %coach) "The coach judges your moves against the engine's." "The coach is off."))))

(def tui-hint!
  (fn (_ st m)
    (%put! st %hint m)
    (%put! st %msg (Str8 append "Hint: " (move-san (game-pos (%get st %game)) m)))))

; --- moves -------------------------------------------------------------------------

; After a move: the game's end said, if it has come.
(def %after-move!
  (fn (_ st)
    (def r (game-result (%get st %game)))
    (unless (null? r)
      (%put! st %msg (Str8 append (%result-text (first r)) " by " (rest r) ".  n starts a new game, u takes a move back.")))))

(def %result-text
  (fn (_ r)
    (match ((str=? r "1-0") "White wins")
           ((str=? r "0-1") "Black wins")
           (#t "Drawn"))))

; Whether the side to move is one you play.
(def %yours?
  (fn (_ st)
    (def side (pos-side (game-pos (%get st %game))))
    (match ((%get st %analyse) #t)
           ((eq? (%get st %human) (lit both)) #t)
           ((eq? (%get st %human) (lit white)) (= side 0))
           (#t (= side 8)))))

(def %play-move!
  (fn (_ st m)
    (game-play! (%get st %game) m)
    (%put! st %sel -1)
    (%put! st %input "")
    (%put! st %hint 0)
    (%put! st %promo ())
    (%put! st %msg "")
    (when (%get st %analyse) (tui-thinking-clear! st))
    (%after-move! st)))

; Move M made: judged first when a puzzle is being solved.
(def %play!
  (fn (_ st m)
    (if (if (null? (%get st %puzzle)) #t (%get st %analyse)) (%play-move! st m) (%puzzle-move! st m "Right.  "))))

; Whether a move can be made now, and if not, why: a message, or ().
(def %cannot-move
  (fn (_ st)
    (match
      ((< -1 (%get st %review)) "You are looking back: End returns to the game.")
      ((not (null? (game-result (%get st %game)))) "The game is over: n starts a new one, u takes a move back.")
      ((not (%yours? st)) "It is not your move.")
      (#t ()))))

(def %move-typed!
  (fn (_ st text)
    (def why (%cannot-move st))
    (def m (if (null? why) (move-parse (game-pos (%get st %game)) text) ()))
    (match
      ((not (null? why)) (%put! st %msg why))
      ((null? m) (%put! st %msg (%not-legal (game-pos (%get st %game)) text)))
      (#t (%play! st m)))
    (%put! st %input "")))

; Why TEXT is no move in P.  A promotion named without its piece is told
; how it is written, for a queen and the others.
(def %not-legal
  (fn (_ p text)
    (def q ((fn (_ m) (if (null? m) (move-parse p (Str8 append text "=Q")) m)) (move-parse p (Str8 append text "q"))))
    (if (null? q) (Str8 append "Not a legal move here: " text)
      (Str8 append text " promotes: say to what, " (move-uci q) " or " (move-san p q)
        " for a queen; r, b or n for the others."))))

; The legal moves from square FROM.
(def %moves-from
  (fn (_ st from) (List filter (fn (_ m) (= (move-from m) from)) (legal-moves (game-pos (%get st %game))))))

; Pick up or put down at SQ.
(def %pick!
  (fn (_ st sq)
    (def p (game-pos (%get st %game)))
    (def pc (pos-piece p sq))
    (def own (if (< 0 pc) (= (piece-colour pc) (pos-side p)) #f))
    (def why (%cannot-move st))
    (def sel (%get st %sel))
    (match
      ((not (null? why)) (%put! st %msg why))
      ((= sel sq) (%put! st %sel -1))
      (own (do (%put! st %sel sq) (%put! st %msg "")))
      ((= sel -1) (%put! st %msg "Pick up one of your pieces."))
      (#t (%put-down! st sel sq)))))

(def %put-down!
  (fn (_ st from to)
    (def ms (List filter (fn (_ m) (= (move-to m) to)) (%moves-from st from)))
    (match
      ((null? ms) (do (%put! st %sel -1) (%put! st %msg "Not a legal move.")))
      ((null? (rest ms)) (%play! st (first ms)))
      (#t (do (%put! st %promo (pair from to))
              (%put! st %msg "Promote to: click a piece, or q queen, r rook, b bishop, n knight"))))))

; The pieces a promotion waiting for its piece offers, as (SQUARE . KIND):
; down the file of the square put down on, from it toward the middle.
(def %promo-choices
  (fn (_ st)
    (def to (rest (%get st %promo)))
    (def step (if (= (sq-rank to) 7) -1 1))
    (List map (fn (_ i) (pair (sq-make (sq-file to) (+ (sq-rank to) (* i step))) (List ref i (list QUEEN ROOK BISHOP KNIGHT))))
      (List range 0 4))))

; The kind of piece the promotion picker offers on SQ, or 0.
(def %promo-kind-at
  (fn (_ st sq)
    (if (null? (%get st %promo)) 0
      ((fn (_ c) (if (null? c) 0 (rest c))) (List find (fn (_ c) (= (first c) sq)) (%promo-choices st))))))

(def %promo-off!
  (fn (_ st msg) (%put! st %promo ()) (%put! st %sel -1) (%put! st %msg msg)))

; A key while a promotion waits: a letter or a click on the picker
; chooses; a button let go or a drag is not an answer.
(def %promo-key!
  (fn (_ st key)
    (match
      ((str? key) (%promote! st key))
      ((if (pair? key) (eq? (first key) (lit mouse)) #f)
        (when (if (= (List ref 1 key) 0) (List ref 4 key) #f)
          ((fn (_ kind) (if (< 0 kind) (%promote-kind! st kind) (%promo-off! st "No promotion made.")))
           (%promo-kind-at st (%square-at st (- (List ref 3 key) 1) (- (List ref 2 key) 1))))))
      (#t (%promo-off! st "")))))

(def %promote!
  (fn (_ st letter)
    (%promote-kind! st (match ((str=? letter "q") QUEEN) ((str=? letter "r") ROOK) ((str=? letter "b") BISHOP)
                              ((str=? letter "n") KNIGHT) (#t 0)))))

(def %promote-kind!
  (fn (_ st kind)
    (def from (first (%get st %promo)))
    (def to (rest (%get st %promo)))
    (def m (List find (fn (_ m) (if (= (move-to m) to) (= (move-promo m) kind) #f)) (%moves-from st from)))
    (match
      ((null? m) (%promo-off! st "No promotion made."))
      (#t (do (%put! st %promo ()) (%play! st m))))))

; --- puzzles -----------------------------------------------------------------------
;
; Puzzle mode holds a Vector: 0 the source the puzzles come from, 1 the
; puzzle, 2 its solution still to play, 3 how many were solved, 4 how
; many tried, 5 whether this one was missed (a wrong move, a hint, the
; answer shown).  You play the side to move; your right moves are
; answered with the solution's replies.

(def %pz (fn (_ st i) (Vector ref i (%get st %puzzle))))
(def %pz! (fn (_ st i v) (Vector set! i v (%get st %puzzle))))

; The puzzles finished, read from their file the first time they are
; asked for.
(def %record-of
  (fn (_ st)
    (when (null? (%get st %record)) (%put! st %record (record-load (%get st %record-path))))
    (%get st %record)))

; Solve the puzzles SOURCE gives, one after another, those solved before
; passed over.
(def tui-puzzles!
  (fn (_ st source)
    (def pz (Vector make 6 ()))
    (Vector set! 0 (record-unsolved (%record-of st) source) pz)
    (Vector set! 3 0 pz)
    (Vector set! 4 0 pz)
    (%put! st %puzzle pz)
    (%put! st %analyse #f)
    (%next-puzzle! st)))

(def %count-text
  (fn (_ st) (Str8 append (io-display-to-str (%pz st 3)) " of " (io-display-to-str (%pz st 4)) " solved")))

(def %next-puzzle!
  (fn (_ st)
    (def z ((%pz st 0)))
    (if (null? z)
      (do (%put! st %msg (Str8 append "No more puzzles: " (%count-text st) "."))
          (%put! st %puzzle ())
          (%put! st %human (lit both)))
      (do (%put! st %game (game-new (puzzle-fen z)))
          (def side (pos-side (game-pos (%get st %game))))
          (%pz! st 1 z)
          (%pz! st 2 (puzzle-solution z))
          (%pz! st 4 (+ 1 (%pz st 4)))
          (%pz! st 5 #f)
          (%put! st %human (if (= side 0) (lit white) (lit black)))
          (%put! st %view side)
          (%put! st %sel -1) (%put! st %review -1) (%put! st %hint 0) (%put! st %promo ())
          (%put! st %eval ()) (%put! st %expect ())
          (tui-thinking-clear! st)
          (%put! st %msg (Str8 append (puzzle-title z) ": " (%side-name side) " to move."))))))

; z: the next puzzle, or the choice of puzzles when none is being solved.
(def %puzzle-key!
  (fn (_ st)
    (if (null? (%get st %puzzle)) (%put! st %choose #t) (%next-puzzle! st))))

; The choice z offers of the library's puzzles: the key, the theme (as
; puzzle-file-source takes it), and what is said of it.
(def %choices
  (list (list "1" "mateIn1" "Mate in one")
        (list "2" "mateIn2" "Mate in two")
        (list "3" "mateIn3" "Mate in three")
        (list "4" "mateIn4" "Mate in four")
        (list "5" "mateIn5" "Mate in five")
        (list "f" "fork" "Forks")
        (list "p" "pin" "Pins")
        (list "s" "skewer" "Skewers")
        (list "d" "discoveredAttack" "Discovered attacks")
        (list "t" "trappedPiece" "Trapped pieces")
        (list "h" "hangingPiece" "Pieces left hanging")
        (list "e" "endgame" "Endgames")
        (list "a" "" "All of them")))

; The rating bands < and > step through: what is said, low, high.
(def %bands
  (list (list "any rating" 0 0) (list "rated below 1000" 0 999) (list "rated 1000 to 1399" 1000 1399)
        (list "rated 1400 to 1799" 1400 1799) (list "rated 1800 to 2199" 1800 2199)
        (list "rated 2200 and up" 2200 0)))

; Puzzles of THEME from the library, in the band chosen, easiest first:
; a source.  Raises when the library cannot be read.
(def %chosen
  (fn (_ st theme)
    (def b (List ref (%get st %band) %bands))
    (def lib (puzzle-library))
    (when (null? lib) (Err raise (lit io) "the puzzle library is not there" ()))
    (puzzle-file-source lib theme (List ref 1 b) (List ref 2 b))))

; Set the puzzles of THEME the choice picks, or say why there are none.
(def %start-chosen!
  (fn (_ st theme)
    (guard (e (%put! st %msg (Str8 append "x-chess: " (if (Err err? e) (e msg) (io-display-to-str e)))))
      (tui-puzzles! st (%chosen st theme)))))

; KEY pressed with the choice shown: < and > another band, x the built-in
; puzzles, l the puzzle of the day, a theme's key its puzzles; any other
; closes the choice.
(def %choose-key!
  (fn (_ st key)
    (def c (if (str? key) (List find (fn (_ c) (str=? (first c) key)) %choices) ()))
    (match
      ((if (%is? key "<") #t (eq? key (lit left))) (%put! st %band (%max 0 (- (%get st %band) 1))))
      ((if (%is? key ">") #t (eq? key (lit right)))
        (%put! st %band (%min (- (List length %bands) 1) (+ (%get st %band) 1))))
      ((%is? key "x") (do (%put! st %choose #f) (tui-puzzles! st (puzzle-list-source (puzzle-set)))))
      ((%is? key "l") (do (%put! st %choose #f) (%ask-daily! st)))
      ((null? c) (%put! st %choose #f))
      (#t (do (%put! st %choose #f) (%start-chosen! st (List ref 1 c)))))))

; Fetch the puzzle of the day once the screen says so: the fetch takes
; seconds.
(def %ask-daily!
  (fn (_ st)
    (%put! st %msg "Asking lichess for the puzzle of the day...")
    (%put! st %pending %daily!)))

; Set the puzzle of the day, or say why there is none, or that it is
; solved.
(def %daily!
  (fn (_ st)
    (def d (%get st %daily))
    (guard (e (%put! st %msg (Str8 append "x-chess: " (if (Err err? e) (e msg) (io-display-to-str e)))))
      ((fn (_ got)
         (def z (first got))
         (if (record-solved? (%record-of st) (puzzle-id z))
           (%put! st %msg (Str8 append "You have solved today's puzzle, " (puzzle-id z) ", rated " (io-display-to-str (puzzle-rating z)) "."))
           (do (tui-puzzles! st (puzzle-list-source (list z)))
               (unless (str=? (rest got) "") (%put! st %msg (Str8 append "x-chess: " (rest got) ".  " (%get st %msg)))))))
       (daily-get (first d) (rest d))))))

; The work the screen waited for, done: whether there was any.
(def tui-work!
  (fn (_ st)
    ((fn (_ w) (if (null? w) #f (do (%put! st %pending ()) (w st) #t))) (%get st %pending))))

; The puzzles of :puzzles FILE [THEME] [LOW-HIGH], as WORDS: a source.
(def %file-puzzles
  (fn (_ words)
    (def more (rest words))
    (def range-word (List find (fn (_ w) (not (null? (puzzle-range w)))) more))
    (def theme (List find (fn (_ w) (null? (puzzle-range w))) more))
    (def range (if (null? range-word) (pair 0 0) (puzzle-range range-word)))
    (puzzle-file-source (first words) (if (null? theme) "" theme) (first range) (rest range))))

; Your move M in the puzzle, LEAD said before what follows when it is right.
(def %puzzle-move!
  (fn (_ st m lead)
    (def left (%pz st 2))
    (def p (game-pos (%get st %game)))
    (def verdict (if (null? left) (pair (lit free) ()) (puzzle-judge (%pz st 1) p m left)))
    (match
      ((eq? (first verdict) (lit free)) (%play-move! st m))
      ((eq? (first verdict) (lit wrong))
        (do (%pz! st 5 #t)
            (%put! st %sel -1) (%put! st %input "")
            (%put! st %msg (Str8 append "Not " (move-san p m) ": try again.  i shows a hint, m the move."))))
      ((eq? (first verdict) (lit solved)) (%solved! st m lead))
      (#t (%right! st m lead (rest verdict))))))

(def %solved!
  (fn (_ st m lead)
    (%play-move! st m)
    (%finished! st lead)))

(def %finished!
  (fn (_ st lead)
    (%pz! st 2 ())
    (unless (%pz st 5) (%pz! st 3 (+ 1 (%pz st 3))))
    (record-add! (%record-of st) (%pz st 1) (not (%pz st 5)))
    (%put! st %msg (Str8 append lead (if (%pz st 5) "Done" "Solved") " (" (%count-text st) "): z for the next puzzle."))))

; M was right: it is made, and the first of LEFT, the line on from it,
; is the reply.
(def %right!
  (fn (_ st m lead left)
    (%play-move! st m)
    (def g (%get st %game))
    (def reply (if (null? left) () (move-parse-uci (game-pos g) (first left))))
    (if (null? reply) (%finished! st lead)
      (do (def san (move-san (game-pos g) reply))
          (game-play! g reply)
          (%pz! st 2 (rest left))
          (%put! st %msg (Str8 append lead (%side-name (- 8 (pos-side (game-pos g)))) " replies " san ": your move."))))))

; i in a puzzle: the solution's next move shown.
(def %puzzle-hint!
  (fn (_ st)
    (def left (if (null? (%get st %puzzle)) () (%pz st 2)))
    (unless (null? left)
      (do (%pz! st 5 #t)
          (tui-hint! st (move-parse-uci (game-pos (%get st %game)) (first left)))))))

; m in a puzzle: the solution's next move made for you.
(def %puzzle-answer!
  (fn (_ st)
    (def left (if (null? (%get st %puzzle)) () (%pz st 2)))
    (unless (null? left)
      (do (def p (game-pos (%get st %game)))
          (def m (move-parse-uci p (first left)))
          (%pz! st 5 #t)
          (%puzzle-move! st m (Str8 append "The move is " (move-san p m) ".  "))))))

; --- keys --------------------------------------------------------------------------

; The characters a move is typed with, and once one is begun, the
; letters of a promotion in long algebraic (b7b8q), which are keys
; of their own on an empty line.
(def %move-chars "abcdefgh12345678NBRQKOo0x=+#-")
(def %promo-chars "qrn")

(def %move-char?
  (fn (_ st key)
    (if (str? key)
      (if (= (Str8 length key) 1)
        (if (Str8 includes? key %move-chars) #t
          (if (str=? (%get st %input) "") #f (Str8 includes? key %promo-chars)))
        #f)
      #f)))

(def %cursor-step!
  (fn (_ st df dr)
    ; the arrows move as the board is seen
    (def flip (if (= (%get st %view) 0) 1 -1))
    (def sq (%get st %cursor))
    (def f (+ (sq-file sq) (* df flip)))
    (def r (+ (sq-rank sq) (* dr flip)))
    (%put! st %cursor-on #t)
    (when (if (< -1 f) (if (< f 8) (if (< -1 r) (< r 8) #f) #f) #f)
      (%put! st %cursor (sq-make f r)))))

; Go back or forward through the game: the ply shown.
(def %review!
  (fn (_ st k)
    (def n (List length (game-moves (%get st %game))))
    (def at (if (< (%get st %review) 0) n (%get st %review)))
    (def to (%max 0 (%min n (+ at k))))
    (%put! st %review (if (= to n) -1 to))
    (%put! st %sel -1)
    (%put! st %msg (if (= to n) "" (Str8 append "Looking back at move " (io-display-to-str (int/ (+ to 1) 2))
                                     ": [ and ] step, End returns.")))))

(def %new-game!
  (fn (_ st fen)
    (%put! st %game (game-new fen))
    (%put! st %sel -1) (%put! st %review -1) (%put! st %hint 0) (%put! st %promo ())
    (%put! st %eval ()) (%put! st %puzzle ()) (%put! st %expect ())
    (tui-thinking-clear! st)
    (%put! st %msg "A new game.")))

(def %undo!
  (fn (_ st)
    (def g (%get st %game))
    (match
      ((null? (game-moves g)) (%put! st %msg "There is no move to take back."))
      (#t (do (game-undo! g)
              ; your move and the engine's reply go back together
              (when (if (tui-engine-to-move? st) (not (null? (game-moves g))) #f) (game-undo! g))
              (%put! st %sel -1) (%put! st %review -1) (%put! st %hint 0) (%put! st %expect ())
              (%put! st %msg "Taken back."))))))

; Play the other side: the engine takes the one you had.
(def %swap!
  (fn (_ st)
    (def h (%get st %human))
    (%put! st %human (match ((eq? h (lit white)) (lit black)) ((eq? h (lit black)) (lit white)) (#t (lit both))))
    (%put! st %view (if (eq? (%get st %human) (lit black)) 8 0))
    (%put! st %expect ())
    (%put! st %msg (Str8 append "You play " (match ((eq? (%get st %human) (lit both)) "both sides")
                                               ((eq? (%get st %human) (lit black)) "black") (#t "white")) "."))))

; Key KEY pressed: the state changed.  The loop asks afterwards whether
; the engine is to think (tui-engine-to-move?, tui-wants).
(def tui-key!
  (fn (_ st key)
    (match
      ((not (null? (%get st %command))) (%command-key! st key))
      ((%get st %choose) (%choose-key! st key))
      ((%get st %help) (%put! st %help #f))
      ((not (null? (%get st %promo))) (%promo-key! st key))
      ((if (pair? key) (eq? (first key) (lit mouse)) #f) (%mouse! st key))
      ((%move-char? st key) (%put! st %input (Str8 append (%get st %input) key)))
      ((eq? key (lit backspace))
        (%put! st %input (if (str=? (%get st %input) "") "" (Str8 slice 0 (- (Str8 length (%get st %input)) 1) (%get st %input)))))
      ((eq? key (lit enter))
        (if (str=? (%get st %input) "") (%pick! st (%get st %cursor)) (%move-typed! st (%get st %input))))
      ((str=? (if (str? key) key "") " ") (%pick! st (%get st %cursor)))
      ((eq? key (lit escape)) (do (%put! st %input "") (%put! st %sel -1) (%put! st %hint 0) (%put! st %msg "")))
      ((eq? key (lit up)) (%cursor-step! st 0 1))
      ((eq? key (lit down)) (%cursor-step! st 0 -1))
      ((eq? key (lit left)) (%cursor-step! st -1 0))
      ((eq? key (lit right)) (%cursor-step! st 1 0))
      ((eq? key (lit home)) (%review! st -10000))
      ((eq? key (lit end)) (%review! st 10000))
      ((%is? key "[") (%review! st -1))
      ((%is? key "]") (%review! st 1))
      ((if (%is? key "q") #t (eq? key (lit interrupt))) (%put! st %quit #t))
      ((%is? key "?") (%put! st %help #t))
      ((%is? key "u") (if (null? (%get st %puzzle)) (%undo! st) (%put! st %msg "In a puzzle: z goes on to the next one.")))
      ((%is? key "n") (%new-game! st ()))
      ((%is? key "v") (%put! st %view (- 8 (%get st %view))))
      ((%is? key "w") (%swap! st))
      ((%is? key "t") (%put! st %show-think (not (%get st %show-think))))
      ((%is? key "p") (%put! st %letters (not (%get st %letters))))
      ((%is? key "l") (%analyse! st))
      ((%is? key ":") (%put! st %command ""))
      ((%is? key "z") (%puzzle-key! st))
      ((%is? key "j") (%coach! st))
      ((%is? key "i") (%puzzle-hint! st))
      ((%is? key "m") (%puzzle-answer! st))
      (#t ()))))

(def %is? (fn (_ key s) (if (str? key) (str=? key s) #f)))

(def %analyse!
  (fn (_ st)
    (%put! st %analyse (not (%get st %analyse)))
    (%put! st %expect ())
    (tui-thinking-clear! st)
    (%put! st %msg (if (%get st %analyse) "Analysing: both sides are yours; l stops." "Analysis stopped."))))

; Whether the loop takes KEY itself, to run the engine: a hint (i) or a
; move now (m), but not in a puzzle, whose solution gives them.
(def tui-loop-key?
  (fn (_ st key) (if (null? (%get st %puzzle)) (if (%is? key "i") #t (%is? key "m")) #f)))

; --- the mouse ---------------------------------------------------------------------

; A press of the left button, KEY (mouse BUTTON COL ROW PRESS?), on a square.
(def %mouse!
  (fn (_ st key)
    (def b (List ref 1 key))
    (def col (- (List ref 2 key) 1))
    (def row (- (List ref 3 key) 1))
    (def sq (%square-at st row col))
    (when (if (= b 0) (if (List ref 4 key) (< -1 sq) #f) #f)
      (do (%put! st %cursor sq) (%pick! st sq)))))

; --- : commands --------------------------------------------------------------------

(def %command-key!
  (fn (_ st key)
    (def text (%get st %command))
    (match
      ((eq? key (lit enter)) (do (%put! st %command ()) (%run-command! st text)))
      ((eq? key (lit escape)) (%put! st %command ()))
      ((eq? key (lit backspace))
        (%put! st %command (if (str=? text "") () (Str8 slice 0 (- (Str8 length text) 1) text))))
      ((str? key) (%put! st %command (Str8 append text key)))
      (#t ()))))

(def %words (fn (_ line) (List reject (fn (_ w) (str=? w "")) (Str8 split " " line))))

(def %run-command!
  (fn (_ st line)
    (def words (%words line))
    (def cmd (if (null? words) "" (first words)))
    (def arg (if (null? words) "" (Str8 join " " (rest words))))
    (def n ((fn (_ v) (if (null? v) 0 v)) (parse-int arg)))
    (match
      ((str=? cmd "") ())
      ((str=? cmd "q") (%put! st %quit #t))
      ((str=? cmd "quit") (%put! st %quit #t))
      ((str=? cmd "new") (%new-game! st ()))
      ((str=? cmd "fen")
        (if (str=? arg "") (%put! st %msg (pos-fen (game-pos (%get st %game))))
          (guard (e (%put! st %msg (Str8 append "x-chess: " (e msg)))) (%new-game! st arg))))
      ((str=? cmd "time")
        (if (< 0 n) (do (%put! st %ms (* n 1000)) (%put! st %msg (Str8 append "The engine thinks " arg " s.")))
          (%put! st %msg "time takes a number of seconds")))
      ((str=? cmd "depth")
        (if (< 0 n) (do (%put! st %depth n) (%put! st %msg (Str8 append "The engine looks " arg " plies deep at most.")))
          (%put! st %msg "depth takes a number of plies")))
      ((str=? cmd "white") (do (%put! st %human (lit white)) (%put! st %view 0)))
      ((str=? cmd "black") (do (%put! st %human (lit black)) (%put! st %view 8)))
      ((str=? cmd "both") (%put! st %human (lit both)))
      ((str=? cmd "engine")
        (if (str=? arg "") (%put! st %msg (Str8 append "The engine is " (player-name (%get st %engine)) "."))
          (guard (e (%put! st %msg (Str8 append "x-chess: " (e msg))))
            (do (def pl (player-start arg))
                (player-quit! (%get st %engine))
                (%put! st %engine pl)
                (%put! st %msg (Str8 append "The engine is " (player-name pl) "."))))))
      ((str=? cmd "coach") (%coach! st))
      ((str=? cmd "board") (%board! st arg))
      ((str=? cmd "puzzle")
        (match ((str=? arg "") (%put! st %choose #t)) ((str=? arg "daily") (%ask-daily! st)) (#t (%start-chosen! st arg))))
      ((str=? cmd "puzzles")
        (if (str=? arg "") (%put! st %msg "puzzles takes a file, then a theme and a rating range if you like")
          (guard (e (%put! st %msg (Str8 append "x-chess: " (e msg))))
            (tui-puzzles! st (%file-puzzles (rest words))))))
      ((str=? cmd "save")
        (if (str=? arg "") (%put! st %msg "save takes a file name")
          (guard (e (%put! st %msg (Str8 append "x-chess: " (e msg))))
            (do (File write-all arg (game-pgn (%get st %game) (list (pair "Event" "x-chess game"))
                                      ((fn (_ r) (if (null? r) "*" (first r))) (game-result (%get st %game)))))
                (%put! st %msg (Str8 append "Saved to " arg "."))))))
      (#t (%put! st %msg (Str8 append "No such command: " cmd ".  ? lists them."))))))

; --- drawing -----------------------------------------------------------------------
;
; A theme is how the board is drawn: a row of %themes, (NAME FIGURES
; COLOURS), the colours the 256-colour palette's.  FIGURES says what a
; piece is drawn as: figures, each side the solid one in its own colour,
; or ascii, letters (white's in upper case) and no colour at all, the
; marks made with characters and reverse video.  COLOURS are the
; squares' backgrounds, light then dark, plain, of the last move, of the
; piece picked up, of the arrows' square and of a hint; a king in check's;
; white's and black's pieces; the dots on the squares a piece picked up
; can go to, and on the pieces it can take; and the bar's two sides.
; The pieces are bold in every theme.

(def %themes
  (list (list "wood" (lit figures) (list 180 137 186 143 114 71 117 74 116 73 203 231 16 65 160 253 238))
        (list "green" (lit figures) (list 108 65 186 143 179 136 110 67 116 73 167 231 16 22 160 253 238))
        (list "blue" (lit figures) (list 110 67 186 143 114 71 146 103 180 137 203 231 16 24 160 253 238))
        (list "grey" (lit figures) (list 248 242 186 143 114 71 117 74 116 73 203 231 16 236 160 253 238))
        (list "ascii" (lit ascii) (List repeat 17 ()))))

; The theme named NAME, or ().
(def tui-theme (fn (_ name) (List find (fn (_ t) (str=? (first t) name)) %themes)))
(def tui-theme-names (fn (_) (List map first %themes)))

(def %ascii? (fn (_ st) (eq? (List ref 1 (%get st %theme)) (lit ascii))))

; Colour I of the theme: 0 the light squares, as %themes lists them.
(def %colour (fn (_ st i) (List ref i (List ref 2 (%get st %theme)))))

; TEXT as the theme draws it: in ascii the separators and the typing
; cursor are ASCII too.
(def %plain
  (fn (_ st text)
    (if (%ascii? st) (Str8 replace "▏" "_" (Str8 replace "·" "|" text)) text)))

; :board NAME, or the next theme when NAME is empty.
(def %board!
  (fn (_ st name)
    (def names (tui-theme-names))
    (def next
      (fn (self l)
        (match ((null? l) (first names))
               ((str=? (first l) (first (%get st %theme))) (if (null? (rest l)) (first names) (first (rest l))))
               (#t (self (rest l))))))
    (def t (tui-theme (if (str=? name "") (next names) name)))
    (if (null? t)
      (%put! st %msg (Str8 append "No such board: " name ".  They are " (Str8 join ", " names) "."))
      (do (%put! st %theme t)
          (%put! st %msg (Str8 append "The " (first t) " board."))))))

; Square sizes: rows and columns a square takes, by the room there is.
(def %layout
  (fn (_ rows cols)
    (match ((if (< 28 rows) (< 85 cols) #f) (list 3 7))
           ((if (< 20 rows) (< 69 cols) #f) (list 2 5))
           (#t (list 1 3)))))

(def %layout-v (Vector make 2 1))

; The board's top row and left column on the screen.
(def %top 1)
(def %left 2)

; The square at screen ROW and COL, or -1.
(def %square-at
  (fn (_ st row col)
    (def h (Vector ref 0 %layout-v))
    (def w (Vector ref 1 %layout-v))
    (def r (if (< row %top) -1 (int/ (- row %top) h)))
    (def c (if (< col %left) -1 (int/ (- col %left) w)))
    (if (if (< -1 r) (if (< r 8) (if (< -1 c) (< c 8) #f) #f) #f) (%sq-of st r c) -1)))

; Board row R and column C, as seen, to a square.
(def %sq-of
  (fn (_ st r c) (if (= (%get st %view) 0) (sq-make c (- 7 r)) (sq-make (- 7 c) r))))

(def %figures-black (list "" "♟" "♞" "♝" "♜" "♛" "♚"))
(def %letters-list (list "" "P" "N" "B" "R" "Q" "K"))

; Piece PC as text: in ascii black's letters are in lower case; with
; letters asked for, both sides' in upper case and told apart by colour.
(def %piece-text
  (fn (_ st pc)
    (def k (piece-kind pc))
    (match ((%ascii? st) (if (= (piece-colour pc) 0) (List ref k %letters-list) (Str8 downcase (List ref k %letters-list))))
           ((%get st %letters) (List ref k %letters-list))
           (#t (List ref k %figures-black)))))

; Piece PC on a square drawn in SQ-STYLE: bold, in its side's colour,
; reversed with the square.
(def %piece-style
  (fn (_ st pc sq-style)
    (Style make (if (Style has? sq-style (lit reverse)) (list (lit bold) (lit reverse)) (list (lit bold)))
      (%colour st (if (= (piece-colour pc) 0) 11 12)) (Style bg sq-style))))

; The position shown: the game's, or the one looked back at.
(def %shown
  (fn (_ st)
    (def g (%get st %game))
    (def k (%get st %review))
    (if (< k 0) (pair (game-pos g) (if (null? (game-moves g)) 0 (List last (game-moves g))))
      (do (def p (%start-pos st))
          (def ms (List take k (game-moves g)))
          (List for-each (fn (_ m) (make! p m)) ms)
          (pair p (if (null? ms) 0 (List last ms)))))))

; What marks square SQ of P: check, sel, cur, hint, last or plain.
(def %mark
  (fn (_ st p sq last)
    (def pc (pos-piece p sq))
    (def hint (%get st %hint))
    (match
      ((< 0 (%promo-kind-at st sq)) (lit sel))
      ((if (= (piece-kind pc) KING) (if (= (piece-colour pc) (pos-side p)) (in-check? p) #f) #f) (lit check))
      ((= sq (%get st %sel)) (lit sel))
      ((if (%get st %cursor-on) (= sq (%get st %cursor)) #f) (lit cur))
      ((if (< 0 hint) (if (= sq (move-from hint)) #t (= sq (move-to hint))) #f) (lit hint))
      ((if (< 0 last) (if (= sq (move-from last)) #t (= sq (move-to last))) #f) (lit last))
      (#t (lit plain)))))

(def %mark-colours (list (pair (lit plain) 0) (pair (lit last) 2) (pair (lit sel) 4) (pair (lit cur) 6) (pair (lit hint) 8)))

; Square SQ of P as (FILL . STYLE): the character it is filled with and
; its style.  In ascii a dark square is dotted, the last move's squares
; dashed, a hint's waved, and the others marked reversed.
(def %square
  (fn (_ st p sq last)
    (def light (= (int% (+ (sq-file sq) (sq-rank sq)) 2) 1))
    (def mark (%mark st p sq last))
    (if (%ascii? st)
      (match ((eq? mark (lit last)) (pair "-" 0))
             ((eq? mark (lit hint)) (pair "~" 0))
             ((eq? mark (lit plain)) (if light (pair " " 0) (pair "." (Style make (list (lit dim)) () ()))))
             (#t (pair (if light " " ".") (Style make (list (lit reverse)) () ()))))
      (pair " " (Style make () ()
                  (if (eq? mark (lit check)) (%colour st 10)
                    (%colour st (+ (rest (Assoc find mark %mark-colours)) (if light 0 1)))))))))

(def %draw-board!
  (fn (_ st screen)
    (def h (Vector ref 0 %layout-v))
    (def w (Vector ref 1 %layout-v))
    (def shown (%shown st))
    (def p (first shown))
    (def last (rest shown))
    (def targets (if (if (< (%get st %sel) 0) #t (not (null? (%get st %promo)))) ()
                   (List map move-to (%moves-from st (%get st %sel)))))
    (List for-each
      (fn (_ i)
        (def r (int/ i 8))
        (def c (int% i 8))
        (def sq (%sq-of st r c))
        (def square (%square st p sq last))
        (def fill (Str8 repeat w (first square)))
        (def sq-style (rest square))
        (def y (+ %top (* r h)))
        (def x (+ %left (* c w)))
        (List for-each (fn (_ k) (Screen put screen (+ y k) x fill sq-style)) (List range 0 h))
        ; the promotion picker's pieces stand over what is there
        (def pc ((fn (_ k) (if (< 0 k) (+ (pos-side p) k) (pos-piece p sq))) (%promo-kind-at st sq)))
        (def cy (+ y (int/ h 2)))
        (def cx (+ x (int/ w 2)))
        ; the mark on a square the piece picked up can go to: I the colour
        (def dot
          (fn (_ col ascii i)
            (Screen put screen cy col (if (%ascii? st) ascii (if (= i 13) "•" "·"))
              (Style make (if (Style has? sq-style (lit reverse)) (list (lit reverse)) ()) (%colour st i) (Style bg sq-style)))))
        (match
          ((< 0 pc) (Screen put screen cy cx (%piece-text st pc) (%piece-style st pc sq-style)))
          ((List includes? sq targets) (dot cx "*" 13))
          (#t ()))
        (when (if (< 0 pc) (List includes? sq targets) #f) (dot (- cx 1) "x" 14)))
      (List range 0 64))
    ; ranks down the left, files along the bottom
    (List for-each
      (fn (_ r)
        (Screen put screen (+ %top (* r h) (int/ h 2)) 0
          (io-display-to-str (if (= (%get st %view) 0) (- 8 r) (+ r 1))) (Style make (list (lit dim)) () ())))
      (List range 0 8))
    (List for-each
      (fn (_ c)
        (Screen put screen (+ %top (* 8 h)) (+ %left (* c w) (int/ w 2))
          (List ref (if (= (%get st %view) 0) c (- 7 c)) (list "a" "b" "c" "d" "e" "f" "g" "h"))
          (Style make (list (lit dim)) () ())))
      (List range 0 8))))

; The bar beside the board: white's share from the bottom (as the board
; is seen), from the last score: an even game half and half.
(def %draw-bar!
  (fn (_ st screen)
    (def h (* 8 (Vector ref 0 %layout-v)))
    (def x (+ %left (* 8 (Vector ref 1 %layout-v)) 1))
    (def s (%get st %eval))
    (def share
      (match ((null? s) 500)
             ((mate-score? s) (if (< 0 s) 1000 0))
             (#t (%max 30 (%min 970 (+ 500 (int/ (* s 1000) (+ 800 (if (< s 0) (- 0 s) s)))))))))
    (def white-cells (int/ (+ (* share h) 500) 1000))
    (List for-each
      (fn (_ k)
        ; K counts from the bottom
        (def white (if (= (%get st %view) 0) (< k white-cells) (< (- h 1 k) white-cells)))
        (Screen put screen (- (+ %top h) 1 k) x
          (if (if (%ascii? st) (not white) #f) ":" " ")
          (Style make (if (if (%ascii? st) white #f) (list (lit reverse)) ()) () (%colour st (if white 15 16)))))
      (List range 0 h))))

; --- the panel ---------------------------------------------------------------------

(def %material (list 0 1 3 3 5 9 0))

; How many of each piece P has, by its code, in one walk of the squares.
(def %counts
  (fn (_ p)
    (def counts (Vector make 16 0))
    (List for-each
      (fn (_ i) ((fn (_ pc) (Vector set! pc (+ 1 (Vector ref pc counts)) counts))
                 (pos-piece p (+ (* (int/ i 8) 16) (int% i 8)))))
      (List range 0 64))
    counts))

; What SIDE has taken from the other in P since the game's start: the
; figures, and its material lead in pawns.
(def %taken
  (fn (_ st p side start)
    (def counts (%counts p))
    (def count (fn (_ colour kind) (Vector ref (+ colour kind) counts)))
    (def other (- 8 side))
    (def gone (List flat-map (fn (_ k) (List repeat (%max 0 (- (Vector ref (+ other k) start) (count other k))) k)) (list 5 4 3 2 1)))
    (def worth
      (fn (_ colour) (List fold (fn (_ n k) (+ n (* (List ref k %material) (count colour k)))) 0 (list 1 2 3 4 5))))
    (def lead (- (worth side) (worth other)))
    (Str8 append (Str8 join "" (List map (fn (_ k) (%piece-text st (+ other k))) gone))
      (if (< 0 lead) (Str8 append " +" (io-display-to-str lead)) ""))))

(def %strip!
  (fn (_ st screen row side p over start)
    (def g (%get st %game))
    (def to-move (if (= (pos-side p) side) (null? over) #f))
    (def who
      (if (if (eq? (%get st %human) (lit both)) #t
            (if (eq? (%get st %human) (lit white)) (= side 0) (= side 8)))
        "You" (player-name (%get st %engine))))
    (def x (Screen put screen row %left
             (match ((%ascii? st) (if (= side 0) " W " " B ")) ((= side 0) " ○ ") (#t " ● "))
             (Style make (if to-move (list (lit bold) (lit reverse)) ()) () ())))
    (def x2 (Screen put screen row (+ x 1) (Str8 append who " (" (%side-name side) ")")
              (Style make (if to-move (list (lit bold)) ()) () ())))
    (Screen put screen row (+ x2 2) (%taken st p side start) (Style make () 244 ()))))

(def %panel-x (fn (_ st) (+ %left (* 8 (Vector ref 1 %layout-v)) 4)))

(def %heading!
  (fn (_ screen row x text more)
    (def e (Screen put screen row x text (Style make (list (lit bold) (lit underline)) () ())))
    (Screen put screen row (+ e 2) more (Style make (list (lit dim)) () ()))))

; Whether cache C was made for a game from the start FEN of game G.  The
; FEN is the key: eq? does not tell one game's Vector from another's.
(def %cached-for? (fn (_ c g) (if (null? c) #f (str=? (first c) (game-start g)))))

; A copy of the game's start position: FEN is parsed once a game.
(def %start-pos
  (fn (_ st)
    (def g (%get st %game))
    (def c (%get st %start-cache))
    (if (%cached-for? c g) (pos-copy (rest c))
      ((fn (_ p) (%put! st %start-cache (pair (game-start g) (pos-copy p))) p) (pos-from-fen (game-start g))))))

; How many leading moves A and B share.
(def %shared
  (fn (self a b n)
    (match ((null? a) n)
           ((null? b) n)
           ((= (first a) (first b)) (self (rest a) (rest b) (+ n 1)))
           (#t n))))

; The SAN of each of the game's moves.  Naming a move asks for the legal
; moves, so the names drawn last are kept, and only those of moves made
; since are found.
(def %sans
  (fn (_ st)
    (def g (%get st %game))
    (def ms (game-moves g))
    (def c (%get st %san-cache))
    (def n (if (%cached-for? c g) (%shared (List ref 1 c) ms 0) 0))
    (if (if (%cached-for? c g) (if (= n (List length ms)) (= n (List length (List ref 1 c))) #f) #f)
      (List ref 2 c)
      (do (def p (%start-pos st))
          (List for-each (fn (_ m) (make! p m)) (List take n ms))
          (def sans (List append (if (= n 0) () (List take n (List ref 2 c))) (moves-san p (List drop n ms))))
          (%put! st %san-cache (list (game-start g) ms sans))
          sans))))

; The moves as rows (number white black), each move a pair of its SAN
; and its ply: "..." stands for white's move when the game began with
; black to move.
(def %move-rows
  (fn (_ st)
    (def p (%start-pos st))
    (def sans (%sans st))
    (def numbered (List zip sans (List range 1 (+ 1 (List length sans)))))
    (def padded (if (= (pos-side p) 8) (pair (pair "..." 0) numbered) numbered))
    (def go
      (fn (self ms n acc)
        (if (null? ms) (List reverse acc)
          (self (if (null? (rest ms)) () (rest (rest ms))) (+ n 1)
            (pair (list n (first ms) (if (null? (rest ms)) (pair "" 0) (first (rest ms)))) acc)))))
    (go padded (pos-full p) ())))

(def %panel-title
  (fn (_ st)
    (match
      ((not (null? (%get st %puzzle)))
        (Str8 append "Puzzle " (io-display-to-str (%pz st 4)) " · " (%count-text st)
          ((fn (_ r) (if (< 0 r) (Str8 append " · rated " (io-display-to-str r)) "")) (puzzle-rating (%pz st 1)))))
      ((%get st %analyse) (Str8 append "Analysing with " (player-name (%get st %engine))))
      (#t (Str8 append "Playing " (player-name (%get st %engine))
            " · " (io-display-to-str (int/ (%get st %ms) 1000)) " s a move"
            (if (%get st %coach) " · coached" ""))))))

(def %draw-panel!
  (fn (_ st screen)
    (def x (%panel-x st))
    (def rows (Screen rows screen))
    (def bottom (- rows 3))
    (Screen put screen 0 x (%plain st (%panel-title st)) (Style make (list (lit bold)) () ()))
    (def think-rows (if (%get st %show-think) (%min 6 (%max 2 (int/ (- bottom 2) 3))) 0))
    (when (%get st %show-think)
      (%heading! screen 2 x "Thinking" (%plain st (%get st %stats)))
      (List for-each
        (fn (_ i) (Screen put screen (+ 3 i) x (List ref i (%get st %thinking))
                    (Style make (if (= i 0) () (list (lit dim))) () ())))
        (List range 0 (%min think-rows (List length (%get st %thinking))))))
    (def mv-top (+ 3 think-rows (if (%get st %show-think) 1 0)))
    (%heading! screen mv-top x "Moves" "")
    (def lines (%move-rows st))
    (def room (%max 1 (- bottom mv-top)))
    (def shown (if (< room (List length lines)) (List drop (- (List length lines) room) lines) lines))
    (def ply-shown (if (< (%get st %review) 0) (List length (game-moves (%get st %game))) (%get st %review)))
    (List for-each
      (fn (_ i)
        (def l (List ref i shown))
        (def y (+ mv-top 1 i))
        (Screen put screen y x (Str8 pad-left 4 #\space (Str8 append (io-display-to-str (first l)) ".")) (Style make (list (lit dim)) () ()))
        (Screen put screen y (+ x 5) (first (List ref 1 l)) (%move-style (List ref 1 l) ply-shown))
        (Screen put screen y (+ x 14) (first (List ref 2 l)) (%move-style (List ref 2 l) ply-shown)))
      (List range 0 (List length shown)))))

; A move of the rows, (SAN . ply), marked when it is the ply shown.
(def %move-style
  (fn (_ m ply-shown)
    (Style make (if (if (< 0 (rest m)) (= (rest m) ply-shown) #f) (list (lit reverse)) ()) () ())))

(def %help-lines
  (list "Moves: type one (e4, Nf3, O-O, e7e8q) then Enter,"
        "or click a piece then its square, or the arrows and Enter."
        "Promote: b7b8q, or b8=Q in SAN; r b n for the others;"
        "clicked, pick one of the four shown down the file."
        ""
        "u      take back          n  new game"
        "v      turn the board     w  play the other side"
        "i      hint               m  the engine moves now"
        "l      analyse            t  show or hide thinking"
        "z      puzzles            j  the coach, on or off"
        "[ ]    back, forward      Home End  first, last"
        "p      letters or figures q  quit"
        ""
        ":fen FEN   :time S   :depth N   :engine CMD"
        ":save FILE   :white   :black   :both   :new"
        ":puzzle [THEME]   :puzzles FILE [THEME] [LOW-HIGH]"
        ":coach   :board [wood|green|blue|grey|ascii]"
        ""
        "Any key closes this."))

(def %draw-help! (fn (_ st screen) (%draw-box! st screen 62 %help-lines)))

; LINES in a box W wide in the middle of the screen.
(def %draw-box!
  (fn (_ st screen w lines)
    (def h (+ 2 (List length lines)))
    (def y (%max 0 (int/ (- (Screen rows screen) h) 2)))
    (def x (%max 0 (int/ (- (Screen cols screen) w) 2)))
    (def style (if (%ascii? st) (Style make (list (lit reverse)) () ()) (Style make () 16 230)))
    (List for-each (fn (_ k) (Screen fill screen (+ y k) x w style)) (List range 0 h))
    (List for-each (fn (_ i) (Screen put screen (+ y 1 i) (+ x 3) (%plain st (List ref i lines)) style))
      (List range 0 (List length lines)))))

(def %keys-line
  "type or click a move · u back · v turn · i hint · m move now · l analyse · z puzzles · ? keys · q quit")

(def %puzzle-keys-line
  "type or click a move · i hint · m show the move · z next puzzle · n leave · ? keys · q quit")

; Draw ST on SCREEN, every cell.
(def tui-draw!
  (fn (_ st screen)
    (def rows (Screen rows screen))
    (def cols (Screen cols screen))
    (Screen clear screen)
    (if (if (< rows 14) #t (< cols 52))
      (Screen put screen 0 0 "Too small: x-chess needs 52 by 14." (Style make () () ()))
      (do
        (def lay (%layout rows cols))
        (Vector set! 0 (first lay) %layout-v)
        (Vector set! 1 (List ref 1 lay) %layout-v)
        (def h (first lay))
        (def p (first (%shown st)))
        (%draw-board! st screen)
        (%draw-bar! st screen)
        (def over (game-result (%get st %game)))
        (def start (%counts (%start-pos st)))
        (%strip! st screen (+ %top (* 8 h) 1) (%get st %view) p over start)
        (%strip! st screen 0 (- 8 (%get st %view)) p over start)
        (%draw-panel! st screen)
        (Screen put screen (- rows 2) 0 (%get st %msg) (Style make (list (lit bold)) () ()))
        (Screen put screen (- rows 1) 0
          (%plain st
            (match ((not (null? (%get st %command))) (Str8 append ":" (%get st %command) "▏"))
                   ((not (str=? (%get st %input) "")) (Str8 append "Move: " (%get st %input) "▏   Enter plays it, Esc clears"))
                   ((null? (%get st %puzzle)) %keys-line)
                   (#t %puzzle-keys-line)))
          (Style make (if (if (null? (%get st %command)) (str=? (%get st %input) "") #f) (list (lit dim)) ()) () ()))
        (when (%get st %help) (%draw-help! st screen))
        (when (%get st %choose) (%draw-choice! st screen))))))

; How many of the library's puzzles have each theme in each band, read
; the first time the choice is shown: see puzzle-counts.
(def %library-counts
  (fn (_ st)
    (when (null? (%get st %counts-read))
      (%put! st %counts-read ((fn (_ lib) (pair (if (null? lib) () (puzzle-counts lib)) ())) (puzzle-library))))
    (first (%get st %counts-read))))

; The choice of puzzles z shows, in the band chosen: how many there are
; of each, and how many of each you have solved of those you finished.
(def %draw-choice!
  (fn (_ st screen)
    (def b (List ref (%get st %band) %bands))
    (def counts (%library-counts st))
    (def count
      (fn (_ c)
        ((fn (_ n) (Str8 pad-left 4 #\space (if (null? n) "" (io-display-to-str n))))
         (puzzle-count counts (List ref 1 c) (List ref 1 b) (List ref 2 b)))))
    (def score
      (fn (_ c)
        ((fn (_ s) (if (= 0 (rest s)) "" (Str8 append (io-display-to-str (first s)) " of " (io-display-to-str (rest s)) " solved")))
         (record-score (%record-of st) (List ref 1 c) (List ref 1 b) (List ref 2 b)))))
    (def lines
      (List append (list (Str8 append "Puzzles, " (first b)) "")
        (List map (fn (_ c) (Str8 append (first c) "   " (Str8 pad-right 20 #\space (List ref 2 c)) (count c) "   " (score c))) %choices)
        (list "x   x-chess's own, unrated" "l   lichess's puzzle of the day" "" "< >  another rating · any other key: back to the game")))
    (%draw-box! st screen 58 lines)))

(provide chess/tui tui-make tui-game tui-quit? tui-engine tui-depth tui-ms tui-analysing? tui-message!
  tui-engine-to-move? tui-report! tui-thinking-clear! tui-engine-played! tui-hint! tui-key! tui-loop-key?
  tui-draw! tui-puzzles! tui-work! tui-theme tui-theme-names)
