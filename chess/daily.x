; # x-chess -- a chess engine on x-lang
;
; ## chess/daily.x -- lichess's puzzle of the day
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; lichess's puzzle of the day (https://lichess.org/api/puzzle/daily,
; no account needed) is a JSON object whose puzzle holds the position
; with the solver to move, the solution in long algebraic, the rating,
; the ID and the themes.  Each one fetched is kept as daily.json in
; $XDG_CACHE_HOME/x-chess or ~/.cache/x-chess, and the copy kept is set
; when lichess cannot be reached.
;
; The http client and the JSON reader are imported at the first fetch,
; not when x-chess starts: with the TLS beneath them they take seconds
; to load from source.

(module chess/daily)

(import x/sys/file)
(import x/core/doors io-display-to-str str-byte-sub)
(import chess/tables chess-cache-dir chess-dir-make!)
(import chess/puzzle puzzle-make puzzle-lines)

(def daily-url "https://lichess.org/api/puzzle/daily")

; Where the last puzzle of the day fetched is kept, or () when there is
; nowhere to name.
(def daily-path
  (fn (_) ((fn (_ dir) (if (null? dir) () (Str8 append dir "/daily.json"))) (chess-cache-dir))))

; lint-known: Http
; The puzzle of the day from lichess: the response's text.  Raises when
; lichess cannot be reached or does not answer 200.
(def daily-fetch
  (fn (_)
    (import x/net/http)
    (def resp (Http request "GET" daily-url (list (pair "User-Agent" "x-chess") (pair "Accept" "application/json")) ()))
    (def status (rest (Assoc find (lit status) resp)))
    (unless (= status 200) (Err raise (lit io) (Str8 append "lichess answered " (io-display-to-str status)) status))
    (bytes->str (rest (Assoc find (lit body) resp)))))

; lint-known: Json
; The puzzle TEXT holds, lichess's puzzle of the day as JSON, or () when
; it does not read as one.
(def daily-from-text
  (fn (_ text)
    (import x/codec/json)
    (guard (e ())
      ((fn (_ pz)
         (def fen (pz get "fen"))
         (def line (pz get "solution"))
         (if (if (str? fen) (pair? line) #f)
           (puzzle-make fen line "the lichess puzzle of the day" (pz get "rating") (pz get "id") (pz get "themes"))
           ()))
       ((Json parse text) get "puzzle")))))

; The text of the file at PATH, or () when it cannot be read.
(def %kept
  (fn (_ path)
    (def next (if (null? path) () (guard (e ()) (puzzle-lines path))))
    (def join (fn (self acc) ((fn (_ l) (if (null? l) acc (self (Str8 append acc l)))) (next))))
    (if (null? next) () (join ""))))

; Keep TEXT at PATH; a file that cannot be written is let be.
(def %keep!
  (fn (_ path text)
    (unless (null? path)
      (guard (e ())
        (do ((fn (_ i) (unless (null? i) (chess-dir-make! (str-byte-sub path 0 i)))) (Str8 last-index-of "/" path))
            (File write-all path text))))))

; The puzzle of the day, as FETCH, a function of no arguments answering
; lichess's text, gives it, kept at PATH; when FETCH fails, the copy kept
; there.  (puzzle . said): said is "" for a puzzle fetched, else why it
; is the copy kept.  Raises an io Err when there is neither.
(def daily-get
  (fn (_ path fetch)
    (def got (guard (e (pair () (if (Err err? e) (e msg) (io-display-to-str e)))) (pair (fetch) "")))
    (def fresh (if (null? (first got)) () (daily-from-text (first got))))
    (def why (if (null? (first got)) (rest got) "its answer did not read as a puzzle"))
    (if (null? fresh)
      ((fn (_ kept)
         (if (null? kept)
           (Err raise (lit io) (Str8 append "no puzzle of the day: " why) ())
           (pair kept (Str8 append "lichess not reached (" why "): the last one fetched"))))
       ((fn (_ text) (if (null? text) () (daily-from-text text))) (%kept path)))
      (do (%keep! path (first got)) (pair fresh "")))))

(provide chess/daily daily-url daily-path daily-fetch daily-from-text daily-get)
