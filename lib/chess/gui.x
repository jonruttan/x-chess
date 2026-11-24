; # x-chess -- a chess engine on x-lang
;
; ## chess/gui.x -- the board drawn as a picture, for a window
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Draws what tui-view says on an RGBA canvas (gfx/canvas) of %width by
; %height: the board on the left with the bar beside it and a strip for
; each side, and on the right the panel of cards (the game, the score,
; the suggestions, the engine's thinking, the moves) over a row of
; buttons.  It also says what a point of the picture is: a square, a
; button's key, or nothing.  The window (chess/window) owns the loop.
;
; The pieces are this file's own outlines, drawn once a size: a profile
; a piece is symmetric about, mirrored, or the knight's whole outline,
; each with circles and bars added, then lines and dots of detail.  A
; piece is a shadow, its outline stroked, its body filled over the
; stroke's inner half, the detail, and a light from the left.
;
; Text is gfx/font's strokes, a string drawn once as a mask and kept,
; then stamped in its colour wherever it is wanted.
;
; Lengths in the piece outlines are hundredths of a square, x from the
; middle and y from the top; points handed to gfx/shape are in 256ths
; of a pixel.

(module chess/gui)

(import gfx/canvas)
(import gfx/shape)
(import gfx/font)
(import x/sys/gc)
(import x/core/doors io-display-to-str char->int str-byte-ref str-byte-len int/ int%)
(import chess/board PAWN KNIGHT BISHOP ROOK QUEEN KING pos-piece pos-side piece-kind piece-colour sq-make sq-file sq-rank
  move-from move-to pos-hash-lo pos-hash-hi)

; --- the layout ---------------------------------------------------------------------

(def %width 1180)
(def %height 760)
(def %sq 80)            ; a square's side
(def %bx 56)            ; the board's left and top
(def %by 60)
(def %bar-x 22)         ; the bar beside it
(def %bar-w 18)
(def %px 724)           ; the panel's left and width
(def %pw 436)
(def %button-w 103)
(def %button-h 30)
(def %button-gap 8)
(def %buttons-y 680)
(def %score-x 904)      ; the score card's bar: its left, top and width
(def %score-y 144)
(def %score-w 240)

(def %buttons
  (list (list "New" "n") (list "Take back" "u") (list "Turn" "v") (list "Hint" "i")
        (list "Move now" "m") (list "Suggest" "s") (list "Puzzles" "z") (list "Keys" "?")))

; --- colours ------------------------------------------------------------------------

(def %bg (list 22 24 29))
(def %card (list 34 38 46))
(def %card-hi (list 46 51 62))
(def %ink (list 234 234 228))
(def %dim (list 152 158 168))
(def %faint (list 104 110 120))
(def %blue (list 122 170 255))
(def %amber (list 242 196 108))
(def %green (list 120 198 132))
(def %light-sq (list 234 226 206))
(def %dark-sq (list 122 149 113))
(def %last-tint (list 246 214 92 105))
(def %sel-tint (list 246 214 92 175))
(def %mark (list 24 36 24 80))
(def %check-red (list 232 52 40))
(def %arrow (list 72 150 240 175))

(def %max (fn (_ a b) (if (< a b) b a)))
(def %min (fn (_ a b) (if (< a b) a b)))

; --- outlines ------------------------------------------------------------------------

; Hundredths of a square to 256ths of a pixel, at a square of S pixels.
; A piece takes 88 of the hundred, so that the squares' names in the
; corners stay clear, and stands 7 down.
(def %u (fn (_ v s) (int/ (* v (* s 2253)) 1000)))

(def %pt (fn (_ s ox oy x y) (pair (+ ox (%u x s)) (+ oy (%u (+ y 7) s)))))

; The points of PATH at a square of S, its x about OX and y from OY: the
; first of PATH is the start (X Y), each after it a line to (X Y) or a
; cubic (X1 Y1 X2 Y2 X Y).
(def %trace
  (fn (_ s ox oy path)
    (def at (fn (_ seg i) (%pt s ox oy (List ref i seg) (List ref (+ i 1) seg))))
    (def go
      (fn (self prev segs acc)
        (if (null? segs) (List reverse acc)
          ((fn (_ seg)
             (if (null? (rest (rest seg)))
               ((fn (_ p) (self p (rest segs) (pair p acc))) (at seg 0))
               ((fn (_ pts) (self (List last pts) (rest segs) (List append (List reverse (rest pts)) acc)))
                (Shape cubic prev (at seg 0) (at seg 2) (at seg 4)))))
           (first segs)))))
    ((fn (_ p0) (go p0 (rest path) (list p0))) (at (first path) 0))))

; The half outline PTS, from the middle at the top round to the middle at
; the bottom, and its mirror image back up the other side about OX.
(def %mirrored
  (fn (_ ox pts)
    (List append pts
      (List reverse (List map (fn (_ p) (pair (- (* 2 ox) (first p)) (rest p)))
                      (rest (List take (- (List length pts) 1) pts)))))))

; A circle about C of radius R, in 256ths: four cubics, clockwise as the
; picture is seen, the way the outlines run.
(def %circle
  (fn (_ c r)
    (def x (first c))
    (def y (rest c))
    (def k (int/ (* r 552) 1000))
    (List append
      (Shape cubic (pair x (- y r)) (pair (+ x k) (- y r)) (pair (+ x r) (- y k)) (pair (+ x r) y))
      (rest (Shape cubic (pair (+ x r) y) (pair (+ x r) (+ y k)) (pair (+ x k) (+ y r)) (pair x (+ y r))))
      (rest (Shape cubic (pair x (+ y r)) (pair (- x k) (+ y r)) (pair (- x r) (+ y k)) (pair (- x r) y)))
      (rest (Shape cubic (pair (- x r) y) (pair (- x r) (- y k)) (pair (- x k) (- y r)) (pair x (- y r)))))))

; A rectangle with round corners, in pixels: its outline in 256ths.
(def %rrect
  (fn (_ x y w h r)
    (def l (* x 256))
    (def t (* y 256))
    (def rr (* 256 (%min r (%min (int/ w 2) (int/ h 2)))))
    (def rt (* (+ x w) 256))
    (def b (* (+ y h) 256))
    (def k (int/ (* rr 552) 1000))
    (List append
      (list (pair (+ l rr) t))
      (Shape cubic (pair (- rt rr) t) (pair (+ (- rt rr) k) t) (pair rt (- (+ t rr) k)) (pair rt (+ t rr)))
      (Shape cubic (pair rt (- b rr)) (pair rt (+ (- b rr) k)) (pair (+ (- rt rr) k) b) (pair (- rt rr) b))
      (Shape cubic (pair (+ l rr) b) (pair (- (+ l rr) k) b) (pair l (+ (- b rr) k)) (pair l (- b rr)))
      (Shape cubic (pair l (+ t rr)) (pair l (- (+ t rr) k)) (pair (- (+ l rr) k) t) (pair (+ l rr) t)))))

(def %box! (fn (_ c x y w h r colour) (Shape fill! c (list (%rrect x y w h r)) colour)))

; A bar's fill W by H, its corners R round, drawn once: a frame copies as
; much of it as the bar shows.
(def %pill (fn (_ w h r) ((fn (_ c) (%box! c 0 0 w h r (list 236 236 230)) c) (Canvas make w h))))

; A rectangle drawn over what is there, by COLOUR's alpha: a tile of the
; colour, made once a size and kept in G's slot 10, blended.
(def %tint!
  (fn (_ g c x y w h colour)
    (def key (list w h colour))
    (def hit (List find (fn (_ t) (equal? (first t) key)) (Vector ref 10 g)))
    (def tile
      (if (not (null? hit)) (rest hit)
        ((fn (_ t) (Vector set! 10 (pair (pair key t) (Vector ref 10 g)) g) t) (Canvas fill! (Canvas make w h) 0 0 w h colour))))
    (Canvas blend! c x y tile 0 0 w h)))

; --- the pieces ----------------------------------------------------------------------

; Each piece: (HALF PATHS CIRCLES LINES DOTS).  HALF is a profile from the
; top middle to the bottom middle, mirrored; PATHS whole outlines; CIRCLES
; and DOTS (X Y R); LINES open paths of detail.  Every foot is one: two
; steps out from the body to a base.

(def %foot (list (list 26 80) (list 30 82 30 86 27 87) (list 31 88) (list 35 89 35 94 31 94) (list 0 94)))
(def %step (list (list -26 87) (list 26 87)))

(def %pawn
  (list (List append (list (list 0 19) (list 6 19 11 24 11 30) (list 11 35 8 39 5 41) (list 10 43) (list 13 44 13 48 10 49)
                           (list 7 49) (list 7 60 13 72 22 78))
          %foot)
        () () (list %step (list (list -7 49) (list 7 49))) ()))

(def %rook
  (list (List append (list (list 0 17) (list 5 17) (list 5 23) (list 12 23) (list 12 17) (list 23 17) (list 23 32) (list 18 36)
                           (list 18 70) (list 18 74 20 77 23 79))
          %foot)
        () () (list %step (list (list -23 32) (list 23 32)) (list (list -18 70) (list 18 70))) ()))

(def %bishop
  (list (List append (list (list 0 7) (list 3 7 5 9 5 12) (list 5 15 3 16 2 17) (list 11 22 17 32 16 42) (list 15 49 11 53 7 55)
                           (list 11 57) (list 14 58 14 62 10 63) (list 8 63) (list 9 70 14 75 22 78))
          %foot)
        () () (list %step (list (list 6 30) (list -3 41)) (list (list -7 55) (list 7 55)) (list (list -8 63) (list 8 63))) ()))

(def %queen
  (list (List append (list (list 0 19) (list 5 33) (list 12 21) (list 16 35) (list 25 25) (list 19 53) (list 23 56)
                           (list 25 57 25 61 22 62) (list 16 62) (list 17 70 19 75 23 79))
          %foot)
        () (list (list 0 16 5) (list 12 18 4) (list -12 18 4) (list 25 22 4) (list -25 22 4))
        (list %step (list (list -19 53) (list 19 53)) (list (list -16 62) (list 16 62))) ()))

(def %king
  (list (List append (list (list 0 30) (list 9 27 24 28 25 38) (list 26 46 21 51 18 54) (list 22 57) (list 24 58 24 61 21 62)
                           (list 16 62) (list 17 70 19 75 23 79))
          %foot)
        (list (list (list -3 5) (list 3 5) (list 3 12) (list 10 12) (list 10 18) (list 3 18) (list 3 31) (list -3 31) (list -3 18)
                    (list -10 18) (list -10 12) (list -3 12)))
        () (list %step (list (list -18 54) (list 18 54)) (list (list -16 62) (list 16 62))) ()))

(def %knight
  (list ()
        (list (list (list 2 9) (list 7 13 9 17 9 20) (list 21 23 29 35 29 50) (list 29 61 24 70 22 78)
                    (list 26 80) (list 30 82 30 86 27 87) (list 31 88) (list 35 89 35 94 31 94)
                    (list -31 94) (list -35 94 -35 89 -31 88) (list -27 87) (list -30 86 -30 82 -26 80) (list -19 78)
                    (list -19 68 -11 60 -4 54) (list -2 52 -6 50 -11 50) (list -19 50 -27 52 -31 47)
                    (list -35 43 -33 37 -28 35) (list -22 29 -13 21 -5 17) (list -3 13 -1 9 2 9)))
        () (list %step (list (list 7 24) (list 17 28 22 38 22 52))) (list (list -12 30 3) (list -27 41 2))))

(def %pieces (list () %pawn %knight %bishop %rook %queen %king))

; Body, outline and detail colours: white's, then black's.
(def %white-colours (list (list 248 244 234) (list 40 36 32) (list 40 36 32)))
(def %black-colours (list (list 46 46 52) (list 14 14 16) (list 132 132 140)))

; The outlines of piece KIND at a square of S, moved DX DY 256ths.
(def %outlines
  (fn (_ kind s dx dy)
    (def pc (List ref kind %pieces))
    (def ox (+ dx (* s 128)))
    (List append
      (if (null? (first pc)) () (list (%mirrored ox (%trace s ox dy (first pc)))))
      (List map (fn (_ path) (%trace s ox dy path)) (List ref 1 pc))
      (List map (fn (_ c) (%circle (%pt s ox dy (first c) (List ref 1 c)) (%u (List ref 2 c) s))) (List ref 2 pc)))))

; The light a piece is lit by: full on the left, darker to the right.
(def %shade
  (fn (_ s)
    (def cell (match ((< 63 s) 32) ((< 31 s) 16) (#t 8)))
    (def n (+ 2 (int/ s cell)))
    (def m (Canvas make n 1))
    (List for-each (fn (_ i) ((fn (_ v) (Canvas fill! m i 0 1 1 (list v v v))) (- 255 (int/ (* i 60) n)))) (List range 0 n))
    (pair m cell)))

; Piece PC as a picture S square.
(def %sprite
  (fn (_ pc s)
    (def kind (piece-kind pc))
    (def colours (if (= (piece-colour pc) 0) %white-colours %black-colours))
    (def spec (List ref kind %pieces))
    (def ox (* s 128))
    (def c (Canvas make s s))
    (def body (%outlines kind s 0 0))
    (def outline (%max 300 (int/ (* s 256 5) 100)))
    (def detail (%max 256 (int/ (* s 256 24) 1000)))
    (Shape fill! c (%outlines kind s (int/ (* s 256) 40) (int/ (* s 256) 28)) (list 0 0 0 60))
    (Shape strokes! c (List map (fn (_ o) (pair #t o)) body) outline (List ref 1 colours))
    (Shape fill! c body (first colours))
    (unless (null? (List ref 3 spec))
      (Shape strokes! c (List map (fn (_ l) (pair #f (%trace s ox 0 l))) (List ref 3 spec)) detail (List ref 2 colours)))
    (unless (null? (List ref 4 spec))
      (Shape fill! c (List map (fn (_ d) (%circle (%pt s ox 0 (first d) (List ref 1 d)) (%u (List ref 2 d) s))) (List ref 4 spec))
        (List ref 2 colours)))
    ((fn (_ sh) (Canvas light! c 0 0 s s (first sh) (rest sh))) (%shade s))
    c))

; Every piece at S: a Vector by piece code.
(def %sprites
  (fn (_ s)
    (def v (Vector make 16 ()))
    ; a piece leaves much behind it: x collects only when asked
    (List for-each (fn (_ colour) (List for-each (fn (_ k) (Vector set! (+ colour k) (%sprite (+ colour k) s) v) (Heap collect)) (List range 1 7)))
      (list 0 8))
    v))

; --- text ---------------------------------------------------------------------------

; A character's advance is 5 of the font's grid, its 4 and 1 of space, a
; capital 6 high: N characters of cap height H take 5H/6 each, counted
; in the 256ths the strokes are laid in and rounded up.
(def %span (fn (_ n h) (int/ (+ (* n 5 (int/ (* h 256) 6)) 255) 256)))

; The characters TEXT shows, a UTF-8 sequence one: (CODE ...), a code of
; a character the font has not as 0, but the middle dot and the caret
; kept as 183 and 9615.
(def %codes
  (fn (_ text)
    (def n (str-byte-len text))
    (def b (fn (_ i) (if (< i n) (char->int (str-byte-ref text i)) 0)))
    ((fn (self i acc)
       (match
         ((not (< i n)) (List reverse acc))
         ((< (b i) 128) (self (+ i 1) (pair (b i) acc)))
         ((< (b i) 192) (self (+ i 1) acc))
         ((if (= (b i) 194) (= (b (+ i 1)) 183) #f) (self (+ i 2) (pair 183 acc)))
         ((if (= (b i) 226) (if (= (b (+ i 1)) 150) (= (b (+ i 2)) 143) #f) #f) (self (+ i 3) (pair 9615 acc)))
         (#t (self (+ i 1) (pair 0 acc)))))
     0 ())))

(def %strokes-of
  (fn (_ code)
    (match ((= code 183) (list (list (pair 2 3))))
           ((= code 9615) (list (list (pair 0 -1) (pair 0 7))))
           ((< code 32) ())
           ((< 126 code) ())
           (#t (Font glyph code)))))

; TEXT as a mask: (CANVAS PAD WIDTH), its cap H high and its strokes W
; 256ths wide, the cap's top PAD pixels down and the first character PAD
; pixels in; WIDTH the advance of the whole.
(def %text-mask
  (fn (_ text h weight)
    (def codes (%codes text))
    (def u (int/ (* h 256) 6))
    (def w (%max 280 (int/ (* h 256 weight) 100)))
    (def pad (+ 2 (int/ w 256)))
    (def width (%span (List length codes) h))
    (def c (Canvas make (+ width (* 2 pad) 1) (+ (int/ (* h 4) 3) (* 2 pad) 1)))
    (def at (fn (_ i p) (pair (+ (* pad 256) (* i 5 u) (* (first p) u)) (+ (* pad 256) (* (- 6 (rest p)) u)))))
    (def lines
      ((fn (self i cs acc)
         (if (null? cs) acc
           (self (+ i 1) (rest cs)
             (List append (List map (fn (_ st) (pair #f (List map (fn (_ p) (at i p)) (if (null? (rest st)) (list (first st) (first st)) st))))
                            (%strokes-of (first cs)))
               acc))))
       0 codes ()))
    (unless (null? lines) (Shape strokes! c lines w (list 255 255 255)))
    (list c pad width)))

; The masks made, kept in buckets by a few of the key's bytes.
(def %bucket
  (fn (_ key)
    (def n (str-byte-len key))
    (def b (fn (_ i) (char->int (str-byte-ref key i))))
    (int% (+ (* n 31) (b (- n 1)) (* 7 (b (int/ n 2))) (* 3 (b (int/ n 3)))) 64)))

(def %texts 0)  ; the slot of the gui holding the buckets, and the count

(def %mask-of
  (fn (_ g text h weight)
    (def key (Str8 append (io-display-to-str h) "/" (io-display-to-str weight) "/" text))
    (def buckets (Vector ref 0 g))
    (def i (%bucket key))
    (def hit (List find (fn (_ e) (str=? (first e) key)) (Vector ref i buckets)))
    (if (not (null? hit)) (rest hit)
      (do (when (< 900 (Vector ref 1 g))
            (do (List for-each (fn (_ k) (Vector set! k () buckets)) (List range 0 64)) (Vector set! 1 0 g)))
          (def m (%text-mask text h weight))
          (Vector set! i (pair (pair key m) (Vector ref i buckets)) buckets)
          (Vector set! 1 (+ 1 (Vector ref 1 g)) g)
          m))))

; TEXT drawn on C with its cap's top left at X Y, H high, in COLOUR:
; the x after it.
(def %text!
  (fn (_ g c x y text h weight colour)
    (if (str=? text "") x
      ((fn (_ m)
         (def mc (first m))
         (Canvas stamp! c (- x (List ref 1 m)) (- y (List ref 1 m)) mc 0 0 (first mc) (List ref 1 mc) colour)
         (+ x (List ref 2 m)))
       (%mask-of g text h weight)))))

(def %text-w (fn (_ text h) (%span (List length (%codes text)) h)))

; TEXT cut to N characters, an ellipsis of three dots at the end when cut.
(def %clip
  (fn (_ text n)
    (if (< n (+ (List length (%codes text)) 1)) (if (< (str-byte-len text) n) text (Str8 append (Str8 slice 0 (- n 3) text) "..."))
      text)))

; --- the gui ------------------------------------------------------------------------
;
; A Vector: 0 the text buckets, 1 how many masks they hold, 2 the frame,
; 3 the pieces a square large, 4 the pieces small, 5 the board drawn for
; white below, 6 for black below, 7 the bar's share as shown, 8 the
; picture of what changes least (see %chrome) and 9 what it was drawn
; for, 10 the tints' tiles, 11 to 14 a square's marks: the dot of a move,
; the ring of a capture, the edge of the square a piece would drop on,
; and the glow of a king in check, 15 the picture between moves (see
; %still) and 16 what it was drawn for, 17 and 18 the bars' fills whole:
; beside the board, and in the score card.

(def gui-make
  (fn (_)
    (def g (Vector make 19 ()))
    (Vector set! 0 (Vector make 64 ()) g)
    (Vector set! 1 0 g)
    (Vector set! 2 (Canvas make %width %height) g)
    (Vector set! 3 (%sprites %sq) g)
    (Vector set! 4 (%sprites 26) g)
    (Vector set! 7 500 g)
    (Vector set! 8 (Canvas make %width %height) g)
    (Vector set! 9 (lit none) g)
    (Vector set! 15 (Canvas make %width %height) g)
    (Vector set! 16 (lit none) g)
    (Vector set! 17 (%pill %bar-w (* 8 %sq) 5) g)
    (Vector set! 18 (%pill %score-w 12 6) g)
    (def ctr (pair (* 128 %sq) (* 128 %sq)))
    (def r (fn (_ n) (int/ (* %sq 256 n) 100)))
    (def mark (fn (_ contours) (Shape fill! (Canvas make %sq %sq) contours (list 255 255 255))))
    (Vector set! 11 (mark (list (%circle ctr (r 15)))) g)
    (Vector set! 12 (mark (list (%circle ctr (r 48)) (List reverse (%circle ctr (r 39))))) g)
    (Vector set! 13 (mark (list (%rrect 0 0 %sq %sq 0) (List reverse (%rrect 4 4 (- %sq 8) (- %sq 8) 0)))) g)
    (def glow (Canvas make %sq %sq))
    (List for-each (fn (_ k) (Shape fill! glow (list (%circle ctr (r (List ref k (list 50 40 30 20)))))
                               (List append %check-red (list (List ref k (list 50 60 80 110))))))
      (List range 0 4))
    (Vector set! 14 glow g)
    (Heap collect)
    g))

(def gui-width (fn (_) %width))
(def gui-height (fn (_) %height))
(def gui-canvas (fn (_ g) (Vector ref 2 g)))
(def gui-square (fn (_) %sq))

(def %files (list "a" "b" "c" "d" "e" "f" "g" "h"))

; The square at board row R and column C as seen with VIEW at the bottom.
(def %sq-at (fn (_ view r c) (if (= view 0) (sq-make c (- 7 r)) (sq-make (- 7 c) r))))

; The board's left top pixel of square SQ, as (X . Y).
(def %sq-xy
  (fn (_ view sq)
    (def c (if (= view 0) (sq-file sq) (- 7 (sq-file sq))))
    (def r (if (= view 0) (- 7 (sq-rank sq)) (sq-rank sq)))
    (pair (+ %bx (* c %sq)) (+ %by (* r %sq)))))

(def %light? (fn (_ sq) (= 1 (int% (+ (sq-file sq) (sq-rank sq)) 2))))

; The squares and their names, drawn once for each side below.
(def %board
  (fn (_ g view)
    (def slot (if (= view 0) 5 6))
    (when (null? (Vector ref slot g))
      (do (def b (Canvas make (* 8 %sq) (* 8 %sq)))
          (List for-each
            (fn (_ i)
              (def r (int/ i 8))
              (def c (int% i 8))
              (def sq (%sq-at view r c))
              (def light (%light? sq))
              (def x (* c %sq))
              (def y (* r %sq))
              (Canvas fill! b x y %sq %sq (if light %light-sq %dark-sq))
              (def ink (if light %dark-sq %light-sq))
              (when (= c 0) (%text! g b (+ x 5) (+ y 5) (io-display-to-str (+ 1 (sq-rank sq))) 11 15 ink))
              (when (= r 7) (%text! g b (- (+ x %sq) 13) (- (+ y %sq) 16) (List ref (sq-file sq) %files) 11 15 ink)))
            (List range 0 64))
          (Vector set! slot b g)
          (Heap collect)))
    (Vector ref slot g)))

; --- what is where ------------------------------------------------------------------

(def %button-xy
  (fn (_ i) (pair (+ %px (* (int% i 4) (+ %button-w %button-gap))) (+ %buttons-y (* (int/ i 4) (+ %button-h 6))))))

(def %in?
  (fn (_ x y bx by w h) (if (< x bx) #f (if (< y by) #f (if (< x (+ bx w)) (< y (+ by h)) #f)))))

; What is at X Y of the picture: (square SQ), (key KEY) for a button, or ().
(def gui-at
  (fn (_ view x y)
    (def c (if (< x %bx) -1 (int/ (- x %bx) %sq)))
    (def r (if (< y %by) -1 (int/ (- y %by) %sq)))
    (match
      ((if (< -1 c) (if (< c 8) (if (< -1 r) (< r 8) #f) #f) #f) (list (lit square) (%sq-at view r c)))
      (#t ((fn (_ i) (if (null? i) () (list (lit key) (List ref 1 (List ref i %buttons)))))
           (List find (fn (_ i) ((fn (_ p) (%in? x y (first p) (rest p) %button-w %button-h)) (%button-xy i)))
             (List range 0 (List length %buttons))))))))

; --- drawing ------------------------------------------------------------------------

(def %view-of (fn (_ v k) (rest (Assoc find k v))))

(def %centre (fn (_ view sq) ((fn (_ p) (pair (* 256 (+ (first p) (int/ %sq 2))) (* 256 (+ (rest p) (int/ %sq 2))))) (%sq-xy view sq))))

; An arrow from square A's middle to B's, its head at B.
(def %arrow!
  (fn (_ c view a b colour)
    (def p (%centre view a))
    (def q (%centre view b))
    (def dx (- (first q) (first p)))
    (def dy (- (rest q) (rest p)))
    (def len (%max 1 (%isqrt (+ (* (int/ dx 16) (int/ dx 16)) (* (int/ dy 16) (int/ dy 16))))))
    ; unit vector in 1/1024
    (def ux (int/ (* dx 64) len))
    (def uy (int/ (* dy 64) len))
    ; PCT hundredths of a square, in 256ths of a pixel
    (def part (fn (_ pct) (int/ (* %sq 256 pct) 100)))
    ; the point D along the way from PT
    (def along (fn (_ pt d) (pair (+ (first pt) (int/ (* ux d) 1024)) (+ (rest pt) (int/ (* uy d) 1024)))))
    (def start (along p (part 22)))
    (def tip (along q (- 0 (part 12))))
    (def base (along tip (- 0 (part 36))))
    (def sw (part 10))
    (def hw (part 26))
    ; the point W across from PT, to the right of the way for S 1, the left for -1
    (def side (fn (_ pt w s) (pair (+ (first pt) (* s (int/ (* uy w) 1024))) (- (rest pt) (* s (int/ (* ux w) 1024))))))
    ; one outline: the shaft's right edge, the head, the shaft's left edge
    (Shape fill! c
      (list (list (side start sw -1) (side start sw 1) (side base sw 1) (side base hw 1)
                  tip
                  (side base hw -1) (side base sw -1)))
      colour)))

(def %isqrt
  (fn (_ n)
    ((fn (self x) (if (< x 2) x ((fn (_ y) (if (< y x) (self y) x)) (int/ (+ x (int/ n x)) 2))))
     (%max 1 n))))

; The board, its marks and its pieces.  UI is the window's: see gui-draw!.
(def %draw-board!
  (fn (_ g c v ui drop)
    (def view (%view-of v (lit view)))
    (def p (%view-of v (lit pos)))
    (def last (%view-of v (lit last)))
    (def sel (%view-of v (lit sel)))
    (def drag (Vector ref 2 ui))
    (def anim (Vector ref 3 ui))
    (def big (Vector ref 3 g))
    (def sq! (fn (_ sq colour) ((fn (_ xy) (%tint! g c (first xy) (rest xy) %sq %sq colour)) (%sq-xy view sq))))
    (def mark! (fn (_ sq slot colour) ((fn (_ xy) (Canvas stamp! c (first xy) (rest xy) (Vector ref slot g) 0 0 %sq %sq colour)) (%sq-xy view sq))))
    (when (< 0 last) (do (sq! (move-from last) %last-tint) (sq! (move-to last) %last-tint)))
    (when (< -1 sel) (sq! sel %sel-tint))
    (def check (%view-of v (lit check)))
    (when (< -1 check) ((fn (_ xy) (Canvas blend! c (first xy) (rest xy) (Vector ref 14 g) 0 0 %sq %sq)) (%sq-xy view check)))
    ; where the piece picked up can go: a dot, or a ring round a piece taken
    (List for-each (fn (_ sq) (mark! sq (if (< 0 (pos-piece p sq)) 12 11) %mark)) (%view-of v (lit targets)))
    ; the square a dragged piece would be let go on
    (when (< -1 drop) (mark! drop 13 (list 255 255 255 150)))
    ; the pieces at rest: one dragged is a shadow where it stood, one sliding
    ; is drawn over the still picture
    (List for-each
      (fn (_ i)
        (def sq (+ (* (int/ i 8) 16) (int% i 8)))
        (def pc (pos-piece p sq))
        (when (< 0 pc)
          ((fn (_ xy)
             (match
               ((= sq drag) (Canvas stamp! c (first xy) (rest xy) (Vector ref pc big) 0 0 %sq %sq (list 0 0 0 55)))
               ((if (null? anim) #f (= sq (first anim))) ())
               (#t (Canvas blend! c (first xy) (rest xy) (Vector ref pc big) 0 0 %sq %sq))))
           (%sq-xy view sq))))
      (List range 0 64))
    ; the hint, or the engine's first suggestion
    (def hint (%view-of v (lit hint)))
    (when (< 0 hint) (%arrow! c view (move-from hint) (move-to hint) %arrow))))

; What moves over the still picture: a piece sliding on its way, a piece
; dragged at the pointer.
(def %draw-moving!
  (fn (_ g c v ui)
    (def view (%view-of v (lit view)))
    (def p (%view-of v (lit pos)))
    (def drag (Vector ref 2 ui))
    (def anim (Vector ref 3 ui))
    (def big (Vector ref 3 g))
    (unless (null? anim)
      ((fn (_ pc)
         (when (< 0 pc)
           ((fn (_ a b t)
              (def e (- 1000 (int/ (* (- 1000 t) (* (- 1000 t) (- 1000 t))) 1000000)))
              (Canvas blend! c (+ (first a) (int/ (* (- (first b) (first a)) e) 1000)) (+ (rest a) (int/ (* (- (rest b) (rest a)) e) 1000))
                (Vector ref pc big) 0 0 %sq %sq))
            (%sq-xy view (List ref 1 anim)) (%sq-xy view (first anim)) (List ref 2 anim))))
       (pos-piece p (first anim))))
    (when (< -1 drag)
      ((fn (_ pc) (when (< 0 pc)
                    (Canvas blend! c (- (Vector ref 0 ui) (int/ %sq 2)) (- (Vector ref 1 ui) (int/ (* %sq 3) 5)) (Vector ref pc big) 0 0 %sq %sq)))
       (pos-piece p drag)))))

; The bar: white's share from the bottom as the board is seen, eased
; toward the share it should show.  Answers whether it is still moving.
(def %draw-bar!
  (fn (_ g c v)
    (def want (%view-of v (lit share)))
    (def was (Vector ref 7 g))
    ; a quarter of the way a frame, until a step would round to nothing
    (def now (if (< (%abs (- want was)) 8) want (+ was (int/ (- want was) 4))))
    (Vector set! 7 now g)
    (def h (* 8 %sq))
    (def wh (int/ (* now h) 1000))
    (def pill (Vector ref 17 g))
    (if (= (%view-of v (lit view)) 0)
      (when (< 0 wh) (Canvas blend! c %bar-x (- (+ %by h) wh) pill 0 (- h wh) %bar-w wh))
      (when (< 0 wh) (Canvas blend! c %bar-x %by pill 0 0 %bar-w wh)))
    (%tint! g c (- %bar-x 2) (- (+ %by (int/ h 2)) 1) (+ %bar-w 4) 2 (list 230 120 80 200))
    (not (= now want))))

(def %abs (fn (_ n) (if (< n 0) (- 0 n) n)))

; The score card's bar, at the share the bar beside the board shows.
(def %draw-score-bar!
  (fn (_ g c)
    (def share (Vector ref 7 g))
    (when (< 0 share) (Canvas blend! c %score-x %score-y (Vector ref 18 g) 0 0 (%max 12 (int/ (* %score-w share) 1000)) 12))
    (%tint! g c (+ %score-x (int/ %score-w 2)) (- %score-y 4) 2 20 (list 230 120 80 220))))

; A side's strip at Y: a disc of its colour, its name, what it has taken
; and its lead.  S is (WHO SIDE TO-MOVE? KINDS LEAD).
(def %draw-strip!
  (fn (_ g c y s)
    (def side (List ref 1 s))
    (def to-move (List ref 2 s))
    (def small (Vector ref 4 g))
    (when to-move (%box! c (- %bx 6) (- y 4) (+ 64 (%text-w (first s) 13)) 30 15 (list 52 74 60)))
    (Shape fill! c (list (%circle (pair (* 256 (+ %bx 12)) (* 256 (+ y 11))) (* 256 8))) (if (= side 0) (list 240 238 230) (list 20 20 24)))
    (Shape stroke! c (%circle (pair (* 256 (+ %bx 12)) (* 256 (+ y 11))) (* 256 8)) 300 (list 120 124 132) #t)
    (def x (%text! g c (+ %bx 30) (+ y 4) (first s) 13 15 (if to-move %ink %dim)))
    (def x2 (+ x 22))
    (def kinds (List ref 3 s))
    (List for-each
      (fn (_ i) (Canvas blend! c (+ x2 (* i 15)) (- y 2) (Vector ref (+ (- 8 side) (List ref i kinds)) small) 0 0 26 26))
      (List range 0 (List length kinds)))
    (when (< 0 (List ref 4 s))
      (%text! g c (+ x2 (* 15 (List length kinds)) 16) (+ y 6) (Str8 append "+" (io-display-to-str (List ref 4 s))) 10 15 %dim))))

; --- the panel ----------------------------------------------------------------------
;
; The cards stand where the view says: the suggestions only while they are
; on, the engine's only while its thinking is shown.  (SUGGEST ENGINE
; MOVES), the top of each, -1 for a card not shown.
(def %cards
  (fn (_ v)
    (def top (+ 96 104 12))
    (def s (if (%view-of v (lit suggesting)) top -1))
    (def e-top (if (< -1 s) (+ s 124) top))
    (def e (if (if (null? (%view-of v (lit thinking))) (str=? (%view-of v (lit stats)) "") #f) -1 e-top))
    (list s e (if (< -1 e) (+ e 122) e-top))))

(def %card-titles (list "SUGGESTED" "ENGINE" "MOVES"))
(def %card-heights (list 112 110 0))

; The picture of what changes least: the ground, the board and its frame,
; the bar's channel, the cards and their titles, the buttons.  It is drawn
; again only when what it shows changes: the side below, the cards shown,
; the button under the pointer, whether suggestions are on.
(def %chrome
  (fn (_ g v ui)
    (def view (%view-of v (lit view)))
    (def cards (%cards v))
    (def hover ((fn (_ h) (if (if (null? h) #f (eq? (first h) (lit key))) (List ref 1 h) "")) (gui-at view (Vector ref 0 ui) (Vector ref 1 ui))))
    (def key (list view cards hover (%view-of v (lit suggesting))))
    (def c (Vector ref 8 g))
    (unless (equal? key (Vector ref 9 g))
      (do (Canvas fill! c 0 0 %width %height %bg)
          (%box! c (- %bx 6) (- %by 6) (+ 12 (* 8 %sq)) (+ 12 (* 8 %sq)) 8 (list 12 13 16))
          (Canvas copy! c %bx %by (%board g view) 0 0 (* 8 %sq) (* 8 %sq))
          (%box! c %bar-x %by %bar-w (* 8 %sq) 5 (list 40 40 46))
          (%box! c %px 14 %pw 70 10 %card)
          (%box! c %px 96 %pw 104 10 %card)
          (%text! g c (+ %px 16) 110 "SCORE" 10 17 %dim)
          (%box! c %score-x %score-y %score-w 12 6 (list 20 20 24))
          (List for-each
            (fn (_ i)
              ((fn (_ y)
                 (when (< -1 y)
                   (do (%box! c %px y %pw (if (= i 2) (- %buttons-y y 12) (List ref i %card-heights)) 10 %card)
                       (%text! g c (+ %px 16) (+ y 14) (List ref i %card-titles) 10 17 %dim))))
               (List ref i cards)))
            (List range 0 3))
          (List for-each
            (fn (_ i)
              (def bt (List ref i %buttons))
              (def xy (%button-xy i))
              (def on (if (str=? (List ref 1 bt) "s") (%view-of v (lit suggesting)) #f))
              (def hot (str=? hover (List ref 1 bt)))
              (%box! c (first xy) (rest xy) %button-w %button-h 8 (match (on (list 58 86 136)) (hot (list 58 64 78)) (#t %card)))
              (%text! g c (+ (first xy) (int/ (- %button-w (%text-w (first bt) 10)) 2)) (+ (rest xy) 10) (first bt) 10 15 (if hot %ink %dim)))
            (List range 0 (List length %buttons)))
          (Vector set! 9 key g)
          (Heap collect)))
    c))

; NOTE beside a card's title TITLE at Y.
(def %note!
  (fn (_ g c y title note)
    (unless (str=? note "")
      ((fn (_ x) (%text! g c x (+ y 15) (%clip note (int/ (- (+ %px %pw) x 16) 8)) 9 14 %faint))
       (+ %px 28 (%text-w title 10))))))

(def %score-colour
  (fn (_ text) (match ((str=? text "") %dim) ((= (char->int (str-byte-ref text 0)) 45) (list 214 140 120)) (#t %ink))))

(def %draw-panel!
  (fn (_ g c v ui)
    (def cards (%cards v))
    ; the game
    (%text! g c (+ %px 16) 28 (%clip (%view-of v (lit title)) 46) 11 16 %ink)
    (def msg (%view-of v (lit msg)))
    (def over (%view-of v (lit over)))
    (def mover ((fn (_ s) (if (List ref 2 (first s)) (first s) (if (List ref 2 (List ref 1 s)) (List ref 1 s) ()))) (%view-of v (lit strips))))
    (match
      ((not (str=? msg "")) (%text! g c (+ %px 16) 54 (%clip msg 52) 10 14 %amber))
      ((not (null? over)) (%text! g c (+ %px 16) 54 (%clip over 52) 10 14 %amber))
      ((not (null? mover)) (%text! g c (+ %px 16) 54 (Str8 append (first mover) " to move") 10 14 %green))
      (#t ()))
    ; the score
    (%note! g c 96 "SCORE" (%view-of v (lit standing)))
    (def score (%view-of v (lit score)))
    (%text! g c (+ %px 16) 136 (if (str=? score "") "--" score) 26 16 (%score-colour score))
    (%text! g c (+ %px 16) 174 (%clip (%view-of v (lit detail)) 50) 9 14 %faint)
    ; the suggestions
    (def sy (first cards))
    (when (< -1 sy)
      (do (%note! g c sy "SUGGESTED" (%view-of v (lit suggest-status)))
          (def rows (%view-of v (lit suggested)))
          (List for-each
            (fn (_ i)
              (def row (List ref i rows))
              (def y (+ sy 36 (* i 24)))
              (when (= i 0) (%tint! g c (+ %px 8) (- y 6) (- %pw 16) 24 (list 255 255 255 14)))
              (%text! g c (+ %px 16) y (io-display-to-str (+ i 1)) 10 15 %faint)
              (%text! g c (+ %px 36) y (first row) 11 17 (if (= i 0) %blue %ink))
              (%text! g c (+ %px 112) y (List ref 1 row) 10 15 (%score-colour (List ref 1 row)))
              (%text! g c (+ %px 180) (+ y 1) (%clip (List ref 2 row) 28) 9 14 %dim))
            (List range 0 (%min 3 (List length rows))))))
    ; the engine's thinking
    (def ey (List ref 1 cards))
    (when (< -1 ey)
      (do (%note! g c ey "ENGINE" (%view-of v (lit stats)))
          (def thinking (%view-of v (lit thinking)))
          (List for-each
            (fn (_ i) (%text! g c (+ %px 16) (+ ey 36 (* i 18)) (%clip (Str8 trim (List ref i thinking)) 52) 9 14 (if (= i 0) %ink %faint)))
            (List range 0 (%min 4 (List length thinking))))))
    ; the moves
    (def my (List ref 2 cards))
    (def b (+ my 36))
    (def rows (%view-of v (lit rows)))
    (def ply (%view-of v (lit ply)))
    (def room (%max 1 (int/ (- %buttons-y 16 b) 22)))
    (def at (List find-index (fn (_ r) (if (= (rest (List ref 1 r)) ply) #t (= (rest (List ref 2 r)) ply))) rows))
    (def last-row (if (null? at) (- (List length rows) 1) at))
    (def from (%max 0 (%min (- (List length rows) room) (- last-row (- room 2)))))
    (def shown (List take (%min room (- (List length rows) from)) (List drop from rows)))
    (List for-each
      (fn (_ i)
        (def r (List ref i shown))
        (def y (+ b (* i 22)))
        (when (= 0 (int% (+ i from) 2)) (%tint! g c (+ %px 8) (- y 6) (- %pw 16) 22 (list 255 255 255 6)))
        (%text! g c (+ %px 18) y (Str8 append (io-display-to-str (first r)) ".") 10 15 %faint)
        (List for-each
          (fn (_ k)
            (def m (List ref k r))
            (def x (+ %px (if (= k 1) 76 186)))
            (when (if (< 0 (rest m)) (= (rest m) ply) #f) (%tint! g c (- x 8) (- y 5) 100 21 (list 70 98 150)))
            (%text! g c x y (first m) 10 15 %ink))
          (list 1 2)))
      (List range 0 (List length shown)))
    (when (null? rows) (%text! g c (+ %px 18) b "No moves yet." 10 14 %faint))))

; The promotion picker: the board dimmed, the pieces offered on tiles.
(def %draw-promo!
  (fn (_ g c v)
    (def choices (%view-of v (lit promo)))
    (unless (null? choices)
      (do (%tint! g c %bx %by (* 8 %sq) (* 8 %sq) (list 0 0 0 130))
          (def side (pos-side (%view-of v (lit pos))))
          (List for-each
            (fn (_ ch)
              ((fn (_ xy)
                 (%box! c (+ 3 (first xy)) (+ 3 (rest xy)) (- %sq 6) (- %sq 6) 12 (list 240 236 226))
                 (Canvas blend! c (first xy) (rest xy) (Vector ref (+ side (rest ch)) (Vector ref 3 g)) 0 0 %sq %sq))
               (%sq-xy (%view-of v (lit view)) (first ch))))
            choices)))))

; The keys box: what the window takes, its buttons and its pointer.
(def %keys
  (list "Moves: drag a piece to its square, or click it then the square;"
        "or type one (e4, Nf3, O-O, e7e8q) and press Enter."
        "Promote: click one of the four pieces shown down the file."
        ""
        "u    take back          n         new game"
        "v    turn the board     w         play the other side"
        "i    hint               m         the engine moves now"
        "s    suggested moves    t         show or hide thinking"
        "l    analyse            j         the coach, on or off"
        "z    puzzles            q         quit"
        "[ ]  back, forward      Home End  first, last"
        ""
        ":fen FEN   :time S   :depth N   :engine CMD"
        ":save FILE   :white   :black   :both   :new"
        ":puzzle [THEME]   :puzzles FILE [THEME] [LOW-HIGH]"
        ":coach   :suggest"
        ""
        "The buttons do the same as their keys.  Any key closes this."))

; A box of LINES in the middle of the picture.
(def %draw-box!
  (fn (_ g c lines)
    (def widest (List fold (fn (_ n l) (%max n (%text-w l 10))) 0 lines))
    (def w (+ widest 64))
    (def h (+ 48 (* 21 (List length lines))))
    (def x (int/ (- %width w) 2))
    (def y (%max 10 (int/ (- %height h) 2)))
    (%tint! g c 0 0 %width %height (list 0 0 0 120))
    (%box! c x y w h 14 (list 40 44 54))
    (List for-each (fn (_ i) (%text! g c (+ x 32) (+ y 26 (* i 21)) (List ref i lines) 10 14 %ink)) (List range 0 (List length lines)))))

; The game's end, over the board.
(def %draw-over!
  (fn (_ g c text)
    (def w (%max 360 (+ 60 (%text-w text 16))))
    (def x (+ %bx (int/ (- (* 8 %sq) w) 2)))
    (def y (+ %by (* 3 %sq) 10))
    (%box! c x y w 116 14 (list 28 31 38 235))
    (%text! g c (+ x (int/ (- w (%text-w text 16)) 2)) (+ y 30) text 16 17 %ink)
    ((fn (_ t) (%text! g c (+ x (int/ (- w (%text-w t 10)) 2)) (+ y 74) t 10 14 %dim)) "New game, or take a move back")))

; A move or a command being typed, at the board's foot.
(def %draw-input!
  (fn (_ g c v)
    (def cmd (%view-of v (lit command)))
    (def input (%view-of v (lit input)))
    (def text (match ((not (null? cmd)) (Str8 append ":" cmd "▏"))
                     ((not (str=? input "")) (Str8 append "Move: " input "▏   Enter plays it, Esc clears"))
                     (#t "")))
    (unless (str=? text "")
      ((fn (_ w)
         (%box! c (+ %bx (int/ (- (* 8 %sq) w) 2)) (- (+ %by (* 8 %sq)) 60) w 40 12 (list 28 31 38 240))
         (%text! g c (+ %bx (int/ (- (* 8 %sq) w) 2) 20) (- (+ %by (* 8 %sq)) 46) text 12 16 %ink))
       (+ 40 (%text-w text 12))))))

; The square under the pointer a dragged piece would be let go on, or -1.
(def %drop
  (fn (_ v ui)
    (def hit (if (< -1 (Vector ref 2 ui)) (gui-at (%view-of v (lit view)) (Vector ref 0 ui) (Vector ref 1 ui)) ()))
    (if (if (null? hit) #f (if (eq? (first hit) (lit square)) (List includes? (List ref 1 hit) (%view-of v (lit targets))) #f))
      (List ref 1 hit)
      -1)))

; The picture as it stands between moves: the chrome, the strips, the
; board with its marks and the pieces at rest, the panel.  It is drawn
; again only when what it shows changes; a frame copies it and draws
; what moves over it.  The key is the position's hash, the squares of a
; piece dragged, its drop and a piece sliding, and the rest of the view
; but the share the bar eases to.
(def %still
  (fn (_ g v ui)
    (def p (%view-of v (lit pos)))
    (def anim (Vector ref 3 ui))
    (def drop (%drop v ui))
    (def chrome (%chrome g v ui))
    (def key (list (Vector ref 9 g) (pos-hash-lo p) (pos-hash-hi p) (Vector ref 2 ui) drop (if (null? anim) -1 (first anim))
                   (List filter (fn (_ e) (not (List includes? (first e) (list (lit pos) (lit share))))) v)))
    (def c (Vector ref 15 g))
    (unless (equal? key (Vector ref 16 g))
      (do (Canvas copy! c 0 0 chrome 0 0 %width %height)
          (def strips (%view-of v (lit strips)))
          (%draw-strip! g c 16 (first strips))
          (%draw-strip! g c (+ %by (* 8 %sq) 14) (List ref 1 strips))
          (%draw-board! g c v ui drop)
          (%draw-panel! g c v ui)
          (Vector set! 16 key g)))
    c))

; Draw view V (tui-view's) on G's canvas.  UI is the window's Vector: 0 1
; the pointer's X Y, 2 the square of a piece being dragged or -1, 3 a move
; sliding, (TO FROM PROGRESS) with progress in thousandths, or ().
; Answers whether the picture is still moving, so that another frame is
; wanted.
(def gui-draw!
  (fn (_ g v ui)
    (def c (Vector ref 2 g))
    (Canvas copy! c 0 0 (%still g v ui) 0 0 %width %height)
    (%draw-moving! g c v ui)
    (def moving (%draw-bar! g c v))
    (%draw-score-bar! g c)
    (%draw-promo! g c v)
    (unless (null? (%view-of v (lit over))) (when (null? (%view-of v (lit promo))) (%draw-over! g c (%view-of v (lit over)))))
    (%draw-input! g c v)
    (when (%view-of v (lit help)) (%draw-box! g c %keys))
    (unless (null? (%view-of v (lit choice))) (%draw-box! g c (%view-of v (lit choice))))
    moving))

(provide chess/gui gui-make gui-draw! gui-at gui-canvas gui-width gui-height gui-square)
