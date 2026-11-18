#lang racket/base

;; App data directory resolution. Family layout: per-user app data on each
;; OS, with an env override so tests and schema checks stay sandboxed (CI
;; has no writable profile and tests must never touch real user data).

(require racket/file
         racket/path
         racket/string)

(provide app-data-dir ensure-app-data-dir!)

;; LAYERLY_DATA_DIR wins over the per-OS default; used by tests and CI.
(define (env-override)
  (define v (getenv "LAYERLY_DATA_DIR"))
  (and v (not (string=? v "")) v))

(define (base-dir)
  (case (system-type 'os)
    [(macosx)
     (build-path (find-system-path 'home-dir)
                 "Library" "Application Support")]
    [(windows)
     (define appdata (getenv "APPDATA"))
     (if appdata (string->path appdata)
         (build-path (find-system-path 'home-dir) "AppData" "Roaming"))]
    [else
     (define config (getenv "XDG_CONFIG_HOME"))
     (if config (string->path config)
         (build-path (find-system-path 'home-dir) ".config"))]))

(define (app-data-dir)
  (or (env-override)
      (build-path (base-dir) "layerly")))

(define (ensure-app-data-dir!)
  (define dir (app-data-dir))
  (unless (directory-exists? dir)
    (make-directory* dir))
  dir)
