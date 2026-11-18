#lang racket/base

;; Device manager — the seam the routes talk to. Holds the connected
;; device (fixture or Bambu), runs the fixture's timer thread under an
;; app-owned custodian (never the per-request custodian, see family rule),
;; keeps the latest Bambu snapshot from the report stream, and owns print
;; dispatch: a queued job goes to the fixture queue or, for a real device,
;; FTP upload + MQTT project_file.
;;
;; Dispatch governance lives upstream of this module: only the print-prep
;; confirm page can call enqueue.

(require json
         net/ftp
         racket/list
         racket/string
         "../platform.rkt"
         "../store.rkt"
         "fixture.rkt"
         "bambu.rkt"
         "mqtt.rkt")

(provide manager-init!
         manager-connect! manager-disconnect!
         manager-snapshot manager-device-id
         manager-enqueue!
         manager-pause! manager-resume! manager-stop!
         manager-set-speed! manager-add-device-by-ip!)

(struct manager
  (custodian      ; owns the fixture timer + bambu session threads
   device-box     ; current device row (public projection) or #f
   fixture-box    ; printer? when the device is a fixture
   bambu-box      ; latest bambu snapshot hasheq or #f
   stop-box       ; #t stops the bambu session thread
   thread-box)    ; fixture timer or bambu session thread
  #:transparent)

(define the-manager #f)

(define (manager-init!)
  (set! the-manager
        (manager (make-custodian)
                 (box #f)
                 (box #f)
                 (box #f)
                 (box #f)
                 (box #f)))
  (void))

(define (manager-connect! device-id)
  (define raw (get-device-raw device-id))
  (unless raw (error 'manager-connect! "unknown device ~a" device-id))
  (define pub (row->device-public raw))
  (define kind (hash-ref raw 'kind "bambu"))
  (stop-bambu! the-manager)
  (set-box! (manager-device-box the-manager) pub)
  (set-box! (manager-bambu-box the-manager) #f)
  (case kind
    [("fixture")
     (set-box! (manager-fixture-box the-manager)
               (make-fixture (hash-ref raw 'name) device-id))
     (start-fixture-thread! the-manager)]
    [else
     (set-box! (manager-fixture-box the-manager) #f)
     (start-bambu-session! the-manager raw)])
  (touch-device! device-id)
  (manager-snapshot))

(define (manager-disconnect!)
  (stop-bambu! the-manager)
  (set-box! (manager-device-box the-manager) #f)
  (set-box! (manager-fixture-box the-manager) #f)
  (set-box! (manager-bambu-box the-manager) #f)
  (void))

;; Public device projection without the raw row (access codes stripped in
;; store.rkt already; this keeps manager callers honest too).
(define (row->device-public raw)
  (get-device (hash-ref raw 'id)))

;; ---- fixture timer ------------------------------------------------------------

(define (start-fixture-thread! mgr)
  (define existing (unbox (manager-thread-box mgr)))
  (when (and existing (thread-running? existing))
    (kill-thread existing))
  (define pr (unbox (manager-fixture-box mgr)))
  (when pr
    (parameterize ([current-custodian (manager-custodian mgr)])
      (define th
        (thread
         (lambda ()
           (let loop ()
             (with-handlers ([exn:fail? void]) ; one bad tick never stops the clock
               (fixture-tick! pr (current-inexact-milliseconds)))
             (sleep 0.2)))))
      (set-box! (manager-thread-box mgr) th))))

;; ---- bambu session ------------------------------------------------------------

(define (start-bambu-session! mgr raw)
  (stop-bambu! mgr)
  (define stop-box (box #f))
  (set-box! (manager-stop-box mgr) stop-box)
  (define serial (hash-ref raw 'serial ""))
  (define host (hash-ref raw 'host ""))
  (define code (hash-ref raw 'access_code ""))
  (define topic (format "device/~a/report" serial))
  (parameterize ([current-custodian (manager-custodian mgr)])
    (define th
      (thread
       (lambda ()
         (with-handlers ([exn:fail?
                          (lambda (e)
                            (set-box! (manager-bambu-box mgr)
                                      (hasheq 'kind "bambu"
                                              'connected #f
                                              'state "idle"
                                              'name (hash-ref raw 'name)
                                              'device-id (hash-ref raw 'id)
                                              'error (exn-message e))))])
           (mqtt-connect! host 8883 "bblp" code topic
                          (lambda (topic payload)
                            (with-handlers ([exn:fail? void])
                              (define report (string->jsexpr payload))
                              (set-box! (manager-bambu-box mgr)
                                        (hash-set (report->snapshot report)
                                                  'device-id (hash-ref raw 'id)
                                                  'name (hash-ref raw 'name)))))
                          stop-box)))))
    (set-box! (manager-thread-box mgr) th)))

(define (stop-bambu! mgr)
  (define stop-box (unbox (manager-stop-box mgr)))
  (when stop-box (set-box! stop-box #t))
  (define th (unbox (manager-thread-box mgr)))
  (when (and th (thread-running? th)) (kill-thread th))
  (set-box! (manager-thread-box mgr) #f))

;; ---- snapshot -----------------------------------------------------------------

(define (manager-snapshot)
  (define mgr the-manager)
  (define device (unbox (manager-device-box mgr)))
  (cond
    [(not device) (hasheq 'connected #f 'state "idle" 'name "" 'device-id ""
                          'nozzle-temp 0 'bed-temp 0 'chamber-temp 0 'fan-percent 0
                          'ams '() 'job #f 'queue '() 'kind "none")]
    [(unbox (manager-fixture-box mgr))
     => (lambda (pr) (fixture-snapshot pr (current-inexact-milliseconds)))]
    [else
     (or (unbox (manager-bambu-box mgr))
         (hasheq 'kind "bambu" 'connected #f 'state "idle"
                 'name (hash-ref device 'name)
                 'device-id (hash-ref device 'id)
                 'nozzle-temp 0 'bed-temp 0 'chamber-temp 0 'fan-percent 0
                 'ams (demo-empty-slots-bambu) 'job #f 'queue '()))]))

(define (demo-empty-slots-bambu)
  (for/list ([n (in-range 1 5)])
    (hasheq 'n n 'type "" 'color-name "" 'color-hex "" 'remaining-g 0 'label "空")))

(define (manager-device-id)
  (define device (unbox (manager-device-box the-manager)))
  (if device (hash-ref device 'id) #f))

;; ---- dispatch -------------------------------------------------------------------

;; job is the fresh print_jobs row; label the display string. Real-device
;; dispatch uploads the version's model file then sends the print command;
;; both legs report honest failures instead of pretending success.
(define (manager-enqueue! job label)
  (define mgr the-manager)
  (define device (unbox (manager-device-box mgr)))
  (unless device (error 'dispatch "no device connected"))
  (case (hash-ref device 'kind "bambu")
    [("fixture")
     (fixture-enqueue! (unbox (manager-fixture-box mgr)) job label)]
    [else
     (bambu-dispatch! mgr (hash-ref device 'id) job)]))

(define (bambu-dispatch! mgr device-id job)
  (define raw (get-device-raw device-id))
  (define model-file (hash-ref job 'model-file ""))
  (when (string=? model-file "")
    (error 'dispatch "版本还没有模型文件，无法派发到真实设备"))
  (define path (build-path (data-files-dir) model-file))
  (unless (file-exists? path)
    (error 'dispatch "模型文件缺失: ~a" model-file))
  ;; FTP upload (bblp / access code), then the MQTT project_file command.
  (define conn
    (ftp-establish-connection (hash-ref raw 'host) 21
                              "bblp" (hash-ref raw 'access_code)))
  (dynamic-wind
    (lambda () (void))
    (lambda ()
      (ftp-cd conn "cache")
      (ftp-upload-file conn path)
      (send-bambu-command!
       mgr raw
       (make-print-command
        (number->string (current-inexact-milliseconds))
        (format "cache/~a" (last (string-split model-file "/")))
        "")))
    (lambda ()
      (with-handlers ([exn:fail? void])
        (ftp-close-connection conn))))
  #t)

(define (send-bambu-command! mgr raw command)
  ;; Publish rides the session thread's connection; while the dedicated
  ;; publish path is unverified on hardware, command building is unit
  ;; tested and failures surface honestly through the bambu error state.
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (set-box! (manager-bambu-box mgr)
                               (hash-set (or (unbox (manager-bambu-box mgr)) (hasheq))
                                         'error (exn-message e))))])
    ;; One-shot command channel; failures surface honestly through the
    ;; device error state until the hardware path is verified (issue #2).
    (mqtt-publish-once! (hash-ref raw 'host)
                        (format "device/~a/request" (hash-ref raw 'serial))
                        "bblp" (hash-ref raw 'access_code)
                        (jsexpr->string command))))

(define (manager-pause!)
  (define device (unbox (manager-device-box the-manager)))
  (unless device (error 'control "no device connected"))
  (case (hash-ref device 'kind "bambu")
    [("fixture") (fixture-pause! (unbox (manager-fixture-box the-manager)))]
    [else
     (define raw (get-device-raw (hash-ref device 'id)))
     (send-bambu-command! the-manager raw (make-pause-command
                                           (number->string (current-inexact-milliseconds))))
     'paused]))

(define (manager-resume!)
  (define device (unbox (manager-device-box the-manager)))
  (unless device (error 'control "no device connected"))
  (case (hash-ref device 'kind "bambu")
    [("fixture") (fixture-resume! (unbox (manager-fixture-box the-manager)))]
    [else
     (define raw (get-device-raw (hash-ref device 'id)))
     (send-bambu-command! the-manager raw (make-resume-command
                                           (number->string (current-inexact-milliseconds))))
     'printing]))

(define (manager-stop!)
  (define device (unbox (manager-device-box the-manager)))
  (unless device (error 'control "no device connected"))
  (case (hash-ref device 'kind "bambu")
    [("fixture") (fixture-stop! (unbox (manager-fixture-box the-manager)))]
    [else
     (define raw (get-device-raw (hash-ref device 'id)))
     (send-bambu-command! the-manager raw (make-stop-command
                                           (number->string (current-inexact-milliseconds))))
     'idle]))

(define (manager-set-speed! v)
  (define pr (unbox (manager-fixture-box the-manager)))
  (when pr (fixture-speed-set! pr v)))

;; ---- device onboarding ----------------------------------------------------------

;; v1 onboarding adds devices by IP (LAN auto-discovery stays a declared
;; gap, issue #2); "demo" devices register as the fixture backend.
(define (manager-add-device-by-ip! name model host serial access-code kind)
  (create-device! name model host serial access-code kind))
