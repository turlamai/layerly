#lang racket/base

;; Synthetic printer — the deterministic device backend. It implements the
;; same snapshot surface as the Bambu bridge so every UI path (queue,
;; heating, layer progress, AMS, finish, pause) is exercisable without
;; hardware. Time advances only through tick! with an explicit now-ms, so
;; tests are reproducible; the live manager drives tick! from a timer
;; thread under its own custodian. Store rows stay immutable: simulation
;; state (simulated layer, display label) lives on the printer, not in the
;; library row.

(require racket/list
         racket/string
         "../store.rkt")

(provide make-fixture
         fixture-tick!
         fixture-enqueue!
         fixture-pause! fixture-resume! fixture-stop!
         fixture-snapshot
         fixture-speed-ref fixture-speed-set!
         printer? printer-state-box printer-job-box)

;; ---- state ------------------------------------------------------------------

(struct printer
  (name                    ; display name (device row)
   device-id               ; library device id
   state-box               ; 'idle | 'heating | 'printing | 'paused
   job-box                 ; current job row (immutable store hasheq) or #f
   label-box               ; display label of the current job
   sim-layer-box           ; simulated layer of the current job
   started-box             ; ms at which the current segment started
   elapsed-box             ; accumulated printing ms (survives pauses)
   speed-box               ; simulated layers per second (demo pace)
   ams-box                 ; list of 4 slot hasheqs
   queue-box               ; pending (job . label) pairs
   clock-box               ; last virtual time seen by tick! (the machine's own clock)
   ) #:transparent)

(define nozzle-target 220)
(define bed-target 100)
(define chamber-target 45)

(define (make-fixture name device-id)
  (printer name
           device-id
           (box 'idle)
           (box #f)
           (box "")
           (box 0)
           (box 0)
           (box 0)
           (box 4)      ; layers/second: 184 layers ≈ 46 s of demo pace
           (box (list (hasheq 'n 1 'type "PETG" 'color-name "黑" 'color-hex "#2b2b2e"
                              'remaining-g 820 'label "820 g")
                      (hasheq 'n 2 'type "PLA" 'color-name "米白" 'color-hex "#d8d3c8"
                              'remaining-g 450 'label "450 g")
                      (hasheq 'n 3 'type "" 'color-name "" 'color-hex ""
                              'remaining-g 0 'label "空")
                      (hasheq 'n 4 'type "" 'color-name "" 'color-hex ""
                              'remaining-g 0 'label "空")))
           (box '())
           (box #f)))

;; The printer's own clock: advanced by every tick!; control calls inside
;; a live session see a fresh value (the manager ticks every 200 ms),
;; tests drive it with virtual times.
(define (pr-now pr)
  (or (unbox (printer-clock-box pr)) (current-inexact-milliseconds)))

(define (fixture-speed-ref pr)
  (unbox (printer-speed-box pr)))

(define (fixture-speed-set! pr v)
  (set-box! (printer-speed-box pr) (max 0.5 (min 1000 v))))

;; ---- queue ------------------------------------------------------------------

;; job is a store print_jobs row (immutable hasheq); label is the display
;; string the device screen shows.
(define (fixture-enqueue! pr job label)
  (define current (unbox (printer-job-box pr)))
  (define q (unbox (printer-queue-box pr)))
  (define seen (cons (and current (hash-ref current 'id))
                     (for/list ([pair (in-list q)]) (hash-ref (car pair) 'id))))
  (if (member (hash-ref job 'id) seen)
      #f ; already queued/running — print-prep is the only dispatch surface
      (begin
        (set-box! (printer-queue-box pr) (append q (list (cons job label))))
        (maybe-start-next! pr (pr-now pr))
        #t)))

(define (fixture-pause! pr)
  (case (unbox (printer-state-box pr))
    [(printing)
     (set-box! (printer-state-box pr) 'paused)
     'paused]
    [else #f]))

(define (fixture-resume! pr)
  (case (unbox (printer-state-box pr))
    [(paused)
     (set-box! (printer-state-box pr) 'printing)
     (set-box! (printer-started-box pr) (pr-now pr))
     'printing]
    [else #f]))

(define (fixture-stop! pr)
  (define job (unbox (printer-job-box pr)))
  (when job
    (job-cancelled! (hash-ref job 'id)))
  (set-box! (printer-job-box pr) #f)
  (set-box! (printer-state-box pr) 'idle)
  (set-box! (printer-elapsed-box pr) 0)
  (set-box! (printer-sim-layer-box pr) 0)
  (maybe-start-next! pr (pr-now pr))
  'idle)

;; ---- simulation -------------------------------------------------------------

(define (start! pr job label now-ms)
  (set-box! (printer-job-box pr) job)
  (set-box! (printer-label-box pr) label)
  (set-box! (printer-sim-layer-box pr) 0)
  (set-box! (printer-state-box pr) 'heating)
  (set-box! (printer-started-box pr) now-ms)
  (set-box! (printer-elapsed-box pr) 0)
  (job-started! (hash-ref job 'id)))

(define (maybe-start-next! pr now-ms)
  (when (and (eq? (unbox (printer-state-box pr)) 'idle)
             (not (unbox (printer-job-box pr))))
    (define q (unbox (printer-queue-box pr)))
    (when (pair? q)
      (define pair (car q))
      (set-box! (printer-queue-box pr) (cdr q))
      (start! pr (car pair) (cdr pair) now-ms))))

;; Advance the machine to now-ms. Pure with respect to wall-clock: every
;; decision derives from the passed time, so tests replay exactly.
(define (fixture-tick! pr now-ms)
  (set-box! (printer-clock-box pr) now-ms)
  (define state (unbox (printer-state-box pr)))
  (case state
    [(heating)
     ;; Heating takes a fixed simulated 3 s, then the job begins.
     (when (>= (- now-ms (unbox (printer-started-box pr))) 3000)
       (set-box! (printer-state-box pr) 'printing)
       (set-box! (printer-started-box pr) now-ms))]
    [(printing)
     (define job (unbox (printer-job-box pr)))
     (when job
       (define speed (unbox (printer-speed-box pr)))
       (define elapsed
         (+ (unbox (printer-elapsed-box pr))
            (- now-ms (unbox (printer-started-box pr)))))
       (set-box! (printer-elapsed-box pr) elapsed)
       (set-box! (printer-started-box pr) now-ms)
       (define total (hash-ref job 'layers 0))
       (define layer (min total (inexact->exact (floor (/ (* elapsed speed) 1000)))))
       (define prev (unbox (printer-sim-layer-box pr)))
       (unless (= layer prev)
         (set-box! (printer-sim-layer-box pr) layer)
         (job-progress! (hash-ref job 'id) layer))
       (when (and (> total 0) (>= layer total))
         ;; Batch piece done: write history, consume from the matched AMS
         ;; slot, return to idle, and pull the next queued job.
         (job-finished! (hash-ref job 'id)
                        (hash-ref job 'minutes 0)
                        (hash-ref job 'grams 0))
         (consume-ams! pr job)
         (set-box! (printer-job-box pr) #f)
         (set-box! (printer-state-box pr) 'idle)
         (set-box! (printer-elapsed-box pr) 0)
         (set-box! (printer-sim-layer-box pr) 0)
         (maybe-start-next! pr now-ms)))]
    [else void]))

(define (consume-ams! pr job)
  (define grams (hash-ref job 'grams 0))
  (define mat (hash-ref job 'material-name ""))
  (when (and (> grams 0) (non-empty-string? mat))
    (set-box! (printer-ams-box pr)
              (for/list ([slot (in-list (unbox (printer-ams-box pr)))])
                (if (string=? (hash-ref slot 'color-name "") (material-color mat))
                    (let ([rest (max 0 (- (hash-ref slot 'remaining-g) grams))])
                      (hash-set* slot
                                 'remaining-g rest
                                 'label (format "~a g" rest)))
                    slot)))))

;; "PETG 黑" / "PLA 米白" — the color name is the trailing token family
;; demos use; match by that token so both name shapes find their slot.
(define (material-color mat)
  (define parts (string-split mat " "))
  (if (> (length parts) 1) (last parts) mat))

;; ---- snapshot ----------------------------------------------------------------

;; The projection the device routes serve to the webview. Same shape the
;; Bambu bridge produces, so screens never know which backend answered.
(define (fixture-snapshot pr now-ms)
  (fixture-tick! pr now-ms)
  (define job (unbox (printer-job-box pr)))
  (define state (unbox (printer-state-box pr)))
  (define speed (unbox (printer-speed-box pr)))
  (define total (if job (hash-ref job 'layers 0) 0))
  (define layer (unbox (printer-sim-layer-box pr)))
  (define printing? (eq? state 'printing))
  (define minutes-left
    (if (and printing? (> speed 0))
        (exact->inexact (/ (- total layer) speed 60))
        0.0))
  (hasheq 'kind "fixture"
          'connected #t
          'state (case state [(heating) "heating"]
                          [(printing) "printing"]
                          [(paused) "paused"]
                          [else "idle"])
          'name (printer-name pr)
          'device-id (printer-device-id pr)
          'nozzle-temp (case state [(idle) 25] [else nozzle-target])
          'bed-temp (case state [(idle) 24] [else bed-target])
          'chamber-temp (case state [(idle) 26] [else chamber-target])
          'fan-percent (if printing? 80 0)
          'ams (unbox (printer-ams-box pr))
          'job (if job
                   (hasheq 'job-id (hash-ref job 'id)
                           'project-id (hash-ref job 'project-id)
                           'name (unbox (printer-label-box pr))
                           'seq (hash-ref job 'seq 1)
                           'total (hash-ref job 'total 1)
                           'layer layer
                           'layers total
                           'percent (if (> total 0) (/ (* layer 100.0) total) 0.0)
                           'minutes-left (exact->inexact minutes-left)
                           'material-name (hash-ref job 'material-name "")
                           'material-hex (hash-ref job 'material-hex ""))
                   #f)
          'queue (map cdr (unbox (printer-queue-box pr)))))
