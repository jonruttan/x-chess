; # x-chess -- a chess engine on x-lang
;
; ## chess/record.x -- the puzzles you have finished
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A file of the puzzles finished, a line each as it is finished:
;
;     ID RATING solved|missed [MSms] THEME ...
;
; missed when a wrong move was made or a move shown, MS the milliseconds
; it took (a line written before times were kept has none).  X_CHESS_RECORD
; names the file, else it is `solved` in $XDG_CACHE_HOME/x-chess or
; ~/.cache/x-chess.  A puzzle solved once stays solved, and its solve time
; is the fastest it was solved in; the chooser scores each theme by the
; rated puzzles solved.
;
; A record is a Vector: 0 the file's path (() for none), 1 a Dict of
; each puzzle's ID to (solved? . PUZZLE), PUZZLE holding the rating and
; themes alone, 2 a Dict of each solved puzzle's ID to its solve time.

(module chess/record)

(import x/sys/file)
(import x/type/dict)
(import x/core/doors str-byte-sub io-display-to-str)
(import chess/board parse-int)
(import chess/tables chess-env chess-cache-dir chess-dir-make!)
(import chess/puzzle puzzle-make puzzle-id puzzle-rating puzzle-themes puzzle-in? puzzle-lines)

; The record file's path, or () when there is none to name.
(def record-path
  (fn (_)
    (def own (chess-env "X_CHESS_RECORD"))
    (def dir (chess-cache-dir))
    (match ((not (null? own)) own)
           ((not (null? dir)) (Str8 append dir "/solved"))
           (#t ()))))

(def %entries (fn (_ r) (Vector ref 1 r)))
(def %times (fn (_ r) (Vector ref 2 r)))

; Note puzzle Z finished, SOLVED? whether it was solved, in MS
; milliseconds (() when not known).
(def %note!
  (fn (_ r z solved? ms)
    (def old ((%entries r) get (puzzle-id z)))
    (def best ((%times r) get (puzzle-id z)))
    ((%entries r) set! (puzzle-id z) (pair (if (null? old) solved? (if (first old) #t solved?)) z))
    (when (if solved? (number? ms) #f)
      (when (if (null? best) #t (< ms best)) ((%times r) set! (puzzle-id z) ms)))))

; The record at PATH; one with nothing in it when the file is not there.
(def record-load
  (fn (_ path)
    (def r (Vector make 3 ()))
    (Vector set! 0 path r)
    (Vector set! 1 (Dict make 64) r)
    (Vector set! 2 (Dict make 64) r)
    (def next (if (null? path) () (guard (e ()) (puzzle-lines path))))
    (def read
      (fn (self)
        (def l (next))
        (unless (null? l)
          (do (%line! r (List reject (fn (_ w) (str=? w "")) (Str8 split " " l)))
              (self)))))
    (unless (null? next) (read))
    r))

; The milliseconds word W gives, MSms, or () when it is not one.
(def %ms
  (fn (_ w)
    (if (if (Str8 ends? "ms" w) (< 2 (Str8 length w)) #f) (parse-int (str-byte-sub w 0 (- (Str8 length w) 2))) ())))

; A line's WORDS noted, when they read as one.
(def %line!
  (fn (_ r words)
    (def rating (if (< (List length words) 3) () (parse-int (List ref 1 words))))
    (def more (List drop 3 words))
    (def ms (if (null? more) () (%ms (first more))))
    (unless (null? rating)
      (%note! r (puzzle-make "" () "" rating (first words) (if (null? ms) more (rest more)))
              (str=? (List ref 2 words) "solved") ms))))

; Puzzle Z finished, SOLVED? whether it was solved, in MS milliseconds
; (() when not known): noted, and added to the file.  A puzzle with no ID
; is not recorded; a file that cannot be written is let be.
(def record-add!
  (fn (_ r z solved? ms)
    (unless (str=? (puzzle-id z) "")
      (do (%note! r z solved? ms)
          (%append! (Vector ref 0 r)
            (Str8 append (puzzle-id z) " " (io-display-to-str (puzzle-rating z)) (if solved? " solved" " missed")
              (if (number? ms) (Str8 append " " (io-display-to-str ms) "ms") "")
              (List fold (fn (_ acc t) (Str8 append acc " " t)) "" (puzzle-themes z)) "\n"))))))

(def %append!
  (fn (_ path line)
    (unless (null? path)
      (guard (e ())
        (do ((fn (_ i) (unless (null? i) (chess-dir-make! (str-byte-sub path 0 i)))) (Str8 last-index-of "/" path))
            (def fd (File open path (list (lit wronly) (lit creat) (lit append))))
            (when (< -1 fd)
              (File write fd line (Str8 length line))
              (File close fd)))))))

; Whether the puzzle with ID has been solved.
(def record-solved?
  (fn (_ r id) ((fn (_ e) (if (null? e) #f (first e))) ((%entries r) get id))))

; Whether the puzzle with ID has been finished, solved or missed.
(def record-played? (fn (_ r id) (not (null? ((%entries r) get id)))))

; The fastest the puzzle with ID was solved in, in milliseconds, or ()
; when it has no solve time.
(def record-best (fn (_ r id) ((%times r) get id)))

; What SOURCE gives of the puzzles not yet solved, ID-OF answering the
; ID of what it gives (puzzle-id for puzzles, puzzle-line-id for the
; lines that hold them): a source.
(def record-unsolved
  (fn (_ r source id-of)
    (fn (self)
      ((fn (_ z) (if (null? z) () (if (record-solved? r (id-of z)) (self) z))) (source)))))

; Of the rated puzzles finished with THEME rated from LOW to HIGH, as
; puzzle-file-source takes them: (solved . finished).
(def record-score
  (fn (_ r theme low high)
    (List fold
      (fn (_ acc e)
        (def v (rest e))
        (if (if (= 0 (puzzle-rating (rest v))) #f (puzzle-in? (rest v) theme low high))
          (pair (if (first v) (+ 1 (first acc)) (first acc)) (+ 1 (rest acc)))
          acc))
      (pair 0 0) ((%entries r) ->alist))))

(provide chess/record record-path record-load record-add! record-solved? record-played? record-best
  record-unsolved record-score)
