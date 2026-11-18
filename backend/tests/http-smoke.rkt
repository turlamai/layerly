#lang racket/base

;; HTTP smoke test: boots the real server surface (start-server over the
;; route list in main.rkt) on an ephemeral port and walks the whole v1
;; lifecycle with plain HTTP — seed → projects → print-prep dispatch →
;; fixture print → history, plus the honest advisor error path and the
;; settings round-trip. This is the wire-level check the schema can't see.

(require json
         racket/list
         racket/port
         racket/random
         racket/string
         racket/tcp
         rackunit
         glaze/server
         "../device/manager.rkt"
         "../main.rkt"
         "../store.rkt")

;; ---- boot on an ephemeral port -------------------------------------------

;; Find a free port by bind-and-close, then hand it to start-server. The
;; reuse race is theoretical for a smoke run; start-server fails loudly
;; if the port is taken, which the test reports honestly.
(define port
  (let try ()
    (define p (+ 20000 (random 40000)))
    (with-handlers ([exn:fail:network? (lambda (_) (try))])
      (define probe (tcp-listen p 16 #f "127.0.0.1"))
      (tcp-close probe)
      p)))

;; Boot-time init outside any request custodian: the SQLite connection
;; must outlive individual requests (family rule D4 — resources created
;; under a per-request custodian die with the request).
(store-fresh!)
(void (store-init!))
(void (manager-init!))
(void
 (thread
  (lambda ()
    (start-server #:port port
                  #:public-dir "/tmp/layerly-smoke-public"
                  #:api api
                  #:api-token "smoke-token"
                  #:serve-api-client? #f))))

;; ---- tiny client -----------------------------------------------------------

(define (call-route path [body (hasheq)])
  (define-values (in out)
    (tcp-connect "127.0.0.1" port))
  (define payload (jsexpr->string body))
  (fprintf out "POST /~a HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Glaze-Token: smoke-token\r\nContent-Type: application/json\r\nContent-Length: ~a\r\nConnection: close\r\n\r\n"
           path (bytes-length (string->bytes/utf-8 payload)))
  (display payload out)
  (flush-output out)
  (let eat-headers ()
    (define l (read-line in 'return-linefeed))
    (unless (or (eof-object? l) (string=? (string-trim l) ""))
      (eat-headers)))
  (define body-str (port->string in))
  (close-input-port in)
  (close-output-port out)
  (string->jsexpr body-str))

;; wait for server readiness before the first real call
(let loop ([n 0])
  (define ok?
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (hash-ref (call-route "api/health") 'ok #f)))
  (unless (or ok? (> n 60))
    (sleep 0.1)
    (loop (add1 n))))

;; ---- the lifecycle -----------------------------------------------------------

(define health (call-route "api/health"))
(check-true (hash-ref health 'ok))
(check-equal? (hash-ref health 'version) "0.1.0")

;; seed the demo workbench (library starts empty in this sandbox)
(define summary (call-route "api/demo/seed"))
(check-equal? (hash-ref (hash-ref summary 'counts) 'projects) 6)

;; connect the fixture device the seed registered
(define devices (hash-ref (call-route "api/device/list") 'devices))
(define fixture-device (findf (lambda (d) (string=? (hash-ref d 'kind) "fixture")) devices))
(check-not-false fixture-device)
(define snap0 (call-route "api/device/connect" (hasheq 'id (hash-ref fixture-device 'id))))
(check-equal? (hash-ref snap0 'state) "idle")

(define projects (hash-ref (call-route "api/projects/list") 'projects))
(check-equal? (length projects) 6)
(define printing (findf (lambda (p) (string=? (hash-ref p 'status) "printing")) projects))
(check-not-false printing "live demo job shows as printing")
(check-equal? (hash-ref (hash-ref printing 'job) 'layer) 114)

;; project detail carries versions/plans/jobs
(define detail (call-route "api/projects/get" (hasheq 'id (hash-ref printing 'id))))
(check-equal? (length (hash-ref detail 'versions)) 4)
(check-equal? (length (hash-ref detail 'plans)) 2)

;; create a fresh project and queue a print on the fixture
(define p (hash-ref (call-route "api/projects/create"
                                (hasheq 'name "smoke 件" 'brief "" 'size-text "" 'target-qty 1))
                    'id))
(define job (call-route "api/jobs/create"
                        (hasheq 'project-id p 'seq 1 'total 1 'layers 12
                                'minutes 1 'grams 3 'material-name "PETG 黑")))
(define queued (call-route "api/jobs/queue" (hasheq 'job-id (hash-ref job 'id))))
(check-true (hash-ref queued 'queued) "dispatch accepted by the fixture")
(check-equal? (hash-ref (hash-ref queued 'device) 'state) "heating")

;; the fixture completes the 12-layer job at the default 4 layers/s pace
;; (3 s heatup + 3 s printing); poll up to 15 s
(let loop ([n 0])
  (define job (hash-ref (call-route "api/device/state") 'job #f))
  (define st (and job (hash-ref job 'job-id #f)))
  (unless (or (not st) (> n 150))
    (sleep 0.1)
    (loop (add1 n))))
(define job-after (call-route "api/jobs/get" (hasheq 'id (hash-ref job 'id))))
(check-equal? (hash-ref job-after 'status) "done" "fixture completed the queued job")
(check-equal? (hash-ref job-after 'layers) 12)
(define p2 (hash-ref (call-route "api/projects/get" (hasheq 'id p)) 'project))
(check-equal? (hash-ref p2 'status) "done" "single-piece batch → project done")

;; materials / shopping round-trips
(define m (hash-ref (call-route "api/materials/create"
                                (hasheq 'material (hasheq 'name "冒烟 PLA" 'type "PLA" 'remaining-g 500)))
                    'id))
(define m-updated (call-route "api/materials/update" (hasheq 'id m 'patch (hasheq 'remaining-g 450))))
(check-equal? (hash-ref m-updated 'remaining-g) 450.0)
(define shop (call-route "api/shopping/create" (hasheq 'name "冒烟件" 'qty 1 'price 9)))
(check-not-false (hash-ref shop 'id))

;; device controls against an ACTIVE job: queue a slow piece, wait for
;; printing, pause/resume it, then let it finish
(define job2 (call-route "api/jobs/create"
                         (hasheq 'project-id p 'seq 2 'total 2 'layers 60
                                 'minutes 2 'grams 9 'material-name "PETG 黑")))
(call-route "api/jobs/queue" (hasheq 'job-id (hash-ref job2 'id)))
(let loop ([n 0])
  (define state (hash-ref (call-route "api/device/state") 'state ""))
  (unless (or (string=? state "printing") (> n 100))
    (sleep 0.1)
    (loop (add1 n))))
(check-equal? (hash-ref (call-route "api/device/state") 'state) "printing")
(call-route "api/device/pause")
(check-equal? (hash-ref (call-route "api/device/state") 'state) "paused")
(call-route "api/device/resume")
(check-equal? (hash-ref (call-route "api/device/state") 'state) "printing")
(let loop ([n 0])
  (define job (hash-ref (call-route "api/device/state") 'job #f))
  (unless (or (not job) (> n 250))
    (sleep 0.1)
    (loop (add1 n))))
(check-equal? (hash-ref (call-route "api/jobs/get" (hasheq 'id (hash-ref job2 'id))) 'status)
              "done")

;; advisor honesty: no BYOK configured → the stream opens with ERR
(define-values (sin sout) (tcp-connect "127.0.0.1" port))
(define chat-body (jsexpr->string (hasheq 'conversation-id "c-none" 'message "你好" 'refs '())))
(fprintf sout "POST /api/advisor/chat HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Glaze-Token: smoke-token\r\nContent-Type: application/json\r\nContent-Length: ~a\r\nConnection: close\r\n\r\n"
         (bytes-length (string->bytes/utf-8 chat-body)))
(display chat-body sout)
(flush-output sout)
(let eat-headers ()
  (define l (read-line sin 'return-linefeed))
  (unless (or (eof-object? l) (string=? (string-trim l) ""))
    (eat-headers)))
(define chat-response (port->string sin))
(close-input-port sin)
(close-output-port sout)
(check-true (string-contains? chat-response "ERR")
            "unconfigured advisor answers ERR, not a fake stream")
(check-true (string-contains? chat-response "advisor-not-configured"))

;; settings round-trip
(call-route "api/settings/set" (hasheq 'key "theme" 'value "dark"))
(check-equal? (hash-ref (call-route "api/settings/get" (hasheq 'key "theme")) 'value) "dark")

(printf "http-smoke: all checks passed\n")
