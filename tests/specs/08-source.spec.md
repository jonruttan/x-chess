# The source
@weight 1

A match clause is (TEST FORM): the engine evaluates the first form after
the test and nothing more, so a second form is silently dropped.  Every
clause in chess/ has one.

### no match clause has more than one form

```chess
(import x/core/doors tok-read-str)
(def walk
  (fn (self f acc)
    (def each (fn (each l acc) (if (pair? l) (each (rest l) (self (first l) acc)) acc)))
    (def size (fn (size l) (if (pair? l) (+ 1 (size (rest l))) 0)))
    (if (not (pair? f)) acc
      (each f
        (if (eq? (first f) (lit match))
          (List append acc (List filter (fn (_ c) (if (pair? c) (< 2 (size c)) #f)) (rest f)))
          acc)))))
(write (List map
  (fn (_ file) (pair file (List length (walk (tok-read-str (%base) (Str8 append (File read-all (Str8 append "chess/" file)) " ")) ()))))
  (list "base.x" "board.x" "cli.x" "game.x" "play.x" "pst.x" "san.x" "search.x" "show.x" "uci.x")))
```
---
    (("base.x" . 0) ("board.x" . 0) ("cli.x" . 0) ("game.x" . 0) ("play.x" . 0) ("pst.x" . 0) ("san.x" . 0) ("search.x" . 0) ("show.x" . 0) ("uci.x" . 0))
