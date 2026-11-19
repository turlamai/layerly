#lang racket/base

;; Layerly on Glaze — the Racket backend. One define-api-routes form
;; declares every RPC (Racket procedures, the route list and the schema
;; commands all come from the same declaration). Slices live next door:
;; library (store.rkt), device (device/), advisor (ai/). API keys and
;; device access codes stay in Racket and never enter the webview.
;;
;; Run:  pnpm --filter @layerly/desktop build   (once)
;;       raco glaze dev

(require json
         racket/contract
         net/base64
         racket/format
         racket/list
         racket/random
         racket/runtime-path
         racket/string
         glaze/app        ; run-app
         glaze/api        ; GET, POST, streaming-response
         glaze/api-macros ; define-api-routes
         glaze/types      ; GString, GValue…
         "store.rkt"
         "platform.rkt"
         "device/manager.rkt"
         "ai/advisor.rkt"
         "ai/redact.rkt")

;; Keep in sync with package.json and CHANGELOG.md; the release workflow's
;; validate job fails the tag if they disagree.
(define app-version "0.1.0")

(define-runtime-path frontend-dist "../apps/desktop/dist")

;; ---- helpers -----------------------------------------------------------------

(define (jsexpr-args h) ; normalize a JSON object passed as a patch
  (if (hash? h) h (hasheq)))

(define (bytes-b64? v) (or (string? v) (not v)))

(define (job-label job)
  ;; "相机快装板 V4 · 第 3/4 件" — the display string the device screen
  ;; and history rows show.
  (define p (get-project (hash-ref job 'project-id)))
  (define versions (if p (list-versions (hash-ref p 'id)) '()))
  (define version
    (and (pair? versions)
         (findf (lambda (v) (string=? (hash-ref v 'id) (hash-ref job 'version-id "")))
                versions)))
  (format "~a~a · 第 ~a/~a 件"
          (if p (hash-ref p 'name) "作品")
          (if version (format " ~a" (hash-ref version 'label)) "")
          (hash-ref job 'seq 1)
          (hash-ref job 'total 1)))

;; ---- routes ---------------------------------------------------------------------

(define-api-routes api
  ;; health / app
  [(POST "api/health")
   (health)
   (hasheq 'ok #t 'version app-version)]
  [(POST "api/app/info")
   (app-info)
   (hasheq 'name "layerly" 'version app-version)]

  ;; library summary — one round-trip for the dashboard shell
  [(POST "api/library/summary")
   (library-summary)
   (hasheq 'counts (library-counts)
           'device (manager-snapshot))]

  ;; projects
  [(POST "api/projects/list")
   (projects-list)
   (hasheq 'projects (map project-summary (list-projects)))]
  [(POST "api/projects/get")
   (projects-get [id string?])
   (define p (get-project id))
   (if p
       (hasheq 'project p
               'versions (list-versions id)
               'plans (list-plans id)
               'jobs (jobs-for-project id)
               'feedback (list-feedback id))
       (hasheq 'project #f))]
  [(POST "api/projects/create")
   (projects-create [name string?] [brief string? ""]
                    [size-text string? ""] [target-qty integer? 1])
   (create-project! name brief size-text target-qty)]
  [(POST "api/projects/update")
   (projects-update [id string?] [patch hash?])
   (update-project! id (jsexpr-args patch))]
  [(POST "api/projects/delete")
   (projects-delete [id string?])
   (void (delete-project! id))
   (hasheq 'ok #t)]

  ;; versions + model files
  [(POST "api/versions/create")
   (versions-create [project-id string?] [label string?]
                    [note string? ""] [model-file string? ""]
                    [material-name string? ""])
   (create-version! project-id label note model-file material-name)]
  [(POST "api/versions/set-current")
   (versions-set-current [project-id string?] [version-id string?])
   (void (set-current-version! project-id version-id))
   (hasheq 'ok #t)]
  [(POST "api/versions/delete")
   (versions-delete [id string?])
   (void (delete-version! id))
   (hasheq 'ok #t)]

  ;; slice plans
  [(POST "api/plans/create")
   (plans-create [project-id string?] [version-id string?] [plan hash?])
   (create-plan! project-id version-id (jsexpr-args plan))]
  [(POST "api/plans/set-recommended")
   (plans-set-recommended [id string?])
   (void (set-recommended-plan! id))
   (hasheq 'ok #t)]
  [(POST "api/plans/delete")
   (plans-delete [id string?])
   (void (delete-plan! id))
   (hasheq 'ok #t)]

  ;; print jobs (history + queue rows)
  [(POST "api/jobs/list")
   (jobs-list [limit integer? 200])
   (hasheq 'jobs (list-jobs limit))]
  [(POST "api/jobs/get")
   (jobs-get [id string?])
   (or (get-job id) (hasheq))]
  [(POST "api/jobs/create")
   (jobs-create [project-id string?] [version-id string? ""] [plan-id string? ""]
                [seq integer? 1] [total integer? 1] [layers integer? 0]
                [minutes integer? 0] [grams (lambda (v) (real? v)) 0]
                [material-name string? ""] [material-hex string? ""])
   (create-job! project-id version-id plan-id (or (manager-device-id) "")
                (hash-ref (manager-snapshot) 'name "")
                seq total layers minutes grams material-name material-hex)]
  [(POST "api/jobs/queue")
   (jobs-queue [job-id string?])
   ;; The dispatch boundary: only the print-prep confirm page sends this.
   ;; The backend resolves the display label and the version's model file
   ;; itself; no row-level inline dispatch exists anywhere in the UI.
   (define job (get-job job-id))
   (unless job (raise (exn:fail "job not found" (current-continuation-marks))))
   (define model-file
     (let ([v (and (non-empty-string? (hash-ref job 'version-id ""))
                   (findf (lambda (x) (string=? (hash-ref x 'id) (hash-ref job 'version-id)))
                          (list-versions (hash-ref job 'project-id))))])
       (if v (hash-ref v 'model-file "") "")))
   (hasheq 'queued (manager-enqueue! (hash-set job 'model-file model-file)
                                     (job-label job))
           'device (manager-snapshot))]

  ;; feedback (实物反馈归档)
  [(POST "api/feedback/create")
   (feedback-create [project-id string?] [job-id string? ""]
                    [kind string? "note"] [text string? ""] [data-b64 bytes-b64? #f])
   (define photo-file
     (and data-b64
          (string? data-b64)
          (not (string=? data-b64 ""))
          (save-photo-file! project-id
                            (format "~a.~a"
                                    (~a (current-inexact-milliseconds) #:precision 0)
                                    "png")
                            (base64-decode data-b64))))
   (create-feedback! project-id job-id kind text (or photo-file ""))]

  ;; materials
  [(POST "api/materials/list")
   (materials-list)
   (hasheq 'materials (list-materials))]
  [(POST "api/materials/create")
   (materials-create [material hash?])
   (create-material! (jsexpr-args material))]
  [(POST "api/materials/update")
   (materials-update [id string?] [patch hash?])
   (update-material! id (jsexpr-args patch))]
  [(POST "api/materials/delete")
   (materials-delete [id string?])
   (void (delete-material! id))
   (hasheq 'ok #t)]

  ;; shopping list + purchases (清单不会自动下单，下单由用户完成)
  [(POST "api/shopping/list")
   (shopping-list)
   (hasheq 'items (list-shopping))]
  [(POST "api/shopping/create")
   (shopping-create [name string?] [qty integer? 1]
                    [price (lambda (v) (real? v)) 0] [source string? "manual"])
   (create-shopping-item! name qty price source)]
  [(POST "api/shopping/delete")
   (shopping-delete [id string?])
   (void (delete-shopping-item! id))
   (hasheq 'ok #t)]
  [(POST "api/purchases/list")
   (purchases-list)
   (hasheq 'purchases (list-purchases))]
  [(POST "api/purchases/create")
   (purchases-create [name string?] [qty integer? 1] [price (lambda (v) (real? v)) 0])
   (create-purchase! name qty price)]
  [(POST "api/purchases/arrive")
   (purchases-arrive [id string?])
   (or (purchase-arrived! id) (hasheq))]

  ;; files (models / photos archived as-is; no real slicing in v1)
  [(POST "api/files/save-model")
   (files-save-model [project-id string?] [filename string?] [data-b64 string?])
   (hasheq 'path (save-model-file! project-id filename (base64-decode data-b64)))]
  [(POST "api/files/save-photo")
   (files-save-photo [project-id string?] [filename string?] [data-b64 string?])
   (hasheq 'path (save-photo-file! project-id filename (base64-decode data-b64)))]

  ;; demo seed — first-run sample workbench, refuses to merge into data
  [(POST "api/demo/seed")
   (demo-seed)
   (seed-demo!)
   (library-summary)]

  ;; device
  [(POST "api/device/state")
   (device-state)
   (manager-snapshot)]
  [(POST "api/device/list")
   (device-list)
   (hasheq 'devices (list-devices))]
  [(POST "api/device/create")
   (device-create [name string?] [model string? ""] [host string? ""]
                  [serial string? ""] [access-code string? ""]
                  [kind string? "bambu"])
   ;; "demo" kind registers the synthetic fixture printer.
   (define kind* (if (string=? kind "demo") "fixture" kind))
   (define d (create-device! name model host serial access-code kind*))
   (define snap (manager-connect! (hash-ref d 'id)))
   (void (settings-set! "last-device" (hash-ref d 'id)))
   (hasheq 'device d 'snapshot snap)]
  [(POST "api/device/update")
   (device-update [id string?] [patch hash?])
   (update-device! id (jsexpr-args patch))]
  [(POST "api/device/delete")
   (device-delete [id string?])
   (void (delete-device! id))
   (hasheq 'ok #t)]
  [(POST "api/device/connect")
   (device-connect [id string?])
   (define snap (manager-connect! id))
   (void (settings-set! "last-device" id))
   snap]
  [(POST "api/device/disconnect")
   (device-disconnect)
   (void (manager-disconnect!))
   (manager-snapshot)]
  [(POST "api/device/pause")
   (device-pause)
   (hasheq 'state (manager-pause!) 'snapshot (manager-snapshot))]
  [(POST "api/device/resume")
   (device-resume)
   (hasheq 'state (manager-resume!) 'snapshot (manager-snapshot))]
  [(POST "api/device/stop")
   (device-stop)
   (hasheq 'state (manager-stop!) 'snapshot (manager-snapshot))]
  [(POST "api/device/speed")
   (device-speed [layers-per-second (lambda (v) (real? v)) 4])
   ;; fixture demo pace only; a real device ignores this
   (manager-set-speed! layers-per-second)
   (manager-snapshot)]

  ;; advisor
  [(POST "api/advisor/settings-view")
   (advisor-settings-view)
   (settings-view)]
  [(POST "api/advisor/settings-save")
   (advisor-settings-save [patch hash?])
   (settings-save! (jsexpr-args patch))]
  [(POST "api/advisor/conversations/list")
   (advisor-conversations-list [project-id string? ""])
   (hasheq 'conversations (list-conversations
                           (if (string=? project-id "") #f project-id)))]
  [(POST "api/advisor/conversations/create")
   (advisor-conversations-create [scope string? "advisor"]
                                 [project-id string? ""]
                                 [title string? "新对话"])
   (create-conversation! scope project-id title)]
  [(POST "api/advisor/conversations/delete")
   (advisor-conversations-delete [id string?])
   (void (delete-conversation! id))
   (hasheq 'ok #t)]
  [(POST "api/advisor/messages")
   (advisor-messages [conversation-id string?])
   (hasheq 'messages (list-messages conversation-id))]
  [(POST "api/advisor/redact-preview")
   (advisor-redact-preview [text string?])
   (redact-preview text)]

  ;; advisor chat — the one streaming route; family line protocol:
  ;; first line `OK`, then one NDJSON event per line
  ;; ({type:"delta"|"done"|"error"}), or `ERR <status> <message>` before
  ;; the stream opens.
  [(POST "api/advisor/chat")
   (advisor-chat [conversation-id string?] [message string?]
                 [refs (lambda (v) (list? v)) '()])
   (streaming-response
    (lambda (out)
      (define (emit event)
        (fprintf out "~a\n" (jsexpr->string event))
        (flush-output out))
      (define refs* (if (list? refs) refs '()))
      (cond
        [(not (advisor-configured?))
         (displayln "ERR 400 advisor-not-configured 设置 → AI 配置里先填 API key" out)
         (flush-output out)]
        [else
         (displayln "OK" out)
         (flush-output out)
         (define user-msg (add-message! conversation-id "user" message refs* #f))
         (emit (hasheq 'type "start" 'message-id (hash-ref user-msg 'id)))
         (define result
           (with-handlers
               ([exn:fail?
                 (lambda (e)
                   (emit (hasheq 'type "error" 'message (exn-message e)))
                   #f)])
             (stream-advisor-reply!
              conversation-id message refs*
              (lambda (delta) (emit (hasheq 'type "delta" 'text delta)))
              (lambda (clean confirm)
                (define advisor-msg
                  (add-message! conversation-id "advisor" clean refs* confirm))
                (emit (hasheq 'type "done"
                              'message-id (hash-ref advisor-msg 'id)
                              'message advisor-msg))
                #t))))
         ;; A failed stream leaves the turn unanswered; nothing else to
         ;; roll back — the user message is already persisted honestly.
         result])))]

  ;; settings (theme / language / onboarding state)
  [(POST "api/settings/get")
   (settings-get-rpc [key string?])
   (hasheq 'key key 'value (settings-get key))]
  [(POST "api/settings/set")
   (settings-set-rpc [key string?] [value any/c])
   (void (settings-set! key value))
   (hasheq 'ok #t)])

(provide api)

(module+ main
  (void (store-init!))
  (manager-init!)
  (define transport
    (or (let ([v (getenv "LAYERLY_TRANSPORT")])
          (and (member v '("native" "http")) (string->symbol v)))
        'native))
  (run-app
   #:public-dir frontend-dist
   #:api api
   #:transport transport
   #:title "Layerly"
   #:width 1280
   #:height 820
   #:app-id "layerly"
   #:window-state #t
   #:current-version app-version))
