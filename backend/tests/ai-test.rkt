#lang racket/base

;; AI layer tests: redaction rules, the confirm-card protocol, request
;; body shapes for both provider kinds, and the settings sentinel
;; round-trip (the stored key never leaks, __SAVED__ never overwrites).

(require json
         rackunit
         racket/file
         racket/string
         "../store.rkt"
         "../ai/redact.rkt"
         "../ai/sse.rkt"
         "../ai/providers.rkt"
         "../ai/advisor.rkt")

;; Hermetic sandbox: wipe any earlier test's library and AI settings.
(store-fresh!)

;; ---- redaction ------------------------------------------------------------

(check-equal? (redacted-text "hello world") "hello world"
              "clean text passes through untouched")
(check-equal? (redacted-text "AKIAIOSFODNN7EXAMPLE is a key")
              "[REDACTED:aws-key] is a key")
(check-equal? (redacted-text "key: sk-abc123def456ghi789jkl")
              "key: [REDACTED:api-token]")
(check-equal? (redacted-text "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----")
              "[REDACTED:private-key]")
(check-equal? (redacted-text "访问码: 12345678")
              "[REDACTED:access-code]" "device access codes redact too")
(define pv (redact-preview "Bearer abcdefghijklmnop and AKIAIOSFODNN7EXAMPLE"))
(check-equal? (length (hash-ref pv 'matches)) 2 "preview reports both rule hits")
(check-true (string-contains? (hash-ref pv 'text) "[REDACTED:aws-key]"))

;; ---- provider presets ---------------------------------------------------------

(check-true (andmap preset? provider-presets))
(check-not-false (find-preset "deepseek") "default preset exists")
(check-false (find-preset "nonexistent"))
(check-equal? (preset-kind (find-preset "anthropic")) "anthropic")
(check-equal? (preset-kind (find-preset "ollama")) "ollama")

;; ---- confirm-card protocol ------------------------------------------------------

(define-values (clean raw) (strip-confirm-marker "好的。\n<<<CONFIRM>>>{\"action\":\"add-shopping-item\",\"label\":\"待你确认\",\"body\":\"购物清单加 1 卷 PETG 黑\",\"impact\":\"≈ ¥89 · 不自动下单\",\"args\":{\"name\":\"PETG 黑\"}}"))
(check-equal? clean "好的。" "marker stripped from user-visible text")
(define card (parse-confirm-card raw))
(check-not-false (hash? card) "confirm card parses")
(check-equal? (hash-ref card 'action) "add-shopping-item")
(check-equal? (hash-ref (hash-ref card 'args) 'name) "PETG 黑")
(check-false (parse-confirm-card "") "empty tail → no card")
(check-false (parse-confirm-card "not json") "invalid tail → no card")

;; no marker → clean text with no confirm
(define-values (clean2 raw2) (strip-confirm-marker "只是普通回答"))
(check-equal? clean2 "只是普通回答")
(check-false raw2)

;; ---- request bodies --------------------------------------------------------------

(define body (advisor-request-body "glm-4.7" "系统提示" (list (hasheq 'role "user" 'content "你好"))))
(define parsed (string->jsexpr body))
(check-equal? (hash-ref parsed 'model) "glm-4.7")
(check-equal? (hash-ref parsed 'stream) #t)
(check-equal? (length (hash-ref parsed 'messages)) 2 "system prompt + one turn")
(check-equal? (hash-ref (car (hash-ref parsed 'messages)) 'role) "system")

(define abody (anthropic-request-body "claude-haiku-4-5" "系统" (list (hasheq 'role "user" 'content "hi"))))
(define aparsed (string->jsexpr abody))
(check-equal? (hash-ref aparsed 'system) "系统")
(check-true (hash-has-key? aparsed 'max_tokens))

;; ---- settings custody ---------------------------------------------------------------

(check-equal? (hash-ref (settings-view) 'api-key) "" "no key configured yet → empty view")
(check-true (pair? (hash-ref (settings-view) 'presets)) "preset table exposed to the UI")

(define saved (settings-save! (hasheq 'provider "glm" 'model "glm-4.7" 'api-key "sk-real-secret-123")))
(check-equal? (hash-ref saved 'api-key) "__SAVED__" "view shows the sentinel, never the key")
(check-true (string-contains? (file->string (settings-path)) "sk-real-secret-123") "key is in the 0600 backend file")

;; __SAVED__ round-trip must not clear or replace the stored key
(settings-save! (hasheq 'provider "glm" 'model "glm-4.7" 'api-key "__SAVED__"))
(check-true (string-contains? (file->string (settings-path)) "sk-real-secret-123")
            "sentinel round-trip preserves the stored key")
(check-true (advisor-configured?) "configured after a key + preset")

(check-equal? (hash-ref (settings-view) 'redact-enabled) #t "redaction defaults on")

;; ---- SSE smoke over a local mock server -------------------------------------

;; Raw TCP server: canned chunked SSE response. Proves stream-request
;; end to end (framing, chunk decoding, data-line dispatch) without a
;; network dependency.
(require racket/tcp
         racket/port
         racket/random)
;; Bind a random port; retry on collision (CI boxes share hosts).
(define sse-port-box (box #f))
(define listener
  (let try ()
    (define port (+ 20000 (random 40000)))
    (with-handlers ([exn:fail:network? (lambda (_) (try))])
      (set-box! sse-port-box port)
      (tcp-listen port 5 #f "127.0.0.1"))))
(define sse-port (unbox sse-port-box))
(define server-thread
  (thread
   (lambda ()
     (define-values (in out) (tcp-accept listener))
     ;; consume the request head
     (let eat () (define l (read-line in 'return-linefeed)) (unless (or (eof-object? l) (string=? l "")) (eat)))
     (define chunk (string->bytes/utf-8 "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}\n\ndata: [DONE]\n\n"))
     (fprintf out "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n")
     (fprintf out "~x\r\n" (bytes-length chunk))
     (write-bytes chunk out)
     (fprintf out "\r\n0\r\n\r\n")
     (flush-output out)
     (close-input-port in)
     (close-output-port out))))
(define got '())
(stream-request (format "http://127.0.0.1:~a/v1/chat/completions" sse-port)
                (list (cons "Content-Type" "application/json"))
                "{}"
                (lambda (payload) (set! got (cons payload got))))
(thread-wait server-thread)
(tcp-close listener)
(check-equal? (length got) 2 "two SSE data frames dispatched")
(check-not-false (member "[DONE]" got) "DONE frame seen")
(check-true (string-contains? (car (filter (lambda (x) (not (string=? x "[DONE]"))) got)) "你")
            "delta content survives the chunked framing")

(printf "ai-test: all checks passed\n")
