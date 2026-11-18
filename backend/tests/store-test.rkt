#lang racket/base

;; Store unit tests: schema init, CRUD round-trips, lifecycle transitions,
;; device access-code hygiene and the demo seed. Runs against a temp data
;; dir (LAYERLY_DATA_DIR) so it never touches a real workbench.

(require rackunit
         "../store.rkt")

;; Fresh sandbox per run: the temp dir is set by the caller (see the run
;; recipe in tests/run-all.rkt); this file only asserts on what the store
;; actually did.
(store-fresh!)
(store-init!)

(check-equal? (length (list-projects)) 0 "starts empty")

(seed-demo!)
(define ps (list-projects))
(check-equal? (length ps) 6 "six demo projects")

(define live (filter (lambda (p) (string=? (hash-ref p 'status) "printing")) ps))
(check-equal? (length live) 1 "one printing project")
(define p1 (get-project (hash-ref (car live) 'id)))
(check-equal? (hash-ref (hash-ref p1 'job) 'layer) 114 "live job at layer 114")
(check-equal? (hash-ref (hash-ref p1 'job) 'layers) 184)
(check-equal? (hash-ref p1 'version-label) "V4")

(define plans (list-plans (hash-ref p1 'id)))
(check-equal? (length plans) 2)
(check-true (hash-ref (car plans) 'recommended) "plan A sorts first as recommended")
(check-equal? (length (hash-ref (car plans) 'parts)) 2)

(check-equal? (length (list-materials)) 5)
(check-equal? (length (list-shopping)) 3)
(check-equal? (length (list-purchases)) 2)
(check-equal? (length (list-jobs)) 9)

(define counts (library-counts))
(check-equal? (hash-ref counts 'done) 2 "done count matches the prototype filter row")
(check-equal? (hash-ref counts 'failed) 1)
(check-equal? (hash-ref counts 'printing) 1)
(check-true (> (hash-ref counts 'stock-g) 0) "stock totals from materials")

;; conversations survive with refs and confirm cards intact
(define convs (list-conversations))
(check-equal? (length convs) 1)
(define msgs (list-messages (hash-ref (car convs) 'id)))
(check-equal? (length msgs) 5)
(define confirms (filter (lambda (m) (hash-ref m 'confirm #f)) msgs))
(check-equal? (length confirms) 1)
(check-equal? (hash-ref (hash-ref (car confirms) 'confirm) 'action)
              "downgrade-material" "confirm card action survives the roundtrip")
(check-equal? (hash-ref (car confirms) 'refs) '())

;; settings round-trip
(settings-set! "theme" "dark")
(check-equal? (settings-get "theme") "dark")
(settings-set! "theme" "light")
(check-equal? (settings-get "theme") "light")
(check-false (settings-get "missing-key") "missing key returns default")

;; device access codes never cross the public projection
(define dev (create-device! "P1S" "P1S" "192.168.1.51" "SERIAL123" "access-code-x" "bambu"))
(check-false (hash-has-key? dev 'access-code) "access code stripped from projection")
(check-true (hash-ref dev 'has-access-code))
(define dev2 (update-device! (hash-ref dev 'id) (hasheq 'access-code "__SAVED__")))
(check-true (hash-ref dev2 'has-access-code) "sentinel round-trip does not clear the stored code")
(delete-device! (hash-ref dev 'id))

;; first version becomes the current version; delete cascades
(define p (create-project! "test" "" "" 1))
(define v (create-version! (hash-ref p 'id) "V1" "" "" ""))
(check-equal? (hash-ref (get-project (hash-ref p 'id)) 'current-version-id)
              (hash-ref v 'id) "first version becomes current")
(define v2 (create-version! (hash-ref p 'id) "V2" "" "" ""))
(set-current-version! (hash-ref p 'id) (hash-ref v2 'id))
(delete-version! (hash-ref v2 'id))
(check-equal? (hash-ref (get-project (hash-ref p 'id)) 'current-version-id)
              (hash-ref v 'id) "current falls back after deleting the current version")
(delete-project! (hash-ref p 'id))
(check-equal? (length (list-projects)) 6 "delete removes the project")

;; job lifecycle drives project status
(define pj (create-project! "lifecycle" "" "" 1))
(define pid (hash-ref pj 'id))
(define j (create-job! pid "" "" "" "" 1 1 100 60 10 "PLA" "#ffffff"))
(check-equal? (hash-ref (get-job (hash-ref j 'id)) 'status) "queued")
(check-equal? (hash-ref (get-project pid) 'status) "printing" "queued job flips project to printing")
(job-started! (hash-ref j 'id))
(job-progress! (hash-ref j 'id) 42)
(check-equal? (hash-ref (get-job (hash-ref j 'id)) 'layer) 42)
(job-finished! (hash-ref j 'id) 60 10)
(check-equal? (hash-ref (get-job (hash-ref j 'id)) 'status) "done")
(check-equal? (hash-ref (get-project pid) 'status) "done" "finished batch flips project to done")
(define j2 (create-job! pid "" "" "" "" 2 1 100 60 10 "PLA" "#ffffff"))
(job-cancelled! (hash-ref j2 'id))
(check-equal? (hash-ref (get-project pid) 'status) "design" "cancelled batch leaves project in design")
(delete-project! pid)

(printf "store-test: all checks passed\n")
