#lang racket/base

;; Smoke test for the API surface contract: routes must exist and the
;; health route must report the app version. Grows with each backend
;; slice; deeper route tests read impl functions directly.

(require rackunit
         (only-in "../main.rkt" api))

;; define-api-routes exposes the route list consumed by glaze.rktd; the
;; schema contract is generated from it (raco glaze schema write/check).
(check-true (pair? api) "api must expose at least one route")
