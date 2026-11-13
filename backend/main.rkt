#lang racket/base

;; Layerly on Glaze — the Racket backend. Serves the built React frontend
;; and the /api surface. Planned slices: project library, material
;; inventory, the Bambu device bridge (printer + AMS state and print
;; history), and the LLM proxy for advisor roles — API keys stay in
;; Racket and never enter the webview.
;;
;; Run:  pnpm --filter @layerly/desktop build   (once)
;;       raco glaze dev

(require glaze/app        ; run-app, current-app-version
         glaze/api        ; GET, POST
         glaze/api-macros ; define-api-routes
         glaze/types      ; GString
         racket/runtime-path)

;; Keep in sync with package.json and CHANGELOG.md; the release workflow's
;; validate job fails the tag if they disagree.
(define app-version "0.1.0")

(define-runtime-path frontend-dist "../apps/desktop/dist")

(define-api-routes api
  [(GET "api/health")
   (health)
   (hasheq 'ok #t 'version app-version)]

  [(POST "api/app/info")
   (app-info)
   (hasheq 'name "layerly" 'version app-version)])

(provide api)

(module+ main
  (run-app
   #:public-dir frontend-dist
   #:api api
   #:title "Layerly"
   #:width 1280
   #:height 820
   #:app-id "layerly"
   #:window-state #t))
