#lang racket/base

;; Minimal streaming HTTP client for SSE endpoints (OpenAI-compatible
;; /chat/completions stream and Anthropic /v1/messages stream). Speaks
;; HTTP/1.1 over TLS or plain TCP, parses chunked transfer encoding, and
;; hands every `data:` frame to the callback. Deliberately tiny: one
;; request, one stream, no connection reuse. The connection lives in the
;; caller's custodian context — the streaming route's per-request
;; custodian tears it down with the request, which is exactly right.

(require openssl
         racket/tcp
         racket/string)

(provide stream-request)

;; ---- url ---------------------------------------------------------------------

(define (parse-url url-string)
  (define m (regexp-match #px"^(https?)://([^/:]+)(?::(\\d+))?(/.*)?$" url-string))
  (unless m
    (raise-argument-error 'stream-request "http(s) url" url-string))
  (values (list-ref m 1)
          (list-ref m 2)
          (let ([p (list-ref m 3)])
            (if p (string->number p) (if (string=? (list-ref m 1) "https") 443 80)))
          (let ([p (list-ref m 4)])
            (if p p "/"))))

;; ---- wire helpers -------------------------------------------------------------

(define (read-headers in)
  (let loop ([headers '()])
    (define line (read-line in 'return-linefeed))
    (cond
      [(eof-object? line) (reverse headers)]
      [(string=? (string-trim line) "") (reverse headers)]
      [else (loop (cons (string-trim line) headers))])))

(define (header-value headers name)
  (define lower (string-downcase name))
  (for/first ([h (in-list headers)]
              #:when (string-prefix? (string-downcase h) (string-append lower ":")))
    (string-trim (substring h (add1 (string-index-of h ":"))))))

(define (string-index-of s needle)
  (define m (regexp-match-positions (regexp (regexp-quote needle)) s))
  (if m (caar m) -1))

;; Copy exactly n bytes from in, handing each read to emit-bytes.
(define (copy-n-bytes in n emit-bytes)
  (define buf (make-bytes 65536))
  (let loop ([remaining n])
    (unless (<= remaining 0)
      (define got (read-bytes (min remaining (bytes-length buf)) in))
      (cond
        [(eof-object? got)
         (raise (exn:fail "stream-request: server closed mid-chunk" (current-continuation-marks)))]
        [else
         (emit-bytes got 0 (bytes-length got))
         (loop (- remaining (bytes-length got)))]))))

;; ---- SSE line pump --------------------------------------------------------------

;; Returns a procedure taking (chunk-string); feeds complete lines to the
;; handler. Chunks arrive split across line boundaries.
(define (make-line-pump handle-line)
  (define pending "")
  (lambda (chunk)
    (set! pending (string-append pending chunk))
    (let loop ()
      (define idx (string-index-of pending "\n"))
      (when (>= idx 0)
        (define line (string-trim (substring pending 0 idx) "\r" #:repeat? #t))
        (set! pending (substring pending (add1 idx)))
        (handle-line line)
        (loop)))))

;; ---- the one request ------------------------------------------------------------

;; Sends POST url with headers/body; on every SSE `data:` frame calls
;; (on-data payload). Returns when the stream ends. Raises on connect
;; failure or non-2xx status (with the error body, best effort).
(define (stream-request url-string headers body on-data
                        #:timeout-seconds [timeout-seconds 300])
  (define-values (scheme host port path) (parse-url url-string))
  (define connect (if (string=? scheme "https") ssl-connect tcp-connect))
  (define-values (in out) (connect host port))
  (dynamic-wind
    (lambda () (void))
    (lambda ()
    (file-stream-buffer-mode out 'line)
    (fprintf out "POST ~a HTTP/1.1\r\n" path)
    (fprintf out "Host: ~a:~a\r\n" host port)
    (fprintf out "Accept: text/event-stream\r\n")
    (fprintf out "Connection: close\r\n")
    (for ([h (in-list headers)])
      (fprintf out "~a: ~a\r\n" (car h) (cdr h)))
    (fprintf out "Content-Length: ~a\r\n\r\n" (bytes-length (string->bytes/utf-8 body)))
    (display body out)
    (flush-output out)

    ;; watchdog: a stuck provider must not wedge the UI forever
    (define deadline (+ (current-inexact-milliseconds) (* timeout-seconds 1000)))

    (define status-line (read-line in 'return-linefeed))
    (when (eof-object? status-line)
      (raise (exn:fail "stream-request: empty response" (current-continuation-marks))))
    ;; local name: (define headers ...) would shadow the parameter and
    ;; make the request-header loop above read an uninitialized binding
    (define response-headers (read-headers in))
    (define chunked?
      (let ([te (header-value response-headers "transfer-encoding")])
        (and te (string-contains? (string-downcase te) "chunked"))))

    (define line-pump (make-line-pump (sse-line-handler on-data)))
    (define (emit-string chunk start end)
      (line-pump (bytes->string/utf-8 (subbytes chunk start end))))

    (define status-ok?
      (regexp-match? #px"^HTTP/1\\.[01] 2" status-line))

    (if chunked?
        (let pump-chunks ()
          (define size-line (read-line in 'return-linefeed))
          (cond
            [(eof-object? size-line) void]
            [else
             (define n (string->number (string-trim size-line) 16))
             (cond
               [(not n) (pump-chunks)] ; trailers or keep-alives — skip
               [(= n 0) void]          ; final chunk
               [else
                (copy-n-bytes in (+ n 2) emit-string) ; chunk bytes + CRLF
                (unless (and status-ok? (< (current-inexact-milliseconds) deadline))
                  (raise (exn:fail "stream-request: stream deadline exceeded"
                                   (current-continuation-marks))))
                (pump-chunks)])]))
        ;; unchunked: stream the raw body
        (let pump-plain ()
          (define buf (make-bytes 16384))
          (define n (read-bytes-avail! buf in))
          (unless (eof-object? n)
            (when (and (number? n) (> n 0))
              (emit-string buf 0 n)
              (pump-plain)))))

    (unless status-ok?
      (raise (exn:fail (format "stream-request: ~a" status-line)
                       (current-continuation-marks))))
    )
    (lambda ()
      (with-handlers ([exn:fail? void])
        (close-input-port in)
        (close-output-port out)))))

;; SSE frame handler: `data: payload` → (on-data payload); ignore comments
;; and empty frames; bare "data" with no colon also counts.
(define (sse-line-handler on-data)
  (lambda (line)
    (cond
      [(string-prefix? line "data:")
       (define payload (string-trim (substring line 5)))
       (on-data payload)]
      [(string=? line "data")
       (on-data "")]
      [else void])))
