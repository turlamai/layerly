#lang racket/base

;; Device layer tests:
;;  - fixture printer: the full lifecycle driven by explicit ticks
;;    (enqueue → heating → printing → layer progress → finish → queue),
;;    pause/resume/stop and double-dispatch rejection;
;;  - MQTT wire format: remaining-length round-trip and packet decoders;
;;  - Bambu projection: report JSON → the shared snapshot shape, and the
;;    print/pause/resume/stop command builders.

(require json
         rackunit
         "../store.rkt"
         "../device/fixture.rkt"
         "../device/mqtt.rkt"
         "../device/bambu.rkt")

;; ---- fixture lifecycle ------------------------------------------------------

(store-fresh!)
(store-init!)
(define dev (create-device! "Fixture One" "X1 Carbon" "" "" "" "fixture"))
(define pr (make-fixture "Fixture One" (hash-ref dev 'id)))
(fixture-tick! pr 0) ; establish the virtual clock before any control call
(check-equal? (hash-ref (fixture-snapshot pr 0) 'state) "idle")
(check-equal? (hash-ref (fixture-snapshot pr 0) 'connected) #t)
(check-equal? (length (hash-ref (fixture-snapshot pr 0) 'ams)) 4)

;; a two-piece queue with different projects
(define pj1 (create-project! "打印件甲" "" "" 1))
(define job1 (create-job! (hash-ref pj1 'id) "" "" (hash-ref dev 'id) "Fixture One"
                          1 2 184 140 44 "PETG 黑" "#2b2b2e"))
(define pj2 (create-project! "打印件乙" "" "" 1))
(define job2 (create-job! (hash-ref pj2 'id) "" "" (hash-ref dev 'id) "Fixture One"
                          1 1 92 65 21 "PLA 米白" "#d8d3c8"))

(check-true (fixture-enqueue! pr job1 "打印件甲 V1 · 第 1/2 件"))
(check-false (fixture-enqueue! pr job1 "打印件甲 V1 · 第 1/2 件") "double dispatch rejected")
(check-true (fixture-enqueue! pr job2 "打印件乙 V1"))

(check-equal? (hash-ref (fixture-snapshot pr 0) 'state) "heating" "first job starts heating")
(check-equal? (hash-ref (fixture-snapshot pr 1000) 'state) "heating")
(check-equal? (hash-ref (fixture-snapshot pr 3200) 'state) "printing" "3 s heatup then printing")

;; speed 4 layers/s: at 3.2s heatup + 10s print = 40 layers
(check-equal? (hash-ref (hash-ref (fixture-snapshot pr 13200) 'job) 'layer) 40)
(check-equal? (hash-ref (get-job (hash-ref job1 'id)) 'layer) 40 "progress persisted")

;; pause freezes time; resume continues from the accumulated print time
(fixture-snapshot pr 23200) ; final tick to the pause boundary: 20 s printed
(fixture-pause! pr)
(check-equal? (hash-ref (fixture-snapshot pr 33200) 'state) "paused")
(check-equal? (hash-ref (hash-ref (fixture-snapshot pr 33200) 'job) 'layer) 80 "no progress while paused")
(fixture-resume! pr)
(check-equal? (hash-ref (hash-ref (fixture-snapshot pr 44450) 'job) 'layer) 125
              "20 s frozen time preserved; resume prints 11.25 s more = 125 layers")

;; run to completion: heatup 3.2 s + 46 s of printing, minus nothing (the
;; pause froze the wall clock but the machine accumulated 20 s already)
(check-equal? (hash-ref (hash-ref (fixture-snapshot pr 52000) 'job) 'layer) 155
              "20 s paused-time preserved; 38.8 s printed = 155 layers")
(check-equal? (hash-ref (fixture-snapshot pr 59200) 'state) "heating" "job 1 done at 59.2 s, machine pulls job 2")
(define finished (get-job (hash-ref job1 'id)))
(check-equal? (hash-ref finished 'status) "done")
(check-equal? (hash-ref finished 'grams) 44.0 "REAL column round-trips inexact")
(check-equal? (hash-ref (get-project (hash-ref pj1 'id)) 'status) "slicing"
              "piece 1/2 done: the batch awaits the next dispatch, so slicing")

;; the second job runs next, then the AMS slot reflects the consumed grams
(check-equal? (hash-ref (fixture-snapshot pr 60000) 'state) "heating" "job 2 starts")
(fixture-snapshot pr 70000) ; heatup elapsed; printing runs from 70 s
(check-equal? (hash-ref (fixture-snapshot pr 120000) 'state) "idle" "all queue drained")
(check-equal? (hash-ref (get-job (hash-ref job2 'id)) 'status) "done")
(check-equal? (hash-ref (get-project (hash-ref pj2 'id)) 'status) "done")
(define slot1 (car (filter (lambda (s) (= (hash-ref s 'n) 1)) (hash-ref (fixture-snapshot pr 120000) 'ams))))
(check-equal? (hash-ref slot1 'remaining-g) 776.0 "PETG slot consumed 44 g")

;; stop cancels the current job
(define pj3 (create-project! "打印件丙" "" "" 1))
(define job3 (create-job! (hash-ref pj3 'id) "" "" (hash-ref dev 'id) "Fixture One"
                          1 1 100 60 10 "PETG 黑" "#2b2b2e"))
(fixture-enqueue! pr job3 "打印件丙 V1")
(fixture-snapshot pr 121000)
(fixture-stop! pr)
(check-equal? (hash-ref (get-job (hash-ref job3 'id)) 'status) "cancelled")

;; ---- MQTT wire format ---------------------------------------------------------

(check-equal? (encode-remaining-length 0) '(0))
(check-equal? (encode-remaining-length 127) '(127))
(check-equal? (encode-remaining-length 128) '(128 1))
(check-equal? (encode-remaining-length 16383) '(255 127))
(check-equal? (encode-remaining-length 268435455) '(255 255 255 127))
(for ([n (in-list (list 0 1 127 128 129 16383 16384 2097151 2097152 268435455))])
  (define enc (list->bytes (encode-remaining-length n)))
  (define-values (val used) (decode-remaining-length enc 0))
  (check-equal? val n (format "varint round-trip ~a" n))
  (check-equal? used (bytes-length enc)))

;; CONNECT packet shape: header, "MQTT" level 4 flags, payloads
(define conn (encode-connect "layerly-1" "bblp" "code"))
(check-equal? (bytes-ref conn 0) #x10 "CONNECT type")
(define-values (clen _) (decode-remaining-length conn 1))
(check-equal? (+ 1 clen (length (encode-remaining-length clen))) (bytes-length conn))
(define mqtt-name (subbytes conn 4 8))
(check-equal? mqtt-name #"MQTT")
(check-equal? (bytes-ref conn 8) #x04 "protocol level 4")
(check-equal? (bytes-ref conn 9) #xC2 "clean session + username + password")

;; SUBSCRIBE / PUBLISH / PING / DISCONNECT round-trips
(define sub (encode-subscribe 1 "device/SN/report"))
(check-equal? (bytes-ref sub 0) #x82)
(define pub (encode-publish "device/SN/report" (jsexpr->string (hasheq 'print (hasheq 'gcode_state "RUNNING")))))
(check-equal? (bytes-ref pub 0) #x30 "QoS0 PUBLISH")
(define pkt (decode-packet pub 0))
(check-equal? (hash-ref pkt 'type) 'publish)
(check-equal? (hash-ref pkt 'topic) "device/SN/report")
(check-equal? (bytes->string/utf-8 (hash-ref pkt 'payload))
              (jsexpr->string (hasheq 'print (hasheq 'gcode_state "RUNNING"))))
(check-equal? (hash-ref (decode-packet (bytes #xD0 #x00) 0) 'type) 'pingresp)
(check-equal? (hash-ref (decode-packet (encode-disconnect) 0) 'type) 'other)

;; ---- Bambu projection -----------------------------------------------------------

(define report
  (hasheq 'print (hasheq 'gcode_state "RUNNING"
                         'printer_name "X1C-Office"
                         'nozzle_temper 220.5
                         'bed_temper 99.5
                         'chamber_temper 44
                         'cooling_fan_speed 80
                         'layer_num 114
                         'total_layer_num 184
                         'mc_remaining_time 41
                         'print_percent 62
                         'task_name "camera-plate V4"
                         'ams (hasheq 'ams (list (hasheq 'tray (list
                                                                 (hasheq 'tray_type "PETG" 'tray_color "2B2B2EFF" 'remain 82)
                                                                 (hasheq 'tray_type "PLA" 'tray_color "D8D3C8FF" 'remain 45)
                                                                 (hasheq 'tray_type "" 'tray_color "" 'remain 0)
                                                                 (hasheq 'tray_type "" 'tray_color "" 'remain 0))))))))
(define snap (report->snapshot report))
(check-equal? (hash-ref snap 'state) "printing")
(check-equal? (hash-ref snap 'nozzle-temp) 220.5)
(check-equal? (hash-ref (hash-ref snap 'job) 'layer) 114)
(check-equal? (hash-ref (hash-ref snap 'job) 'layers) 184)
(check-equal? (hash-ref (hash-ref snap 'job) 'percent) 62.0)
(check-equal? (list-ref (hash-ref snap 'ams) 0) (hasheq 'n 1 'type "PETG" 'color-name ""
                                                        'color-hex "#2B2B2E" 'remaining-g 0
                                                        'label "82%") "slot label is a percent, never fake grams")
(check-equal? (list-ref (hash-ref snap 'ams) 2) (hasheq 'n 3 'type "" 'color-name ""
                                                        'color-hex "" 'remaining-g 0 'label "空"))
(check-equal? (hash-ref (report->snapshot (hasheq 'print (hasheq 'gcode_state "PAUSE" 'task_name "x"))) 'state)
              "paused")
(check-equal? (hash-ref (report->snapshot (hasheq 'print (hasheq 'gcode_state "IDLE"))) 'job)
              #f "idle reports carry no job")

;; command builders
(define cmd (make-print-command "42" "cache/model.gcode.3mf" "abc"))
(check-equal? (hash-ref (hash-ref cmd 'print) 'command) "project_file")
(check-equal? (hash-ref (hash-ref cmd 'print) 'url) "cache/model.gcode.3mf")
(check-equal? (hash-ref (hash-ref (make-pause-command "1") 'print) 'command) "pause")
(check-equal? (hash-ref (hash-ref (make-resume-command "1") 'print) 'command) "resume")
(check-equal? (hash-ref (hash-ref (make-stop-command "1") 'print) 'command) "stop")

(printf "device-test: all checks passed\n")
