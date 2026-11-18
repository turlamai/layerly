#lang racket/base

;; Redaction before anything leaves the machine toward an LLM. Every AI
;; send path calls `redact` last; `redact-preview` returns the same result
;; plus match counts so the UI can show exactly what would be sent
;; (family governance: AI proposes, user disposes, secrets never travel
;; unredacted).

(require racket/contract
         racket/list
         racket/string)

(provide redact redacted-text redact-preview)

;; Each rule: (list name regex replacement). Patterns use the pregexp
;; dialect (#px): {n} quantifiers and (?i:…) case folding are not
;; available in the plain #rx dialect.
(define rules
  (list
   ;; PEM / OpenSSH private key blocks
   (list "private-key"
         #px"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----"
         "[REDACTED:private-key]")
   ;; AWS access key ids
   (list "aws-key" #px"AKIA[0-9A-Z]{16}" "[REDACTED:aws-key]")
   ;; Generic API tokens: sk-…, ghp_…, xoxb-…, Bearer …
   (list "api-token"
         #px"(sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|xox[abprs]-[A-Za-z0-9-]{10,})"
         "[REDACTED:api-token]")
   (list "bearer" #px"(?i:bearer)[ ]+[A-Za-z0-9._~/+=-]{16,}" "[REDACTED:bearer]")
   ;; password= / PASSWORD: assignments (shell + env shapes)
   (list "password-assign"
         #px"(?i:(password|passwd|pwd|secret|token)[ ]*[=:][ ]*[^[:space:]\"']{4,})"
         "[REDACTED:credentials]")
   ;; device access codes pasted into a brief (the LAN printer secret)
   (list "access-code"
         #px"(?i:(access[ _-]?code|访问码)[ ]*[=:][ ]*[^[:space:]\"']{4,})"
         "[REDACTED:access-code]")
   ;; Connection strings embedding credentials
   (list "conn-uri"
         #px"[a-z][a-z0-9+.-]*://[^/[:space:]]+:[^@/[:space:]]+@"
         "[REDACTED:connection-string]")))

(define (apply-rule text rule)
  (define name (car rule))
  (define rx (cadr rule))
  (define replacement (caddr rule))
  (define matches (regexp-match* rx text))
  (if (null? matches)
      (values text '())
      (values (regexp-replace* rx text replacement) (map (lambda (_) name) matches))))

;; Returns (values redacted-text match-names).
(define (redact text)
  (for/fold ([text text] [found '()])
            ([rule (in-list rules)])
    (define-values (next names) (apply-rule text rule))
    (values next (append found names))))

(define (redacted-text text)
  (define-values (out _) (redact text))
  out)

;; The preview the confirmation UI shows: same text, plus which rules hit.
(define (redact-preview text)
  (define-values (out found) (redact text))
  (hasheq 'text out
          'matches found))
