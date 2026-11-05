; # x-chess -- a chess engine on x-lang
;
; ## chess/search.x -- choosing a move
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Negamax with alpha-beta, iteratively deepened, and a quiescence search
; of captures at the leaves so a position is never judged in the middle
; of an exchange.  Moves are tried best guess first: the move the last
; iteration chose, then captures by most valuable victim and least
; valuable attacker, then the two quiet moves that last cut off at the
; same ply (the killers), then the rest.
;
; The search runs on a copy of the position and stops by raising, at a
; time, node or depth limit or when the poll function says so; the move
; it answers is the best one a finished search of the root found.  The
; heap is collected every %collect-nodes nodes: x collects only when
; asked, and a search makes garbage at every node.
;
; The hot paths branch with match alone (see chess/board.x), and a match
; clause takes one form, so a value a clause needs twice is passed to a
; function of its own.

(module chess/search)

(import x/sys/gc)
(import x/core/doors int+ int- int* int/ int< int= int& int>> obj-ref obj-set!)
(import chess/pst pst-worth)
(import chess/board pos-copy pos-side pos-half pos-middle pos-end pos-phase pos-piece
  move-from move-to move-promo move-uci in-check? gen-moves make! unmake! make-checked! legal-moves)

(def MATE 30000)
(def %infinity 32000)

; --- evaluation ------------------------------------------------------------------
;
; The middle-game and end-game sums blended by phase, from the side to
; move's point of view.
(def evaluate
  (fn (_ p)
    (def phase (match ((int< 24 (pos-phase p)) 24) (#t (pos-phase p))))
    (def score (int/ (int+ (int* (pos-middle p) phase) (int* (pos-end p) (int- 24 phase))) 24))
    (match ((int= (pos-side p) 0) score) (#t (int- 0 score)))))

; --- the search's state ------------------------------------------------------------

(def %check-nodes 128)
(def %collect-nodes 2048)

; One Vector of counters, read and written by slot: 1 nodes, 2 the
; clock reading to stop at (0 for none), 3 the node count to stop at (0
; for none), 4 nodes until the next look at the clock and the poll, 5
; nodes until the next collection.
(def %state (Vector make 5 0))
(def %killers (Vector make 256 0))
(def %poll (fn (_) #f))

(def %stop (fn (_) (Err raise (lit chess-stop) "the search was stopped" ())))

; Count a node; every so often look at the limits, and collect.
(def %tick!
  (fn (_)
    (obj-set! %state 1 (int+ (obj-ref %state 1) 1))
    (obj-set! %state 4 (int- (obj-ref %state 4) 1))
    (match ((int< 0 (obj-ref %state 4)) #f) (#t (%checkpoint!)))))

(def %checkpoint!
  (fn (_)
    (obj-set! %state 4 %check-nodes)
    (obj-set! %state 5 (int- (obj-ref %state 5) %check-nodes))
    (match ((int< 0 (obj-ref %state 5)) ()) (#t (%collect!)))
    (match
      ((match ((int= (obj-ref %state 2) 0) #f) (#t (int< (obj-ref %state 2) (Sys clock)))) (%stop))
      ((match ((int= (obj-ref %state 3) 0) #f) (#t (int< (obj-ref %state 3) (obj-ref %state 1)))) (%stop))
      ((%poll) (%stop))
      (#t #f))))

(def %collect!
  (fn (_)
    (obj-set! %state 5 %collect-nodes)
    (Heap collect)))

; --- ordering ------------------------------------------------------------------------

; A capture's order: the victim's worth times ten, less the attacker's.
(def %victim (list 0 1 2 3 4 5 6))

(def %capture-score
  (fn (_ p m)
    (int- (int* (int& (pos-piece p (move-to m)) 7) 10) (int& (pos-piece p (move-from m)) 7))))

; Insert the move M scoring S into ACC, a list of (score . move) highest
; first.
(def %insert
  (fn (self s m acc)
    (match ((null? acc) (list (pair s m)))
           ((int< (first (first acc)) s) (pair (pair s m) acc))
           (#t (pair (first acc) (self s m (rest acc)))))))

; MOVES with FIRST first when among them, then captures and promotions
; best first, then the killers at PLY, then the rest.
(def %order
  (fn (_ p moves first-move ply)
    (def k1 (obj-ref %killers (int+ (int* ply 2) 1)))
    (def k2 (obj-ref %killers (int+ (int* ply 2) 2)))
    (%order-split p moves first-move k1 k2 () () () ())))

(def %order-split
  (fn (self p ms fm k1 k2 lead caps kill quiet)
    (match
      ((null? ms)
        (List append lead (List map rest caps) kill (List reverse quiet)))
      ((int= (first ms) fm) (self p (rest ms) fm k1 k2 (list fm) caps kill quiet))
      ((match ((int< 0 (pos-piece p (move-to (first ms)))) #t) ((int< 0 (move-promo (first ms))) #t) (#t #f))
        (self p (rest ms) fm k1 k2 lead
          (%insert (int+ (%capture-score p (first ms)) (int* (move-promo (first ms)) 10)) (first ms) caps)
          kill quiet))
      ((int= (first ms) k1) (self p (rest ms) fm k1 k2 lead caps (pair k1 kill) quiet))
      ((int= (first ms) k2) (self p (rest ms) fm k1 k2 lead caps (pair k2 kill) quiet))
      (#t (self p (rest ms) fm k1 k2 lead caps kill (pair (first ms) quiet))))))

(def %killer!
  (fn (_ p m ply)
    (match
      ((int< 0 (pos-piece p (move-to m))) ())
      ((int= m (obj-ref %killers (int+ (int* ply 2) 1))) ())
      (#t (%killer-push! m (int+ (int* ply 2) 1))))))

(def %killer-push!
  (fn (_ m i)
    (obj-set! %killers (int+ i 1) (obj-ref %killers i))
    (obj-set! %killers i m)))

; --- quiescence -------------------------------------------------------------------------
;
; Captures only, from the side to move's standing score.  A capture
; that could not lift the score to alpha even with %delta to spare is
; not tried (delta pruning), a promotion always is.

(def %delta 200)

(def %worth
  (do (def v (Vector make 7 0))
      (List for-each (fn (_ k) (obj-set! v (int+ k 1) (pst-worth k))) (List range 1 7))
      v))

(def %quiesce
  (fn (_ p alpha beta ply)
    (%tick!)
    (%quiesce-from p (evaluate p) alpha beta ply)))

(def %quiesce-from
  (fn (_ p stand alpha beta ply)
    (match
      ((int< stand beta)
        (%quiesce-moves p (%order p (gen-moves p #t) 0 127) (match ((int< alpha stand) stand) (#t alpha)) beta ply
          (in-check? p) (int+ stand %delta)))
      (#t beta))))

; Whether capture M cannot reach ALPHA from HOPE, the standing score
; and the margin.
(def %futile?
  (fn (_ p m hope alpha)
    (match
      ((int< 0 (move-promo m)) #f)
      (#t (int< (int+ hope (obj-ref %worth (int+ (int& (pos-piece p (move-to m)) 7) 1))) alpha)))))

(def %quiesce-moves
  (fn (self p ms alpha beta ply check hope)
    (match
      ((null? ms) alpha)
      ((%futile? p (first ms) hope alpha) (self p (rest ms) alpha beta ply check hope))
      ((make-checked! p (first ms) check)
        (%quiesce-after p ms alpha beta ply check hope (int- 0 (%quiesce p (int- 0 beta) (int- 0 alpha) (int+ ply 1)))))
      (#t (self p (rest ms) alpha beta ply check hope)))))

(def %quiesce-after
  (fn (_ p ms alpha beta ply check hope score)
    (unmake! p (first ms))
    (match
      ((int< score beta) (%quiesce-moves p (rest ms) (match ((int< alpha score) score) (#t alpha)) beta ply check hope))
      (#t beta))))

; --- the principal variation ---------------------------------------------------------------
;
; A triangle of lines: ply K's line holds 128 slots from K*128, its
; length in %pv-len.  A move that raises alpha at ply K makes K's line
; that move then the line its search left at K+1.  Plies past 125 keep
; no line.

(def %pv (Vector make 16384 0))
(def %pv-len (Vector make 128 0))

(def %pv-clear! (fn (_ ply) (match ((int< ply 127) (obj-set! %pv-len (int+ ply 1) 0)) (#t ()))))

(def %pv-raise!
  (fn (_ ply m)
    (match ((int< ply 126) (%pv-set-line! ply m (obj-ref %pv-len (int+ ply 2))))
           (#t ()))))

(def %pv-set-line!
  (fn (_ ply m n)
    (obj-set! %pv (int+ (int* ply 128) 1) m)
    (%pv-copy! (int* ply 128) (int* (int+ ply 1) 128) 0 n)
    (obj-set! %pv-len (int+ ply 1) (int+ n 1))))

; The child's moves from I on, after the move at TO.
(def %pv-copy!
  (fn (self to from i n)
    (match
      ((int< i n)
        (do (obj-set! %pv (int+ to (int+ i 2)) (obj-ref %pv (int+ from (int+ i 1))))
            (self to from (int+ i 1) n)))
      (#t ()))))

; The root's line, a list of moves.
(def %pv-root
  (fn (_)
    (List map (fn (_ i) (obj-ref %pv (int+ i 1))) (List range 0 (obj-ref %pv-len 1)))))

; --- alpha-beta ----------------------------------------------------------------------------
;
; The score of P searched DEPTH plies, within ALPHA and BETA; PLY is how
; far from the root.  At the root the best move is kept in %best.

(def %best (Vector make 2 0))

(def %search
  (fn (_ p depth alpha beta ply)
    (%pv-clear! ply)
    (match
      ((int= ply 0) (%search-node p depth alpha beta ply))
      ((int< 99 (pos-half p)) 0)
      ((int< depth 1) (%quiesce p alpha beta ply))
      (#t (%search-node p depth alpha beta ply)))))

(def %search-node
  (fn (_ p depth alpha beta ply)
    (%tick!)
    (%search-ordered p depth alpha beta ply (in-check? p))))

(def %search-ordered
  (fn (_ p depth alpha beta ply check)
    (%search-moves p
      (%order p (gen-moves p #f) (match ((int= ply 0) (obj-ref %best 1)) (#t 0)) ply)
      ; a side in check looks one ply further: the reply is forced
      (match (check (int+ depth 1)) (#t depth))
      alpha beta ply check 0)))

(def %search-moves
  (fn (self p ms depth alpha beta ply check legal)
    (match
      ((null? ms)
        (match ((int< 0 legal) alpha)
               (check (int- (int+ 0 ply) MATE))
               (#t 0)))
      ((make-checked! p (first ms) check)
        (%search-after p ms depth alpha beta ply check legal
          (int- 0 (%search p (int- depth 1) (int- 0 beta) (int- 0 alpha) (int+ ply 1)))))
      (#t (self p (rest ms) depth alpha beta ply check legal)))))

(def %search-after
  (fn (_ p ms depth alpha beta ply check legal score)
    (unmake! p (first ms))
    (match
      ((int< score beta)
        (match
          ((int< alpha score) (%search-raised p ms depth score beta ply check legal))
          (#t (%search-moves p (rest ms) depth alpha beta ply check (int+ legal 1)))))
      (#t (%search-cut p (first ms) ply beta)))))

; The first of MS raised alpha to SCORE: at the root it is the best move.
(def %search-raised
  (fn (_ p ms depth score beta ply check legal)
    (%pv-raise! ply (first ms))
    (match ((int= ply 0) (%root-best! (first ms) score)) (#t ()))
    (%search-moves p (rest ms) depth score beta ply check (int+ legal 1))))

(def %root-best! (fn (_ m score) (obj-set! %best 1 m) (obj-set! %best 2 score)))

(def %search-cut
  (fn (_ p m ply beta)
    (%killer! p m ply)
    beta))

; --- the root -----------------------------------------------------------------------------

; Search P for at most DEPTH plies, MS milliseconds of processor time and
; NODES nodes (0 for no limit on either), POLL answering true to stop.
; Each finished depth is handed to INFO as (depth score nodes
; microseconds move line), LINE the moves the search expects from move
; on.  Answers that last report, or () when P has no
; legal move.  Stopped before any root move is finished, it answers the
; first legal move, scored 0: a move in time is worth more than none.
(def search
  (fn (_ p depth ms nodes poll info)
    (def q (pos-copy p))
    (def t0 (Sys clock))
    (def legal (legal-moves q))
    (obj-set! %state 1 0)
    (obj-set! %state 2 (match ((int= ms 0) 0) (#t (int+ t0 (int* ms 1000)))))
    (obj-set! %state 3 nodes)
    (obj-set! %state 4 %check-nodes)
    (obj-set! %state 5 %collect-nodes)
    (obj-set! %best 1 0)
    (obj-set! %best 2 0)
    (List for-each (fn (_ i) (obj-set! %killers i 0)) (List range 1 257))
    (set! %poll poll)
    (Heap collect)
    (match ((null? legal) ())
           (#t (%deepen q 1 depth t0 info (first legal) ())))))

(def %deepen
  (fn (self q d depth t0 info fallback last)
    (match
      ((int< depth d) last)
      (#t (self q (int+ d 1) depth t0 info fallback (%iterate q d t0 info fallback last))))))

; One iteration at depth D: its report.  When the search is stopped the
; deepening ends with LAST's report, improved by any root move this
; iteration finished, or FALLBACK's when there is neither.
(def %iterate
  (fn (_ q d t0 info fallback last)
    (def got
      (guard (e (match ((eq? (Err label e) (lit chess-stop)) (lit stopped)) (#t (error e))))
        (%search q d (int- 0 %infinity) %infinity 0)))
    (def report (list d (obj-ref %best 2) (obj-ref %state 1) (int- (Sys clock) t0) (obj-ref %best 1) (%pv-root)))
    (match
      ((eq? got (lit stopped)) (Err raise (lit chess-done) "" (%stopped-report report fallback last)))
      (#t (%report info report)))))

(def %stopped-report
  (fn (_ report fallback last)
    (match
      ((not (int= (obj-ref %best 1) 0)) (pair (match ((null? last) (first report)) (#t (first last))) (rest report)))
      ((null? last) (list (first report) 0 (List ref 2 report) (List ref 3 report) fallback (list fallback)))
      (#t last))))
(def %report (fn (_ info report) (info report) report))

; Search and answer the best report: the stopped search's raise carries
; it out of the deepening.
(def search-best
  (fn (_ p depth ms nodes poll info)
    (guard (e (match ((eq? (Err label e) (lit chess-done)) (e data)) (#t (error e))))
      (search p depth ms nodes poll info))))

(def mate-score? (fn (_ s) (match ((int< (int- MATE 1000) s) #t) ((int< s (int- 1000 MATE)) #t) (#t #f))))

; Moves to mate for a mate score: positive when the side to move mates.
(def mate-in
  (fn (_ s)
    (match ((int< 0 s) (int/ (int+ (int- MATE s) 1) 2))
           (#t (int- 0 (int/ (int+ s MATE) 2))))))

(provide chess/search MATE evaluate search-best mate-score? mate-in)
