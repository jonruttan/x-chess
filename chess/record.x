; # x-chess -- a chess engine on x-lang
;
; ## chess/record.x -- the puzzles you have finished
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A file of the rated puzzles finished, a line each as it is finished:
;
;     ID RATING solved|missed THEME ...
;
; missed when a wrong move was made or a move shown.  X_CHESS_RECORD
; names the file, else it is `solved` in $XDG_CACHE_HOME/x-chess or
; ~/.cache/x-chess.  A puzzle solved once stays solved; the chooser
; passes over solved puzzles and scores each theme by them.
;
; A record is a Vector: 0 the file's path (() for none), 1 a Dict of
; each puzzle's ID to (solved? . PUZZLE), PUZZLE holding the rating and
; themes alone.

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

; Note puzzle Z finished, SOLVED? whether it was solved.
(def %note!
  (fn (_ r z solved?)
    (def old ((%entries r) get (puzzle-id z)))
    ((%entries r) set! (puzzle-id z) (pair (if (null? old) solved? (if (first old) #t solved?)) z))))

; The record at PATH; one with nothing in it when the file is not there.
(def record-load
  (fn (_ path)
    (def r (Vector make 2 ()))
    (Vector set! 0 path r)
    (Vector set! 1 (Dict make 64) r)
    (def next (if (null? path) () (guard (e ()) (puzzle-lines path))))
    (def read
      (fn (self)
        (def l (next))
        (unless (null? l)
          (do (%line! r (List reject (fn (_ w) (str=? w "")) (Str8 split " " l)))
              (self)))))
    (unless (null? next) (read))
    r))

; A line's WORDS noted, when they read as one.
(def %line!
  (fn (_ r words)
    (def rating (if (< (List length words) 3) () (parse-int (List ref 1 words))))
    (unless (null? rating)
      (%note! r (puzzle-make "" () "" rating (first words) (rest (rest (rest words))))
              (str=? (List ref 2 words) "solved")))))

; Puzzle Z finished, SOLVED? whether it was solved: noted, and added to
; the file.  A puzzle with no ID (the built-in ones) is not recorded; a
; file that cannot be written is let be.
(def record-add!
  (fn (_ r z solved?)
    (unless (str=? (puzzle-id z) "")
      (do (%note! r z solved?)
          (%append! (Vector ref 0 r)
            (Str8 append (puzzle-id z) " " (io-display-to-str (puzzle-rating z)) (if solved? " solved" " missed")
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

; The puzzles of SOURCE not yet solved: a source.
(def record-unsolved
  (fn (_ r source)
    (fn (self)
      ((fn (_ z) (if (null? z) () (if (record-solved? r (puzzle-id z)) (self) z))) (source)))))

; Of the puzzles finished with THEME rated from LOW to HIGH, as
; puzzle-file-source takes them: (solved . finished).
(def record-score
  (fn (_ r theme low high)
    (List fold
      (fn (_ acc e)
        (def v (rest e))
        (if (puzzle-in? (rest v) theme low high)
          (pair (if (first v) (+ 1 (first acc)) (first acc)) (+ 1 (rest acc)))
          acc))
      (pair 0 0) ((%entries r) ->alist))))

(provide chess/record record-path record-load record-add! record-solved? record-unsolved record-score)
