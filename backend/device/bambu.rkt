#lang racket/base

;; Bambu Lab LAN bridge. Prints are LAN-only local-first: MQTT over TLS on
;; :8883 (username bblp, password = device access code) for state and
;; commands, plain FTP on :21 for file transfer. The projection and the
;; command builders are pure and unit tested.
;;
;; Honesty note (issue #2): the projection/command shapes follow the
;; public LAN protocol but the full session path is unverified on real
;; hardware — the fixture backend covers every UI path until then.

(require json
         racket/format
         racket/list
         racket/string)

(provide report->snapshot
         make-print-command make-pause-command make-resume-command
         make-stop-command
         state->snapshot-state)

;; ---- report → snapshot --------------------------------------------------------

;; Bambu report JSON: {"print": {...}, ...}. Map the fields the UI shows;
;; anything unknown falls back to honest defaults instead of guessing.
(define (report->snapshot report-json)
  (define print (hash-ref report-json 'print (hasheq)))
  (hasheq 'kind "bambu"
          'connected #t
          'state (state->snapshot-state (hash-ref print 'gcode_state ""))
          'name (hash-ref print 'printer_name "")
          'device-id ""
          'nozzle-temp (num-or (hash-ref print 'nozzle_temper #f) 0)
          'bed-temp (num-or (hash-ref print 'bed_temper #f) 0)
          'chamber-temp (num-or (hash-ref print 'chamber_temper #f) 0)
          'fan-percent (num-or (hash-ref print 'cooling_fan_speed #f) 0)
          'ams (ams->slots (hash-ref print 'ams #f))
          'job (print->job print)
          'queue '()))

(define (num-or v default)
  (cond [(real? v) (exact->inexact v)]
        [(string? v) (or (string->number v) default)]
        [else default]))

;; gcode_state → the shared snapshot states. Family values are honest:
;; an unknown state maps to "idle" rather than an invented one.
(define (state->snapshot-state s)
  (case s
    [("RUNNING" "SLICING" "PREPARE") "printing"]
    [("PAUSE") "paused"]
    [else "idle"]))

(define (print->job print)
  (define state (hash-ref print 'gcode_state ""))
  (define total (num-or (hash-ref print 'total_layer_num #f) 0))
  (define layer (num-or (hash-ref print 'layer_num #f) 0))
  (define remain (num-or (hash-ref print 'mc_remaining_time #f) 0))
  (define task (hash-ref print 'task_name ""))
  (if (or (string=? task "") (string=? state "IDLE"))
      #f
      (hasheq 'job-id (hash-ref print 'task_id "")
              'project-id ""
              'name task
              'seq 1 'total 1
              'layer (inexact->exact layer)
              'layers (inexact->exact total)
              'percent (num-or (hash-ref print 'print_percent #f)
                               (if (> total 0) (/ (* layer 100.0) total) 0))
              'minutes-left remain
              'material-name ""
              'material-hex "")))

;; AMS units → the shared slot shape. Real devices report remaining
;; filament as a percent of the spool, so the slot label is a percent —
;; never a made-up gram figure.
(define (ams->slots ams)
  (define units (hash-ref (or ams (hasheq)) 'ams '()))
  (define slots
    ;; in-indexed yields (element index) — element first. Never a parallel
    ;; in-naturals here: in for* an unbounded inner clause nests forever.
    (for*/list ([unit (in-list units)]
                [(tray i) (in-indexed (in-list (hash-ref unit 'tray '())))])
      (define type (hash-ref tray 'tray_type ""))
      (define color (hash-ref tray 'tray_color ""))
      (define remain (num-or (hash-ref tray 'remain #f) 0))
      (if (or (string=? type "") (string=? type "empty"))
          (hasheq 'n (add1 i) 'type "" 'color-name "" 'color-hex ""
                  'remaining-g 0 'label "空")
          (hasheq 'n (add1 i)
                  'type type
                  'color-name ""
                  'color-hex (color->hex color)
                  'remaining-g 0
                  'label (format "~a%" (inexact->exact remain))))))
  (if (null? slots) (demo-empty-slots) slots))

(define (demo-empty-slots)
  (for/list ([n (in-range 1 5)])
    (hasheq 'n n 'type "" 'color-name "" 'color-hex "" 'remaining-g 0 'label "空")))

;; Bambu reports colors as 8-hex RRGGBBAA; the UI wants #RRGGBB.
(define (color->hex c)
  (if (and (string? c) (>= (string-length c) 6))
      (string-append "#" (string-upcase (substring c 0 6)))
      ""))

;; ---- command builders ------------------------------------------------------------

(define (next-sequence-id!)
  (~a (current-inexact-milliseconds) #:precision 0))

;; Print a file already uploaded to the printer (FTP root of the gcode
;; dir); url/md5 come from the upload step in manager dispatch.
(define (make-print-command seq-id path md5)
  (hasheq 'print (hasheq 'sequence_id seq-id
                         'command "project_file"
                         'param "Metadata/plate_1.gcode"
                         'url path
                         'md5 md5
                         'bed_leveling #t
                         'flow_cali #f
                         'vibration_cali #t
                         'layer_inspect #t
                         'use_ams #t
                         'timelapse #f)))

(define (make-pause-command seq-id)
  (hasheq 'print (hasheq 'sequence_id seq-id 'command "pause")))

(define (make-resume-command seq-id)
  (hasheq 'print (hasheq 'sequence_id seq-id 'command "resume")))

(define (make-stop-command seq-id)
  (hasheq 'print (hasheq 'sequence_id seq-id 'command "stop")))
