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
  (list "app.x" "base.x" "board.x" "book.x" "cli.x" "engine.x" "game.x" "match.x" "mate.x" "play.x" "player.x" "pst.x" "puzzle.x" "record.x" "san.x" "search.x" "show.x" "tables.x" "tui.x" "uci.x")))
```
---
    (("app.x" . 0) ("base.x" . 0) ("board.x" . 0) ("book.x" . 0) ("cli.x" . 0) ("engine.x" . 0) ("game.x" . 0) ("match.x" . 0) ("mate.x" . 0) ("play.x" . 0) ("player.x" . 0) ("pst.x" . 0) ("puzzle.x" . 0) ("record.x" . 0) ("san.x" . 0) ("search.x" . 0) ("show.x" . 0) ("tables.x" . 0) ("tui.x" . 0) ("uci.x" . 0))
