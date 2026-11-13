#lang racket/base

;; Non-interactive native UI acceptance check: boots the real app shell,
;; waits for the React document title, captures evidence and reports
;; pass/fail verdicts. Run via `raco glaze verify` after
;; `pnpm --filter @layerly/desktop build`.

(require racket/file
         glaze)

(define public (build-path (current-directory) "apps/desktop/dist"))
(define verdicts '())
(define-values (_kind stop)
  (run-app
   #:public-dir public
   #:title "Layerly Verification"
   #:on-ready
   (lambda (wv url)
     (define deadline (+ (current-inexact-milliseconds) 15000))
     (define loaded?
       (let loop ()
         (cond
           [(equal? (webview-title wv) "Layerly") #t]
           [(>= (current-inexact-milliseconds) deadline) #f]
           [else (sleep 0.1) (loop)])))
     (define shot (and loaded? (webview-capture! wv)))
     (set! verdicts
           (list (cons 'page-loaded loaded?)
                 (cons 'url (equal? (webview-url wv) url))
                 (cons 'capture (and shot (file-exists? shot) (> (file-size shot) 0)))))
     (webview-close wv))))
(stop)
(for ([verdict (in-list verdicts)])
  (printf "[verify] ~a = ~a\n" (car verdict) (cdr verdict)))
(unless (and (pair? verdicts) (andmap cdr verdicts))
  (eprintf "[verify] native UI verification failed\n")
  (exit 1))
(displayln "[verify] ALL PASS")
