; # x-chess -- a chess engine on x-lang
;
; ## chess/window.x -- the board in a window or a browser tab
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The loop chess/app runs on a terminal, run over a window's events:
; FRONT is Sdl, or Web for a browser tab, which answer the same
; messages.  chess/tui keeps the game and says what a key does;
; chess/gui draws it.
;
; A piece is moved by clicking it and then its square, or by dragging it
; there; a move made by the engine, or by a click, slides.  Typing a
; move, and every key the terminal takes, works the same.  The buttons
; under the panel press keys.
;
; While the engine thinks the events are still taken, between its nodes:
; m has it move at once, q or closing the window stops it and leaves,
; and anything else waits until it has moved.  With nothing else to do
; the position is scored and, with s on, the engine's suggestions found;
; any key or click stops that, and is acted on.

(module chess/window)

(import x/sys/sdl)
(import x/sys/web)
(import x/sys/posix)
(import x/sys/gc)
(import x/sys/file)
(import x/core/doors int& int/ io-display-to-str)
(import chess/tables chess-cache-dir chess-dir-make!)
(import chess/game game-pos)
(import chess/board move-from move-to)
(import chess/player player-think player-quit!)
(import chess/search search-best search-excluding)
(import chess/tui tui-make tui-game tui-quit? tui-engine tui-depth tui-ms tui-analysing? tui-message!
  tui-engine-to-move? tui-report! tui-thinking-clear! tui-engine-played! tui-hint! tui-key! tui-loop-key?
  tui-work! tui-scored! tui-unscored tui-suggest-wanted tui-suggestion! tui-suggested! tui-view tui-sel)
(import chess/gui gui-make gui-draw! gui-at gui-canvas gui-width gui-height gui-scale)

; --- the window's state ------------------------------------------------------------
;
; A Vector, its slots named below.  The pointer's state is gui-draw!'s
; UI: 0 1 its X Y, 2 the square of a piece being dragged or -1, 3 the
; move sliding as (TO FROM PROGRESS), or ().

(def %front 0)
(def %win 1)
(def %st 2)
(def %gui 3)
(def %ui 4)
(def %queue 5)    ; what to act on, oldest first: a key, or (press SQ) or (release SQ)
(def %dirty 6)    ; whether the picture is out of date
(def %drawn 7)    ; the clock when it was last drawn, in milliseconds
(def %seen 8)     ; (PLY . MOVE) of the position last drawn
(def %dropped 9)  ; whether the last move was a piece let go, which does not slide
(def %slide 10)   ; the move sliding: (TO FROM START-MS), or ()
(def %view 11)    ; the view last drawn, what a point of the window is read from, or ()
(def %collected 12) ; the clock at the last collect
(def %polled 13)  ; the clock when the events were last taken during a search
(def %log 14)      ; the slow-moments log, a file descriptor, or ()
(def %doing 15)    ; what the window is busy with, for the log
(def %pumped 16)   ; the clock when the events were last taken
(def %checked 17)  ; the clock when the screen's density was last asked
(def %stale 18)    ; whether the game may have changed since the view was made: a
                   ; frame for the pointer alone draws the view it has
(def %slots 19)

(def %get (fn (_ w i) (Vector ref i w)))
(def %put! (fn (_ w i v) (Vector set! i v w)))

; The picture out of date because the game may have changed: the view is
; made again.  The pointer alone sets %dirty, and keeps the view.
(def %changed! (fn (_ w) (Vector set! %stale #t w) (Vector set! %dirty #t w)))

(def %ms (fn (_) ((fn (_ t) (+ (* 1000 (first t)) (int/ (rest t) 1000))) (Sys time-of-day))))

(def %slide-ms 170)
(def %frame-ms 16)

; --- keys ---------------------------------------------------------------------------

(def %named
  (list (pair 27 (lit escape)) (pair 13 (lit enter)) (pair 8 (lit backspace)) (pair 127 (lit backspace))
        (pair 1073741906 (lit up)) (pair 1073741905 (lit down)) (pair 1073741904 (lit left)) (pair 1073741903 (lit right))
        (pair 1073741898 (lit home)) (pair 1073741901 (lit end))))

(def %printable " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~")
(def %plain "1234567890-=[]\\;',./`")
(def %shifted "!@#$%^&*()_+{}|:\"<>?~")

(def %char (fn (_ code) (Str8 slice (- code 32) (- code 31) %printable)))

; The key a key-down event E is, as chess/tui takes keys: a string for a
; character, a name for the others, or () for none.  The keycode is the
; key's own character, so a shifted one is worked out from the
; modifiers: a letter its capital, a sign the one above it on the keys.
(def %key-of
  (fn (_ e)
    (def code (List ref 1 e))
    (def mod (List ref 2 e))
    (def shift (not (= 0 (int& mod 3))))
    (def ctrl (not (= 0 (int& mod 192))))
    (def cmd (not (= 0 (int& mod 3072))))
    (def named (List find (fn (_ p) (= (first p) code)) %named))
    (match
      ((not (null? named)) (rest named))
      ((if ctrl (= code 99) #f) (lit interrupt))
      ((if cmd (= code 113) #f) "q")
      (ctrl ())
      (cmd ())
      ((if (< 96 code) (< code 123) #f) (%char (if shift (- code 32) code)))
      ((if (< 31 code) (< code 127) #f)
        ((fn (_ s) ((fn (_ i) (if (if shift (not (null? i)) #f) (Str8 slice i (+ i 1) %shifted) s)) (Str8 index-of s %plain)))
         (%char code)))
      (#t ()))))

; --- events -------------------------------------------------------------------------

; Event E with the pointer's place in the picture's pixels at scale 1, as
; the gui lays it out.
(def %logical
  (fn (_ w e)
    (def k (gui-scale (%get w %gui)))
    (def at (match ((eq? (first e) (lit mouse-motion)) 1) ((eq? (first e) (lit mouse-down)) 2) ((eq? (first e) (lit mouse-up)) 2) (#t 0)))
    (if (if (= k 1) #t (= at 0)) e
      (let each ((i 0) (xs e))
        (if (null? xs) ()
          (pair (if (if (< (- at 1) i) (< i (+ at 2)) #f) (int/ (first xs) k) (first xs)) (each (+ i 1) (rest xs))))))))

(def %next-event
  (fn (_ w)
    ((fn (_ e) (if (null? e) () (%logical w e)))
     (if (eq? (%get w %front) Sdl) (Sdl poll (%get w %win)) (Web poll)))))

; --- the screen's density -----------------------------------------------------------

; Pixels a point on the window's screen, 1 or 2: drawn at 2, the picture is
; as sharp as such a screen shows.  An x without density answers 1.
(def %density
  (fn (_ w)
    ((fn (_ d) (match ((< d 2) 1) (#t 2)))
     (guard (e 1) ((%get w %front) density (%get w %win))))))

; The gui and the window's picture made at the screen's density when it
; is not the one drawn at: at the start, and when the window moves to
; another screen or a page connects.
(def %rescale!
  (fn (_ w)
    (def d (%density w))
    (%put! w %checked (%ms))
    (unless (= d (gui-scale (%get w %gui)))
      (do (def began (%ms))
          (%put! w %gui ())
          (Heap collect)
          (%put! w %gui (gui-make d))
          (%put! w %win ((%get w %front) picture! (%get w %win) (* d (gui-width)) (* d (gui-height))))
          (%changed! w)
          (%note! w (Str8 append "drawing at " (io-display-to-str d) " took " (io-display-to-str (- (%ms) began)) " ms"))))))

(def %queue! (fn (_ w item) (%put! w %queue (List append (%get w %queue) (list item)))))

(def %at (fn (_ w x y) (gui-at (%get w %gui) (%get w %view) x y)))

; Event E taken: a key or a press queued, the pointer moved.
(def %event!
  (fn (_ w e)
    (def kind (first e))
    (def ui (%get w %ui))
    ; drawn again when a piece is dragged or what is under the pointer
    ; changes: the ui's slot 4 keeps what was
    (def point!
      (fn (_ x y)
        (def hit (%at w x y))
        (unless (if (< -1 (Vector ref 2 ui)) #f (equal? hit (Vector ref 4 ui))) (%put! w %dirty #t))
        (Vector set! 4 hit ui)
        (Vector set! 0 x ui)
        (Vector set! 1 y ui)))
    (match
      ((eq? kind (lit quit)) (%queue! w "q"))
      ((eq? kind (lit close)) (%queue! w "q"))
      ((eq? kind (lit key-down)) ((fn (_ k) (unless (null? k) (%queue! w k))) (%key-of e)))
      ((eq? kind (lit mouse-motion)) (point! (List ref 1 e) (List ref 2 e)))
      ((if (eq? kind (lit mouse-down)) (eq? (List ref 1 e) (lit left)) #f)
        (do (point! (List ref 2 e) (List ref 3 e))
            ((fn (_ hit)
               (match ((null? hit) ())
                      ((eq? (first hit) (lit square)) (%queue! w (list (lit press) (List ref 1 hit))))
                      ((eq? (first hit) (lit key)) (%queue! w (List ref 1 hit)))
                      (#t ())))
             (%at w (List ref 2 e) (List ref 3 e)))))
      ((if (eq? kind (lit mouse-up)) (eq? (List ref 1 e) (lit left)) #f)
        (do (point! (List ref 2 e) (List ref 3 e))
            ((fn (_ hit) (%queue! w (list (lit release) (if (if (null? hit) #f (eq? (first hit) (lit square))) (List ref 1 hit) -1))))
             (%at w (List ref 2 e) (List ref 3 e)))))
      (#t ()))))

; --- the slow-moments log -----------------------------------------------------------

; A line in the log, when there is one.
(def %note!
  (fn (_ w text)
    ((fn (_ fd) (unless (null? fd) (guard (e ()) (Sys fd-write fd (Str8 append (io-display-to-str (%ms)) " " text "\n")))))
     (%get w %log))))

(def %doing! (fn (_ w label) (%put! w %doing label)))

; The log kept in the cache directory, opened afresh, or () when it cannot be.
(def %log-open
  (fn (_)
    (def dir (chess-cache-dir))
    (if (null? dir) ()
      (guard (e ())
        (do (chess-dir-make! dir)
            (File open (Str8 append dir "/window.log") (list (lit wronly) (lit creat) (lit trunc)) 420))))))

(def %pump-all!
  (fn (self w) ((fn (_ e) (unless (null? e) (do (%event! w e) (self w)))) (%next-event w))))

; Every event waiting taken; a long wait since the last time is noted
; with what the window was doing.
(def %pump!
  (fn (_ w)
    (def now (%ms))
    (def gap (- now (%get w %pumped)))
    (when (< 250 gap) (%note! w (Str8 append "input waited " (io-display-to-str gap) " ms during " (%get w %doing))))
    (%put! w %pumped now)
    (%pump-all! w)))

; --- drawing ------------------------------------------------------------------------

; The move to slide, when the position drawn has moved on one ply from the
; one before by a move not let go by the pointer.
(def %follow!
  (fn (_ w v now)
    (def ply (rest (Assoc find (lit ply) v)))
    (def last (rest (Assoc find (lit last) v)))
    (def seen (%get w %seen))
    (unless (if (= (first seen) ply) (= (rest seen) last) #f)
      (do (%put! w %slide (if (if (= ply (+ 1 (first seen))) (if (< 0 last) (not (%get w %dropped)) #f) #f)
                            (list (move-to last) (move-from last) now) ()))
          (%put! w %seen (pair ply last))
          (%put! w %dropped #f)))))

; Draw the window now: whether the picture is still moving.
(def %frame!
  (fn (_ w)
    (def now (%ms))
    (when (< 1000 (- now (%get w %checked))) (%rescale! w))
    (def v (if (%get w %stale) (tui-view (%get w %st)) (%get w %view)))
    (%put! w %stale #f)
    (def ui (%get w %ui))
    (%put! w %view v)
    (%follow! w v now)
    (def s (%get w %slide))
    (def t (if (null? s) 1000 (int/ (* 1000 (- now (List ref 2 s))) %slide-ms)))
    (when (< 999 t) (%put! w %slide ()))
    (Vector set! 3 (if (< 999 t) () (list (first s) (List ref 1 s) t)) ui)
    (def moving (gui-draw! (%get w %gui) v ui))
    (def shown (%ms))
    ((%get w %front) show! (%get w %win) (List ref 2 (gui-canvas (%get w %gui))))
    ((fn (_ took) (when (< 50 took) (%note! w (Str8 append "showing the frame took " (io-display-to-str took) " ms"))))
     (- (%ms) shown))
    (%put! w %drawn now)
    ; a slide's first frame draws the picture between moves again, which
    ; takes a while: the slide is timed from when that frame is shown
    (when (if (null? s) #f (= t 0)) (%put! w %slide (list (first s) (List ref 1 s) (%ms))))
    (%put! w %dirty #f)
    (when (< 250 (- now (%get w %collected))) (do (Heap collect) (%put! w %collected (%ms))))
    ; the bar still easing is drawn again
    (%put! w %dirty moving)))

(def %moving? (fn (_ w) (not (null? (%get w %slide)))))

; Drawn when out of date and a frame's time has passed since the last.
(def %refresh!
  (fn (_ w) (when (if (%get w %dirty) (< %frame-ms (- (%ms) (%get w %drawn))) #f) (%frame! w))))

; --- the engine ---------------------------------------------------------------------

; The events taken during a search, a few times a frame at most.
(def %take!
  (fn (_ w)
    ((fn (_ now) (when (< 5 (- now (%get w %polled))) (do (%put! w %polled now) (%pump! w) (%refresh! w)))) (%ms))))

(def %pull!
  (fn (_ w pred)
    ((fn (_ hit) (when hit (%put! w %queue (List reject pred (%get w %queue)))) hit)
     (not (null? (List find pred (%get w %queue)))))))

(def %is? (fn (_ s) (fn (_ k) (if (str? k) (str=? k s) #f))))

; The poll a search makes while it plays: m stops it, q, ctrl-c and
; closing the window stop it and leave, anything else waits.
(def %playing-poll
  (fn (_ w)
    (fn (_)
      (%take! w)
      (match
        ((%pull! w (%is? "m")) #t)
        ((%pull! w (fn (_ k) (if ((%is? "q") k) #t (eq? k (lit interrupt))))) (do (tui-key! (%get w %st) "q") #t))
        (#t #f)))))

; The poll while analysing or scoring: anything to act on ends it.
(def %waiting-poll (fn (_ w) (fn (_) (%take! w) (not (null? (%get w %queue))))))

(def %think
  (fn (_ w poll ms)
    (def st (%get w %st))
    (def g (tui-game st))
    (def p (game-pos g))
    (tui-thinking-clear! st)
    (%put! w %stale #t)
    (%frame! w)
    (def began (%ms))
    (def r (player-think (tui-engine st) g (if (= ms 0) 64 (tui-depth st)) ms poll
             (fn (_ r) (tui-report! st p r) (%put! w %stale #t) (%frame! w))))
    ((fn (_ took) (when (if (< 0 ms) (< (+ ms 1000) took) #f)
                    (%note! w (Str8 append "a " (io-display-to-str ms) " ms search took " (io-display-to-str took) " ms"))))
     (- (%ms) began))
    (Heap collect)
    r))

(def %min (fn (_ a b) (if (< a b) a b)))

(def %engine-move!
  (fn (_ w)
    (def st (%get w %st))
    (def r (%think w (%playing-poll w) (tui-ms st)))
    (match
      ((tui-quit? st) ())
      ((null? r) (tui-message! st "The engine has no move."))
      (#t (tui-engine-played! st (List ref 4 r) r)))
    (%changed! w)))

(def %hint!
  (fn (_ w)
    (def st (%get w %st))
    (def r (%think w (%playing-poll w) (%min 3000 (tui-ms st))))
    (unless (null? r) (tui-hint! st (List ref 4 r)))
    (%changed! w)))

(def %assess-ms 500)

(def %assess!
  (fn (_ w p)
    (def st (%get w %st))
    (search-best p 64 %assess-ms 0 (%waiting-poll w) (fn (_ r) (tui-scored! st p r) (%changed! w) (%refresh! w)))
    (%changed! w)
    (Heap collect)))

; Each suggestion in turn, as chess/app finds them.
(def %suggest!
  (fn (_ w wanted)
    (def st (%get w %st))
    (def p (first wanted))
    (def box (Vector of ()))
    (def poll (%waiting-poll w))
    (def round
      (fn (self k except)
        (Vector set! 0 () box)
        (search-excluding p except 64 (%min 2000 (tui-ms st)) 0 poll
          (fn (_ r) (Vector set! 0 r box) (tui-suggestion! st p k r) (%changed! w) (%refresh! w)))
        (Heap collect)
        (%changed! w)
        (match ((not (null? (%get w %queue))) ())
               ((null? (Vector ref 0 box)) (tui-suggested! st p))
               (#t ((fn (_ wa) (if (null? wa) (tui-suggested! st p) (self (+ k 1) (rest wa)))) (tui-suggest-wanted st))))))
    (round (List length (rest wanted)) (rest wanted))))

; --- acting -------------------------------------------------------------------------

(def %act!
  (fn (_ w item)
    (def st (%get w %st))
    (def ui (%get w %ui))
    (%changed! w)
    (match
      ((if (pair? item) (eq? (first item) (lit press)) #f)
        ((fn (_ sq)
           (tui-key! st (list (lit square) sq))
           (Vector set! 2 (if (= (tui-sel st) sq) sq -1) ui))
         (List ref 1 item)))
      ((if (pair? item) (eq? (first item) (lit release)) #f)
        ((fn (_ from to)
           (Vector set! 2 -1 ui)
           (when (if (< -1 from) (if (< -1 to) (not (= from to)) #f) #f)
             (do (%put! w %dropped #t) (tui-key! st (list (lit square) to)))))
         (Vector ref 2 ui) (List ref 1 item)))
      ((not (tui-loop-key? st item)) (tui-key! st item))
      ((str=? item "i") (%hint! w))
      ((str=? item "m") (%engine-move! w))
      (#t (tui-key! st item)))))

; Until there is something to act on or to draw: the picture kept up.
(def %wait!
  (fn (self w)
    (%pump! w)
    (%refresh! w)
    (when (if (null? (%get w %queue)) (if (%get w %dirty) #f (not (%moving? w))) #f)
      (do (Sys usleep 8000) (self w)))))

(def %idle!
  (fn (_ w)
    (def st (%get w %st))
    (def wanted (tui-suggest-wanted st))
    (def p (if (null? wanted) (tui-unscored st) ()))
    (match
      ((not (null? wanted)) (do (%doing! w "suggesting") (%suggest! w wanted)))
      ((not (null? p)) (do (%doing! w "scoring") (%assess! w p)))
      (#t (do (%doing! w "waiting") (%wait! w))))))

(def %loop
  (fn (self w)
    (def st (%get w %st))
    (%pump! w)
    (match
      ((tui-quit? st) ())
      ((not (null? (%get w %queue)))
        ((fn (_ item) (%put! w %queue (rest (%get w %queue))) (%doing! w "acting") (%act! w item) (self w)) (first (%get w %queue))))
      ((if (%get w %dirty) #t (%moving? w))
        (do (%doing! w "drawing")
            ((fn (_ left) (when (< 0 left) (Sys usleep (* 1000 left)))) (- %frame-ms (- (%ms) (%get w %drawn))))
            (%frame! w)
            (self w)))
      ((tui-work! st) (do (%changed! w) (self w)))
      ((tui-engine-to-move? st) (do (%doing! w "the engine's move") (%engine-move! w) (self w)))
      ((tui-analysing? st) (do (%doing! w "analysis") (%think w (%waiting-poll w) 0) (%changed! w) (%wait! w) (self w)))
      (#t (do (%idle! w) (self w))))))

; Play in a window drawn through FRONT, Sdl or Web, with OPTS as
; tui-make takes them: () when it was left, or what went wrong.
(def window-run
  (fn (_ front opts)
    (when (eq? front Sdl) (Sdl hint! "SDL_VIDEO_MAC_FULLSCREEN_SPACES" "0"))
    (def w (Vector make %slots ()))
    (%put! w %front front)
    (%put! w %st (tui-make opts))
    (%put! w %gui (gui-make 1))
    (%put! w %ui (Vector of -1 -1 -1 () ()))
    (%changed! w)
    (%put! w %drawn 0)
    (%put! w %seen (pair -1 0))
    (%put! w %dropped #f)
    (%put! w %view ())
    (%put! w %stale #t)
    (%put! w %collected 0)
    (%put! w %polled 0)
    (%put! w %log (%log-open))
    (%put! w %doing "starting")
    (%put! w %pumped (%ms))
    (%put! w %checked 0)
    (%put! w %win (front scaling! (front open "x-chess" (gui-width) (gui-height) 1) (lit fit)))
    ; a window opened from a terminal is left behind it, the keyboard with
    ; the terminal
    (when (eq? front Sdl) (Sdl raise! (%get w %win)))
    (%rescale! w)
    (def failed (guard (e e) (do (%loop w) ())))
    (front close (%get w %win))
    (unless (null? (%get w %log)) (guard (e ()) (File close (%get w %log))))
    (player-quit! (tui-engine (%get w %st)))
    failed))

(provide chess/window window-run)
