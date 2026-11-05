; # x-chess -- a chess engine on x-lang
;
; ## chess/tables.x -- endgame tables
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Exact play in the endings of a lone king against king and queen, king
; and rook, or king and pawn.  Each table holds, for every position of
; the three men with either side to move, how many plies are left to
; mate with best play on both sides, or that there is no mate: the
; distance to mate, by retrograde analysis.
;
; A table is built from the mates back.  Every position where the lone
; king is mated is lost in 0 plies; a position where the stronger side
; has a move to a position lost in k plies is won in k + 1; a position
; of the lone king's whose every move goes to a won position, the last
; of them won in k plies, is lost in k + 1.  The positions are taken a
; ply at a time, in order, and each sends the positions one move before
; it to be looked at, so a position is settled once: the stronger
; side's at the first loss found below it, the lone king's when the
; count of its moves not yet known to lose comes to 0.
;
; With no pawn the board is folded by its eight symmetries, one image
; of a position kept: the stronger king in the triangle a1 d1 d4, so a
; table is 10 x 64 x 64 positions a side.  With a pawn it is folded left
; to right only, the pawn on files a to d, 24 x 64 x 64.  A position
; holds the plies to mate plus one, 0 for no mate.  A pawn that promotes
; is looked up in the queen's and the rook's tables, built first.
;
; Building takes minutes (see the README), so a table is kept in a file
; once built: X_CHESS_TABLES names the directory, else
; $XDG_CACHE_HOME/x-chess or ~/.cache/x-chess.  Only tables in memory
; are probed; tables-load! reads them, and builds them only where that
; is allowed.

(module chess/tables)

(import x/sys/gc)
(import x/sys/file)
(import x/core/doors int+ int- int* int< int= int& int>> obj-ref obj-set! str-make str->ptr ptr-ref ptr-set!)
(import chess/board pos-piece pos-side pos-castle pos-king pos-phase)

; --- squares 0 to 63, a1 to h8 -----------------------------------------------

(def %rank (fn (_ s) (int>> s 3)))
(def %file (fn (_ s) (int& s 7)))
(def %abs (fn (_ n) (match ((int< n 0) (int- 0 n)) (#t n))))

; The geometry building looks up rather than works out, made at the
; first build: for squares a and b, slot a * 64 + b + 1 of %near-v is #t
; when they are the same square or a king's step apart, of %line-v the
; line from a to b (1 to 4 a rank or file, 5 to 8 a diagonal, 0 none),
; of %dist-v the king's steps between them.  Slot s * 8 + d of %rays-v
; is the list of squares from s outward along line d; slot s + 1 of
; %steps-v the squares a king's step from s.
(def %near-v ())
(def %line-v ())
(def %dist-v ())
(def %rays-v ())
(def %steps-v ())

(def %line-code
  (fn (_ dr df)
    (match ((match ((int= dr 0) (int= df 0)) (#t #f)) 0)
           ((int= dr 0) (match ((int< 0 df) 1) (#t 2)))
           ((int= df 0) (match ((int< 0 dr) 3) (#t 4)))
           ((int= (%abs dr) (%abs df))
             (int+ 5 (int+ (match ((int< 0 dr) 0) (#t 2)) (match ((int< 0 df) 0) (#t 1)))))
           (#t 0))))

(def %geometry!
  (fn (_)
    (when (null? %steps-v)
      (def near (Vector make 4096 #f))
      (def line (Vector make 4096 0))
      (def dist (Vector make 4096 0))
      (def rays (Vector make 512 ()))
      (def steps (Vector make 64 ()))
      (def squares (List range 0 64))
      (def at (fn (_ a b) (int+ (int+ (int* a 64) b) 1)))
      (List for-each
        (fn (_ a)
          (List for-each
            (fn (_ b)
              (def dr (int- (%rank b) (%rank a)))
              (def df (int- (%file b) (%file a)))
              (def d (if (int< (%abs dr) (%abs df)) (%abs df) (%abs dr)))
              (obj-set! dist (at a b) d)
              (obj-set! near (at a b) (int< d 2))
              (obj-set! line (at a b) (%line-code dr df)))
            squares)
          (obj-set! steps (int+ a 1) (List filter (fn (_ b) (int= (obj-ref dist (at a b)) 1)) squares))
          (List for-each
            (fn (_ l)
              (obj-set! rays (int+ (int* a 8) l)
                (List sort (fn (_ b c) (int< (obj-ref dist (at a b)) (obj-ref dist (at a c))))
                  (List filter (fn (_ b) (int= (obj-ref line (at a b)) l)) squares))))
            (List range 1 9)))
        squares)
      (set! %near-v near)
      (set! %line-v line)
      (set! %dist-v dist)
      (set! %rays-v rays)
      (set! %steps-v steps))))

(def %steps-of (fn (_ s) (obj-ref %steps-v (int+ s 1))))

; Whether A and B are the same square or a king's step apart.
(def %near? (fn (_ a b) (obj-ref %near-v (int+ (int* a 64) (int+ b 1)))))

; Whether a queen (KIND 5) or rook (4) on FROM attacks TO, with the
; stronger king on BLOCK the one man that may stand between.
(def %slides?
  (fn (_ kind from to block)
    (def at (int+ (int* from 64) 1))
    (def d (obj-ref %line-v (int+ at to)))
    (match ((int= d 0) #f)
           ((match ((int= kind 4) (int< 4 d)) (#t #f)) #f)
           ((int= (obj-ref %line-v (int+ at block)) d)
             (int< (obj-ref %dist-v (int+ at to)) (obj-ref %dist-v (int+ at block))))
           (#t #t))))

; Whether the stronger side's piece of KIND on X attacks T.
(def %attacks?
  (fn (_ kind x t block)
    (match
      ((int= kind 1)
        (match ((int= (%rank t) (int+ (%rank x) 1)) (int= (%abs (int- (%file t) (%file x))) 1)) (#t #f)))
      (#t (%slides? kind x t block)))))

; --- folding the board -----------------------------------------------------------
;
; With no pawn a position is one of up to 8 the board's symmetries make
; of it, and only one of them is kept: the stronger king in the
; triangle a1 d1 d4, and when it stands on the diagonal a1 d4 the piece,
; or failing that the lone king, on or below the diagonal a1 h8.  With a
; pawn only the pawn on files a to d is kept.

; Square S under fold T: bit 1 turns the files round, bit 2 the ranks,
; bit 4 swaps files and ranks, last.
(def %fold
  (fn (_ t s)
    (def f (match ((int= (int& t 1) 0) (%file s)) (#t (int- 7 (%file s)))))
    (def r (match ((int= (int& t 2) 0) (%rank s)) (#t (int- 7 (%rank s)))))
    (match ((int= (int& t 4) 0) (int+ (int* r 8) f)) (#t (int+ (int* f 8) r)))))

; The triangle a1 b1 c1 d1 b2 c2 d2 c3 d3 d4.
(def %triangle (list 0 1 2 3 9 10 11 18 19 27))
(def %triangle-v (Vector from-list %triangle))

; Slot t * 64 + s + 1: S under fold T.
(def %folds
  (do (def v (Vector make 512 0))
      (List for-each
        (fn (_ t) (List for-each (fn (_ s) (obj-set! v (int+ (int* t 64) (int+ s 1)) (%fold t s))) (List range 0 64)))
        (List range 0 8))
      v))

(def %fold-of (fn (_ t s) (obj-ref %folds (int+ (int* t 64) (int+ s 1)))))

; Slot s + 1: the place of S in the triangle, or -1.
(def %corner
  (do (def v (Vector make 64 -1))
      (List for-each (fn (_ i) (obj-set! v (int+ (List ref i %triangle) 1) i)) (List range 0 10))
      v))

; Slot s + 1: the first fold that brings S into the triangle.
(def %fold-for
  (do (def v (Vector make 64 0))
      (List for-each
        (fn (_ s)
          (obj-set! v (int+ s 1)
            (List find (fn (_ t) (int< -1 (obj-ref %corner (int+ (%fold t s) 1)))) (List range 0 8))))
        (List range 0 64))
      v))

; Slot s + 1: 0 when S is below the diagonal a1 h8, 1 on it, 2 above.
(def %side-v
  (Vector from-list
    (List map (fn (_ s) (match ((int< (%rank s) (%file s)) 0) ((int= (%rank s) (%file s)) 1) (#t 2))) (List range 0 64))))

(def %diagonal-side (fn (_ s) (obj-ref %side-v (int+ s 1))))

; What %index adds up, by square: slot s + 1 of %fold-base is where the
; fold for a stronger king on s starts in %folds, of %king-part that
; king's share of the index; of %pawn-base and %pawn-part the same for a
; pawn on s, folded left to right when it stands on files e to h.
(def %fold-base
  (Vector from-list (List map (fn (_ s) (int+ (int* (obj-ref %fold-for (int+ s 1)) 64) 1)) (List range 0 64))))
(def %king-part
  (Vector from-list
    (List map (fn (_ s) (int* (obj-ref %corner (int+ (%fold-of (obj-ref %fold-for (int+ s 1)) s) 1)) 4096)) (List range 0 64))))
(def %pawn-base
  (Vector from-list (List map (fn (_ s) (match ((int< 3 (%file s)) 65) (#t 1))) (List range 0 64))))
(def %pawn-part
  (Vector from-list
    (List map (fn (_ s)
                ((fn (_ p) (int* (int+ (int* (int- (%rank p) 1) 4) (%file p)) 4096))
                 (%fold-of (match ((int< 3 (%file s)) 1) (#t 0)) s)))
      (List range 0 64))))

; --- a table -------------------------------------------------------------------
;
; A Vector: slot 1 the piece's kind (5 queen, 4 rook, 1 pawn), 2 the
; positions a side, 3 the stronger side's Vector of positions, 4 the
; lone king's, 5 while it is built the lone king's moves not yet known
; to lose, counted twice over.  A position's slot is its index plus 1.

; The index of the position with the kings on WK and BK and the piece on X.
(def %index
  (fn (_ tb wk x bk)
    (match ((int= (obj-ref tb 1) 1) (%pawn-index wk x bk (obj-ref %pawn-base (int+ x 1))))
           (#t (%folded-index wk x bk (obj-ref %fold-base (int+ wk 1)))))))

; With the fold's slots starting at B in %folds: on the diagonal the
; files and ranks are swapped (B 256 on or back) when the piece, or
; else the lone king, would be above it.
(def %folded-index
  (fn (_ wk x bk b)
    (match ((not (int= (%diagonal-side (obj-ref %folds (int+ b wk))) 1)) (%index-at wk x bk b))
           (#t (%diagonal-index wk x bk b (%diagonal-side (obj-ref %folds (int+ b x))))))))

(def %diagonal-index
  (fn (_ wk x bk b side)
    (match ((int= side 0) (%index-at wk x bk b))
           ((int= side 2) (%index-at wk x bk (%swapped b)))
           ((int= (%diagonal-side (obj-ref %folds (int+ b bk))) 2) (%index-at wk x bk (%swapped b)))
           (#t (%index-at wk x bk b)))))

(def %swapped (fn (_ b) (match ((int< b 257) (int+ b 256)) (#t (int- b 256)))))

(def %index-at
  (fn (_ wk x bk b)
    (int+ (obj-ref %king-part (int+ wk 1)) (int+ (int* (obj-ref %folds (int+ b x)) 64) (obj-ref %folds (int+ b bk))))))

(def %pawn-index
  (fn (_ wk x bk b)
    (int+ (obj-ref %pawn-part (int+ x 1)) (int+ (int* (obj-ref %folds (int+ b wk)) 64) (obj-ref %folds (int+ b bk))))))

; The squares of position I.
(def %wk-of
  (fn (_ tb i)
    (match ((int= (obj-ref tb 1) 1) (int& (int>> i 6) 63))
           (#t (obj-ref %triangle-v (int+ (int>> i 12) 1))))))

(def %x-of
  (fn (_ tb i)
    (match ((int= (obj-ref tb 1) 1) (int+ (int* (int+ (int>> i 14) 1) 8) (int& (int>> i 12) 3)))
           (#t (int& (int>> i 6) 63)))))

(def %bk-of (fn (_ i) (int& i 63)))

; How many positions the symmetries make of position I, halved: 2, or
; 1 when all three men stand on the diagonal a1 h8 and the swap of
; files and ranks leaves it as it is.  With a pawn, always 2.
(def %orbit
  (fn (_ tb i)
    (match ((int= (obj-ref tb 1) 1) 2)
           ((not (int= (%diagonal-side (%wk-of tb i)) 1)) 2)
           ((not (int= (%diagonal-side (%x-of tb i)) 1)) 2)
           ((not (int= (%diagonal-side (%bk-of i)) 1)) 2)
           (#t 1))))

(def %get (fn (_ v i) (obj-ref v (int+ i 1))))
(def %put! (fn (_ v i x) (obj-set! v (int+ i 1) x)))

(def %table-new
  (fn (_ kind)
    (def n (match ((int= kind 1) 98304) (#t 40960)))
    (def tb (Vector make 5 0))
    (obj-set! tb 1 kind)
    (obj-set! tb 2 n)
    (obj-set! tb 3 (Vector make n 0))
    (obj-set! tb 4 (Vector make n 0))
    (obj-set! tb 5 ())
    tb))

; --- building --------------------------------------------------------------------
;
; Positions waiting to be taken, by their plies: slot k + 1 holds those
; of k plies, each as its index times 2, plus 1 for the lone king's.
;
; A lone king's position starts with its legal moves counted, twice
; over.  Each time a position it moves to is won, the count drops by 2,
; times how many positions the symmetries make of that one over how
; many they make of this: the won position, kept once for all its
; images, stands for each of them, and the moves into them are found
; from it once each.  At 0 the position is lost.

(def %waiting (Vector make 256 ()))
(def %work (Vector make 1 0))

(def %wait! (fn (_ k e) (obj-set! %waiting (int+ k 1) (pair e (obj-ref %waiting (int+ k 1))))))

; Every 512 positions taken, the heap is collected: x collects only
; when asked.
(def %count!
  (fn (_)
    (obj-set! %work 1 (int+ (obj-ref %work 1) 1))
    (match ((int= (int& (obj-ref %work 1) 511) 0) (Heap collect)) (#t ()))))

; The stronger side's position I won in PLIES, unless already won sooner.
(def %win!
  (fn (_ tb i plies)
    (def v (%get (obj-ref tb 3) i))
    (match ((match ((int= v 0) #t) (#t (int< (int+ plies 1) v)))
             (do (%put! (obj-ref tb 3) i (int+ plies 1)) (%wait! plies (int* i 2))))
           (#t ()))))

; Whether the lone king may step to T.
(def %black-may?
  (fn (_ kind wk x t)
    (match ((%near? t wk) #f)
           ((int= t x) #t)
           (#t (not (%attacks? kind x t wk))))))

; The lone king's legal moves among TS, counted onto N.
(def %black-moves
  (fn (self kind wk x ts n)
    (match ((null? ts) n)
           ((%black-may? kind wk x (first ts)) (self kind wk x (rest ts) (int+ n 1)))
           (#t (self kind wk x (rest ts) n)))))

; The stronger side's positions one move before the lone king's
; position (WK X BK), lost in K plies, are won in K + 1.
(def %before-loss!
  (fn (_ tb wk x bk k)
    (def kind (obj-ref tb 1))
    (%king-back! tb kind wk x bk k (%steps-of wk))
    (match ((int= kind 1) (%pawn-before! tb wk x bk k))
           ((int= kind 5) (%lines-back! tb kind wk x bk k 1 9))
           (#t (%lines-back! tb kind wk x bk k 1 5)))))

(def %king-back!
  (fn (self tb kind wk x bk k us)
    (match ((null? us) ())
           ((int= (first us) x) (self tb kind wk x bk k (rest us)))
           ((%near? (first us) bk) (self tb kind wk x bk k (rest us)))
           ((%attacks? kind x bk (first us)) (self tb kind wk x bk k (rest us)))
           (#t (do (%win! tb (%index tb (first us) x bk) (int+ k 1)) (self tb kind wk x bk k (rest us)))))))

(def %lines-back!
  (fn (self tb kind wk x bk k l end)
    (match ((int= l end) ())
           (#t (do (%ray-back! tb kind wk bk k (obj-ref %rays-v (int+ (int* x 8) l)))
                   (self tb kind wk x bk k (int+ l 1) end))))))

; The squares the piece may have come from, out along a line to the
; edge or a king.
(def %ray-back!
  (fn (self tb kind wk bk k ss)
    (match ((null? ss) ())
           ((int= (first ss) wk) ())
           ((int= (first ss) bk) ())
           ((%attacks? kind (first ss) bk wk) (self tb kind wk bk k (rest ss)))
           (#t (do (%win! tb (%index tb wk (first ss) bk) (int+ k 1)) (self tb kind wk bk k (rest ss)))))))

; The pawn's squares before: a step back, or two from its first rank.
(def %pawn-before!
  (fn (_ tb wk x bk k)
    (def s (int- x 8))
    (match ((int< (%rank x) 2) ())
           ((int= s wk) ())
           ((int= s bk) ())
           (#t (do (match ((%attacks? 1 s bk wk) ()) (#t (%win! tb (%index tb wk s bk) (int+ k 1))))
                   (match ((int= (%rank x) 3) (%pawn-double! tb wk (int- x 16) bk k)) (#t ())))))))

(def %pawn-double!
  (fn (_ tb wk s bk k)
    (match ((int= s wk) ()) ((int= s bk) ()) ((%attacks? 1 s bk wk) ())
           (#t (%win! tb (%index tb wk s bk) (int+ k 1))))))

; The lone king's positions one move before the stronger side's
; position I (WK X BK), won in K plies: each move into it is known to
; lose, and a position with none left that does not is lost in K + 1.
(def %before-win!
  (fn (self tb i wk x k us)
    (match ((null? us) ())
           ((int= (first us) x) (self tb i wk x k (rest us)))
           ((%near? (first us) wk) (self tb i wk x k (rest us)))
           (#t (do (%move-lost! tb i (%index tb wk x (first us)) k) (self tb i wk x k (rest us)))))))

(def %move-lost!
  (fn (_ tb i y k)
    (match ((not (int= (%get (obj-ref tb 4) y) 0)) ())
           (#t (%count-down! tb y k (int- (%get (obj-ref tb 5) y) (%weight (%orbit tb i) (%orbit tb y))))))))

; Twice the won position's halved orbit over the losing one's.
(def %weight
  (fn (_ won lost)
    (match ((int= won lost) 2) ((int= won 2) 4) (#t 1))))

(def %count-down!
  (fn (_ tb y k n)
    (match ((int< 0 n) (%put! (obj-ref tb 5) y n))
           (#t (do (%put! (obj-ref tb 5) y 0) (%put! (obj-ref tb 4) y (int+ k 2)) (%wait! (int+ k 1) (int+ (int* y 2) 1)))))))

; Whether the kings on WK and BK and the piece on X are a legal
; position with the lone king to move, and the one of its images that
; is kept.
(def %kept?
  (fn (_ tb i wk x bk)
    (match ((int= wk x) #f)
           ((int= bk x) #f)
           ((%near? wk bk) #f)
           (#t (int= (%index tb wk x bk) i)))))

; Each lone king's position: its moves counted, and the mates, lost in
; 0 plies.
(def %count-moves!
  (fn (self tb i)
    (match
      ((int= i (obj-ref tb 2)) ())
      (#t (do (%count-at! tb i (%wk-of tb i) (%x-of tb i) (%bk-of i)) (%count!) (self tb (int+ i 1)))))))

(def %count-at!
  (fn (_ tb i wk x bk)
    (match
      ((not (%kept? tb i wk x bk)) ())
      (#t (%counted! tb i (%black-moves (obj-ref tb 1) wk x (%steps-of bk) 0) (%attacks? (obj-ref tb 1) x bk wk))))))

(def %counted!
  (fn (_ tb i n check)
    (match ((int< 0 n) (%put! (obj-ref tb 5) i (int* n 2)))
           (check (do (%put! (obj-ref tb 4) i 1) (%wait! 0 (int+ (int* i 2) 1))))
           (#t ()))))

; A pawn on the seventh with the stronger side to move may promote: to
; a queen or a rook, its plies looked up in their tables.
(def %promotions!
  (fn (self tb q r i)
    (match
      ((int= i (obj-ref tb 2)) ())
      (#t (do (%promote-at! tb q r i (%wk-of tb i) (%x-of tb i) (%bk-of i)) (%count!) (self tb q r (int+ i 1)))))))

(def %promote-at!
  (fn (_ tb q r i wk x bk)
    (def to (int+ x 8))
    (match
      ((not (int= (%rank x) 6)) ())
      ((int= wk x) ())
      ((int= bk x) ())
      ((%near? wk bk) ())
      ((%attacks? 1 x bk wk) ())
      ((int= to wk) ())
      ((int= to bk) ())
      (#t (do (%promote-to! tb i q wk to bk) (%promote-to! tb i r wk to bk))))))

(def %promote-to!
  (fn (_ tb i other wk to bk)
    ((fn (_ v) (match ((int= v 0) ()) (#t (%win! tb i v))))
     (%get (obj-ref other 4) (%index other wk to bk)))))

; Take the positions of K plies, then of K + 1, to the last.
(def %settle!
  (fn (self tb k)
    (match
      ((int< 254 k) tb)
      (#t (do (%settle-each! tb k (obj-ref %waiting (int+ k 1)))
              (obj-set! %waiting (int+ k 1) ())
              (self tb (int+ k 1)))))))

(def %settle-each!
  (fn (self tb k es)
    (match ((null? es) ())
           (#t (do (%settle-one! tb k (int>> (first es) 1) (int& (first es) 1)) (%count!) (self tb k (rest es)))))))

(def %settle-one!
  (fn (_ tb k i lone)
    (match
      ((int= lone 1) (%before-loss! tb (%wk-of tb i) (%x-of tb i) (%bk-of i) k))
      ((int= (%get (obj-ref tb 3) i) (int+ k 1))
        (%before-win! tb i (%wk-of tb i) (%x-of tb i) k (%steps-of (%bk-of i))))
      (#t ()))))

; Build the table for KIND; Q and R are the queen's and rook's, which a
; pawn's table needs.
(def %build
  (fn (_ kind q r)
    (%geometry!)
    (def tb (%table-new kind))
    (obj-set! tb 5 (Vector make (obj-ref tb 2) 0))
    (List for-each (fn (_ k) (obj-set! %waiting (int+ k 1) ())) (List range 0 256))
    (%count-moves! tb 0)
    (when (int= kind 1) (%promotions! tb q r 0))
    (%settle! tb 0)
    (obj-set! tb 5 ())
    (Heap collect)
    tb))

; --- files -----------------------------------------------------------------------

(def %env (fn (_ name) ((fn (_ v) (if (null? v) () (if (str=? v "") () v))) (Sys getenv name))))

; The directory tables are kept in, or () when there is none to name.
(def tables-dir
  (fn (_)
    (def own (%env "X_CHESS_TABLES"))
    (def cache (%env "XDG_CACHE_HOME"))
    (def home (%env "HOME"))
    (match ((not (null? own)) own)
           ((not (null? cache)) (Str8 append cache "/x-chess"))
           ((not (null? home)) (Str8 append home "/.cache/x-chess"))
           (#t ()))))

(def %path (fn (_ dir name) (Str8 append dir "/" name ".tb")))

; A table on disk is its two sides' bytes, the stronger side's first.
; Bytes and slots are copied a position at a time, the heap collected
; every 16384.
(def %copy
  (fn (self f i n)
    (match ((int= i n) ())
           (#t (do (f i) (match ((int= (int& i 16383) 0) (Heap collect)) (#t ())) (self f (int+ i 1) n))))))

; The table NAME of KIND read from DIR, or () when it is not there whole.
(def %read
  (fn (_ dir name kind)
    (def fd (if (null? dir) -1 (File open (%path dir name) (lit rdonly))))
    (if (int< fd 0) ()
      (do
        (def tb (%table-new kind))
        (def n (obj-ref tb 2))
        (def buf (str-make (int* n 2)))
        (def got (File read fd buf (int* n 2)))
        (File close fd)
        (if (int= got (int* n 2))
          (do
            (def p (str->ptr buf))
            (def w (obj-ref tb 3))
            (def b (obj-ref tb 4))
            (%copy (fn (_ i) (obj-set! w (int+ i 1) (int& (ptr-ref p i 1) 255))
                             (obj-set! b (int+ i 1) (int& (ptr-ref p (int+ i n) 1) 255)))
              0 n)
            tb)
          ())))))

; Keep TB in DIR as NAME; a directory that cannot be made or written is
; let be: the table is built again next time.
(def %write!
  (fn (_ dir name tb)
    (unless (null? dir)
      (guard (e ())
        (do
          (def n (obj-ref tb 2))
          (def buf (str-make (int* n 2)))
          (def p (str->ptr buf))
          (def w (obj-ref tb 3))
          (def b (obj-ref tb 4))
          (%copy (fn (_ i) (ptr-set! p i (obj-ref w (int+ i 1)) 1) (ptr-set! p (int+ i n) (obj-ref b (int+ i 1)) 1)) 0 n)
          (guard (e ()) (File mkdir (Str8 append (Sys getenv "HOME") "/.cache")))
          (guard (e ()) (File mkdir dir))
          (def fd (File open (%path dir name) (list (lit wronly) (lit creat) (lit trunc))))
          (when (int< -1 fd)
            (File write fd buf (int* n 2))
            (File close fd)))))))

(def %kqk ())
(def %krk ())
(def %kpk ())

; Whether the tables may be built when they are wanted and not on disk.
; Building takes minutes, so it is for a game at the terminal, which
; asks for it, and not for a UCI search with a clock running.
(def %may-build #f)
(def tables-allow-build! (fn (_ flag) (set! %may-build flag) flag))

; Whether the tables have been looked for: they are read once at most.
(def %looked #f)

; The table NAME of KIND: read from DIR, or built and kept there when
; building is allowed; () when neither.
(def %table
  (fn (_ dir name kind q r)
    ((fn (_ tb)
       (match ((not (null? tb)) tb)
              ((not %may-build) ())
              ((match ((int= kind 1) (null? q)) (#t #f)) ())
              (#t ((fn (_ tb) (%write! dir name tb) tb) (%build kind q r)))))
     (%read dir name kind))))

; Read the three tables, or build those not on disk when that is
; allowed, once; answers whether all three are in memory.  Building
; says so on standard error first: it takes minutes.
(def tables-load!
  (fn (_)
    (unless %looked
      (set! %looked #t)
      (def dir (tables-dir))
      (when (if %may-build (null? (%read-size dir)) #f)
        (Sys fd-write 2 "x-chess: building the endgame tables, once; this takes a few minutes\n"))
      (set! %kqk (%table dir "kqk" 5 () ()))
      (set! %krk (%table dir "krk" 4 () ()))
      (set! %kpk (%table dir "kpk" 1 %kqk %krk)))
    (tables-loaded?)))

; Whether DIR holds all three tables' files, or () when it does not.
(def %read-size
  (fn (_ dir)
    (match ((null? dir) ())
           ((List all? (fn (_ name) (File exists? (%path dir name))) (list "kqk" "krk" "kpk")) #t)
           (#t ()))))

; Build the three tables afresh into DIR, or keep them in memory alone
; when DIR is (); answers each one's microseconds, (kqk krk kpk).
(def tables-build!
  (fn (_ dir)
    (set! %looked #t)
    (def time (fn (_ thunk) ((fn (_ t0) (thunk) (int- (Sys clock) t0)) (Sys clock))))
    (def a (time (fn (_) (set! %kqk (%build 5 () ())) (%write! dir "kqk" %kqk))))
    (def b (time (fn (_) (set! %krk (%build 4 () ())) (%write! dir "krk" %krk))))
    (def c (time (fn (_) (set! %kpk (%build 1 %kqk %krk)) (%write! dir "kpk" %kpk))))
    (list a b c)))

(def tables-loaded? (fn (_) (not (null? %kpk))))

; The longest win in each table, in plies with the stronger side to
; move, and how many of its positions are won: ((plies won) ...) for
; KQK, KRK and KPK.
(def tables-longest
  (fn (_)
    (def scan
      (fn (_ tb)
        (def buf (obj-ref tb 3))
        (def go
          (fn (self i most won)
            (match ((int= i (obj-ref tb 2)) (list (int- most 1) won))
                   (#t (%longest-at self i most won (%get buf i))))))
        (go 0 0 0)))
    (List map scan (list %kqk %krk %kpk))))

(def %longest-at
  (fn (_ go i most won v)
    (match ((int= v 0) (go (int+ i 1) most won))
           ((int< most v) (go (int+ i 1) v (int+ won 1)))
           (#t (go (int+ i 1) most (int+ won 1))))))

; --- probing ---------------------------------------------------------------------

; P's men other than the kings, as a list of (piece . square), or many
; past one.
(def %men
  (fn (self p sq found)
    (match ((int< 127 sq) found)
           ((int= (int& sq 8) 8) (self p (int+ sq 8) found))
           (#t (%man p sq (pos-piece p sq) found)))))

(def %man
  (fn (_ p sq pc found)
    (match ((int= pc 0) (%men p (int+ sq 1) found))
           ((int= (int& pc 7) 6) (%men p (int+ sq 1) found))
           ((null? found) (%men p (int+ sq 1) (list (pair pc sq))))
           (#t (lit many)))))

; How many men other than the kings P has, counted to 3.
(def tables-men
  (fn (_ p)
    (def go
      (fn (self sq n)
        (match ((int< 2 n) n)
               ((int< 127 sq) n)
               ((int= (int& sq 8) 8) (self (int+ sq 8) n))
               ((int= (int& (pos-piece p sq) 7) 0) (self (int+ sq 1) n))
               ((int= (int& (pos-piece p sq) 7) 6) (self (int+ sq 1) n))
               (#t (self (int+ sq 1) (int+ n 1))))))
    (go 0 0)))

; P's distance to mate from the side to move's view, when the tables
; know it: N + 1 for a win in N plies, -(N + 1) for a loss in N, 0 for
; a draw.  () when P is not one they hold or they are not in memory.
; A lone minor piece, or kings alone, is a draw without a table.
(def table-probe
  (fn (_ p)
    (match ((int< 4 (pos-phase p)) ())
           ((not (int= (pos-castle p) 0)) ())
           (#t (%probe-men p (%men p 0 ()))))))

(def %probe-men
  (fn (_ p found)
    (match ((eq? found (lit many)) ())
           ((null? found) 0)
           (#t (%probe-one p (first (first found)) (rest (first found)))))))

(def %probe-one
  (fn (_ p pc sq)
    (def kind (int& pc 7))
    (def strong (int& pc 8))
    (def tb (match ((int= kind 5) %kqk) ((int= kind 4) %krk) ((int= kind 1) %kpk) (#t ())))
    (match ((int= kind 2) 0)
           ((int= kind 3) 0)
           ((null? tb) ())
           (#t (%probe-at tb strong (pos-side p) (pos-king p strong) sq (pos-king p (int- 8 strong)))))))

; A 0x88 square as 0 to 63, the ranks turned round when black is the
; stronger side.
(def %sq64
  (fn (_ sq strong)
    (match ((int= strong 0) (int+ (int* (int>> sq 4) 8) (int& sq 7)))
           (#t (int+ (int* (int- 7 (int>> sq 4)) 8) (int& sq 7))))))

(def %probe-at
  (fn (_ tb strong side wk x bk)
    (def i (%index tb (%sq64 wk strong) (%sq64 x strong) (%sq64 bk strong)))
    (match ((int= side strong) (%get (obj-ref tb 3) i))
           (#t (int- 0 (%get (obj-ref tb 4) i))))))

(provide chess/tables tables-dir tables-allow-build! tables-load! tables-build! tables-loaded? tables-longest tables-men table-probe)
