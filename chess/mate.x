; # x-chess -- a chess engine on x-lang
;
; ## chess/mate.x -- mates found by forcing moves
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A mate search apart from the engine's.  The attacker's moves are its
; checks, and in a mate in one or two its first move may be quiet too;
; the defender's are all its moves, each of which must lose.  A mating
; move is a check, so every mate in one or two is found, and a longer
; one when the attacker checks at every move.  A check leaves the
; defender few replies, so a mate by checks in five takes seconds where
; the engine's search, which looks at every move, would take hours.
;
; A line is a list of moves, the attacker's and the defender's in turn.

(module chess/mate)

(import x/sys/gc)
(import x/core/doors int+ int- int* int% int< int= obj-ref obj-set!)
(import chess/board pos-copy in-check? gen-moves make! make-checked! unmake! legal-moves)

; 1 nodes, 2 the clock reading to stop at (0 for none).
(def %state (Vector make 2 0))

; Count a node; every 64 look at the clock, every 1024 collect: x
; collects only when asked.
(def %tick!
  (fn (_)
    (def n (int+ (obj-ref %state 1) 1))
    (obj-set! %state 1 n)
    (when (int= 0 (int% n 64)) (%look!))
    (when (int= 0 (int% n 1024)) (Heap collect))))

(def %look!
  (fn (_)
    (def stop (obj-ref %state 2))
    (when (if (int= stop 0) #f (int< stop (Sys clock)))
      (Err raise (lit mate-stop) "the mate search ran out of time" ()))))

; The attacker's legal moves in P, checks first; its quiet moves after
; them when QUIET? says so.
(def %attacks
  (fn (_ p quiet?)
    (def check (in-check? p))
    (def go
      (fn (self ms checks quiets)
        (if (null? ms)
          (List append (List reverse checks) (List reverse quiets))
          ((fn (_ m)
             (if (make-checked! p m check)
               ((fn (_ gives)
                  (unmake! p m)
                  (match (gives (self (rest ms) (pair m checks) quiets))
                         (quiet? (self (rest ms) checks (pair m quiets)))
                         (#t (self (rest ms) checks quiets))))
                (in-check? p))
               (self (rest ms) checks quiets)))
           (first ms)))))
    (go (gen-moves p #f) () ())))

; A mate in N for the side to move in P: its line, or ().  Its quiet
; moves are tried when QUIET? says so.
(def %attack
  (fn (_ p n quiet?)
    (%tick!)
    (def try
      (fn (self ms)
        (if (null? ms) ()
          ((fn (_ line) (if (null? line) (self (rest ms)) line))
           (%attack-with p (first ms) n)))))
    (try (%attacks p quiet?))))

; The line when the attacker's move M in P mates in N, or ().
(def %attack-with
  (fn (_ p m n)
    (make! p m)
    (def line (%defend p (int- n 1)))
    (unmake! p m)
    (if (eq? line (lit escape)) () (pair m line))))

; With the defender to move in P: the line by which every reply is mated
; within N more of the attacker's moves, from the reply that holds out
; longest (() when it is mated now), or escape when one reply is not.
(def %defend
  (fn (_ p n)
    (%tick!)
    (def replies (legal-moves p))
    (match ((null? replies) (if (in-check? p) () (lit escape)))
           ((int= n 0) (lit escape))
           (#t (%refute p replies n ())))))

(def %refute
  (fn (self p rs n found)
    (if (null? rs) found
      ((fn (_ line)
         (if (null? line) (lit escape)
           (self p (rest rs) n
             (if (int< (List length found) (+ 1 (List length line))) (pair (first rs) line) found))))
       (%reply p (first rs) n)))))

; The attacker's mate in N after the defender's reply R in P, or ().
(def %reply
  (fn (_ p r n)
    (make! p r)
    (def line (%attack p n #f))
    (unmake! p r)
    line))

; Run F on a copy of P with MS milliseconds (0 for no limit): what it
; answers, or () when the time ran out.
(def %timed
  (fn (_ p ms f)
    (obj-set! %state 1 0)
    (obj-set! %state 2 (if (int= ms 0) 0 (int+ (Sys clock) (int* ms 1000))))
    (guard (e (match ((eq? (Err label e) (lit mate-stop)) ()) (#t (error e))))
      (f (pos-copy p)))))

; The shortest mate in at most K moves for the side to move in P, found
; within MS milliseconds (0 for no limit): its line, or () when none was
; found.
(def mate-find
  (fn (_ p k ms)
    (%timed p ms
      (fn (_ q)
        (def deepen (fn (self n) (if (int< k n) () ((fn (_ line) (if (null? line) (self (+ n 1)) line)) (%attack q n (int< n 3))))))
        (deepen 1)))))

; With the defender to move in P, whether every reply is mated within K
; of the attacker's moves, found within MS milliseconds: the line from
; the reply that holds out longest (() when the defender is mated now),
; or escape when a reply is not mated or the time ran out.
(def mate-forced
  (fn (_ p k ms)
    ((fn (_ r) (if (null? r) (lit escape) (first r)))
     (%timed p ms (fn (_ q) ((fn (_ line) (if (eq? line (lit escape)) () (list line))) (%defend q k)))))))

(provide chess/mate mate-find mate-forced)
