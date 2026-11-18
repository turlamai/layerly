#lang racket/base

;; Minimal MQTT 3.1.1 client primitives over TLS — enough for Bambu LAN
;; bridges (CONNECT/SUBSCRIBE/PUBLISH QoS0/PINGREQ/DISCONNECT on one
;; topic pair). Encoding and remaining-length math are pure and unit
;; tested; the connection loop runs in a thread under the caller's
;; custodian so the per-request custodian rule never traps it.
;;
;; Honesty note (issue #2): the wire format is verified by packet-level
;; tests; the full session path is unverified against real hardware until
;; a printer is available.

(require openssl
         racket/math
         racket/string)

(provide encode-remaining-length decode-remaining-length
         encode-connect encode-subscribe encode-publish
         encode-pingreq encode-disconnect
         decode-packet
         mqtt-connect!
         mqtt-publish-once!)

;; ---- remaining length varint (MQTT spec 2.2.3) ------------------------------

(define (encode-remaining-length n)
  (unless (and (exact-nonnegative-integer? n) (<= n 268435455))
    (raise-argument-error 'encode-remaining-length "0..268435455" n))
  (let loop ([n n] [acc '()])
    (cond
      [(zero? n) (if (null? acc) (list 0) (reverse acc))]
      [else
       (define byte (modulo n 128))
       (define rest (quotient n 128))
       (if (> rest 0)
           (loop rest (cons (+ byte 128) acc))
           (loop 0 (cons byte acc)))])))

;; Returns (values value bytes-consumed) from the byte string starting at pos.
(define (decode-remaining-length buf pos)
  (let loop ([pos pos] [multiplier 1] [value 0])
    (when (>= pos (bytes-length buf))
      (error 'decode-remaining-length "truncated varint"))
    (define byte (bytes-ref buf pos))
    (define nv (+ value (* (bitwise-and byte 127) multiplier)))
    (if (> (bitwise-and byte 128) 0)
        (loop (add1 pos) (* multiplier 128) nv)
        (values nv (add1 pos)))))

;; ---- packet encoders --------------------------------------------------------

(define (string->mqtt s)
  (define b (string->bytes/utf-8 s))
  (bytes-append (bytes (bitwise-and (arithmetic-shift (bytes-length b) -8) #xFF)
                        (modulo (bytes-length b) 256))
                b))

(define (append-remaining type payload)
  (bytes-append (bytes type)
                (list->bytes (encode-remaining-length (bytes-length payload)))
                payload))

;; CONNECT with clean session, username and password (Bambu: bblp / access code).
(define (encode-connect client-id username password [keepalive 60])
  (define flags (+ #x02 ; clean session
                   (if (non-empty-string? username) #x80 0)
                   (if (non-empty-string? password) #x40 0)))
  (define variable
    (bytes-append (string->mqtt "MQTT")
                  (bytes #x04 flags)
                  (bytes (bitwise-and (arithmetic-shift keepalive -8) #xFF)
                         (modulo keepalive 256))))
  (define payload
    (bytes-append (string->mqtt client-id)
                  (if (non-empty-string? username) (string->mqtt username) #"")
                  (if (non-empty-string? password) (string->mqtt password) #"")))
  (append-remaining #x10 (bytes-append variable payload)))

;; SUBSCRIBE (QoS 0 topic, single topic per call — the bridge needs one).
(define (encode-subscribe packet-id topic)
  (append-remaining #x82
                    (bytes-append (bytes (bitwise-and (arithmetic-shift packet-id -8) #xFF)
                                          (modulo packet-id 256))
                                  (string->mqtt topic)
                                  (bytes 0))))

;; PUBLISH QoS 0. Payload accepts a string or bytes.
(define (encode-publish topic payload)
  (append-remaining #x30
                    (bytes-append (string->mqtt topic)
                                  (if (string? payload) (string->bytes/utf-8 payload) payload))))

(define (encode-pingreq) (bytes #xC0 #x00))
(define (encode-disconnect) (bytes #xE0 #x00))

;; ---- packet decoder -----------------------------------------------------------

;; Decodes one packet from buf (starting at pos). Returns a hasheq:
;; type, topic (PUBLISH only), payload bytes, and the number of bytes
;; consumed so a stream reader can loop.
(define (decode-packet buf [pos 0])
  (when (>= pos (bytes-length buf))
    (error 'decode-packet "empty buffer"))
  (define type (arithmetic-shift (bytes-ref buf pos) -4))
  (define flags (bitwise-and (bytes-ref buf pos) #x0F))
  (define-values (remaining after-len) (decode-remaining-length buf (add1 pos)))
  (define end (+ after-len remaining))
  (when (> end (bytes-length buf))
    (error 'decode-packet "truncated packet"))
  (case type
    [(3) ; PUBLISH
     (define topic-len (+ (* (bytes-ref buf after-len) 256) (bytes-ref buf (+ after-len 1))))
     (define topic (bytes->string/utf-8 (subbytes buf (+ after-len 2) (+ after-len 2 topic-len))))
     (define payload-start (+ after-len 2 topic-len))
     ;; QoS 0 has no packet id; QoS 1/2 would add one before the payload.
     (define payload-start* (case flags [(2) (+ payload-start 2)] [else payload-start]))
     (hasheq 'type 'publish
             'topic topic
             'payload (subbytes buf payload-start* end)
             'consumed (- end pos))]
    [(13) (hasheq 'type 'pingresp 'consumed (- end pos))]
    [(9)  (hasheq 'type 'suback 'consumed (- end pos))]
    [(2)  (hasheq 'type 'connack 'consumed (- end pos))]
    [else (hasheq 'type (case type [(4) 'puback] [(13) 'pingresp] [else 'other])
                  'consumed (- end pos))]))

;; ---- session ------------------------------------------------------------------

;; Blocking session loop: connect, subscribe, call on-publish for every
;; received PUBLISH, ping at keepalive/2, and stop when stop?-box becomes
;; #t. Returns normally on EOF; raises on connect failure (the caller
;; records honest connection status). Runs in the caller's thread.
(define (mqtt-connect! host port username password topic on-publish stop?-box
                       #:reconnect [reconnect #t])
  (define (session)
    (define-values (in out) (ssl-connect host port))
    (dynamic-wind
      (lambda () (void))
      (lambda ()
        (write-bytes (encode-connect (format "layerly-~a" (substring (format "~a" (current-inexact-milliseconds)) 0 10))
                                     username password)
                     out)
        (flush-output out)
        (write-bytes (encode-subscribe 1 topic) out)
        (flush-output out)
        (let ping-loop ([last-ping (current-inexact-milliseconds)] [buf (make-bytes 65536)])
          (when (not (unbox stop?-box))
            (sync/timeout 0.5 in) ; wake on data, EOF or time
            (define n (read-bytes-avail!* buf in))
            (define next-ping last-ping)
            (when (and (number? n) (> n 0))
              (let read-loop ([pos 0])
                (when (< pos n)
                  (define pkt (decode-packet buf pos))
                  (case (hash-ref pkt 'type)
                    [(publish)
                     (with-handlers ([exn:fail? void]) ; one bad report never kills the session
                       (on-publish (hash-ref pkt 'topic)
                                   (bytes->string/utf-8 (hash-ref pkt 'payload))))]
                    [else void])
                  (read-loop (+ pos (hash-ref pkt 'consumed))))))
            (when (>= (- (current-inexact-milliseconds) next-ping) 15000)
              (write-bytes (encode-pingreq) out)
              (flush-output out)
              (set! next-ping (current-inexact-milliseconds)))
            (ping-loop next-ping buf))))
      (lambda ()
        (with-handlers ([exn:fail? void])
          (write-bytes (encode-disconnect) out)
          (flush-output out)
          (close-input-port in)
          (close-output-port out)))))

  (if reconnect
      (let loop ()
        (unless (unbox stop?-box)
          (with-handlers ([exn:fail? void])
            (session))
          (unless (unbox stop?-box)
            (sleep 2) ; honest reconnect backoff
            (loop))))
      (session)))

;; One-shot publish: TLS connect, CONNECT+PUBLISH, disconnect. Used for
;; device command dispatch; the session loop stays the report channel.
(define (mqtt-publish-once! host topic username password payload
                            #:client-id [client-id "layerly-cmd"])
  (define-values (in out) (ssl-connect host 8883))
  (dynamic-wind
    (lambda () (void))
    (lambda ()
      (write-bytes (encode-connect client-id username password) out)
      (flush-output out)
      ;; Wait out the CONNACK so the PUBLISH is accepted in order.
      (define buf (make-bytes 256))
      (sync/timeout 5 in)
      (read-bytes-avail! buf in)
      (write-bytes (encode-publish topic (string->bytes/utf-8 payload)) out)
      (flush-output out)
      (write-bytes (encode-disconnect) out)
      (flush-output out))
    (lambda ()
      (close-input-port in)
      (close-output-port out))))
