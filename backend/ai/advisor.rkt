#lang racket/base

;; Advisor orchestration — the AI half of the governance contract.
;; BYOK settings are custody items: a 0600 JSON file in the app data dir,
;; held by this backend, masked to the UI as the __SAVED__ sentinel.
;; Every send path redacts first; the system prompt pins the role to
;; "AI proposes, user disposes"; proposed actions ride as trailing
;; confirm-card JSON the backend strips out of the stream and stores as
;; message.confirm — the UI renders them as confirmation cards, never as
;; executable buttons (design invariant 2).

(require json
         racket/file
         racket/format
         racket/list
         racket/port
         racket/string
         "../platform.rkt"
         "../store.rkt"
         "providers.rkt"
         "redact.rkt"
         "sse.rkt")

(provide settings-view settings-save! settings-path
         advisor-configured?
         build-advisor-context
         send-confirm-marker-prefix
         stream-advisor-reply!
         parse-confirm-card
         advisor-request-body
         anthropic-request-body
         extract-delta
         strip-confirm-marker)

;; ---- settings custody ---------------------------------------------------------

;; Masked sentinel: the UI receives this after a save instead of the key.
(define saved-sentinel "__SAVED__")

(define (settings-path)
  (build-path (ensure-app-data-dir!) "ai-settings.json"))

(define default-settings
  (hasheq 'provider default-preset-id
          'model ""
          'base-url ""
          'api-key ""
          'redact-enabled #t))

(define (load-settings)
  (if (file-exists? (settings-path))
      (with-handlers ([exn:fail? (lambda (_) default-settings)])
        (for/fold ([acc default-settings])
                  ([(k v) (in-hash (string->jsexpr (file->string (settings-path))))])
          (hash-set acc k v)))
      default-settings))

(define (save-settings! h)
  (define dir (ensure-app-data-dir!))
  (define tmp (build-path dir ".ai-settings.json.tmp"))
  (with-output-to-file tmp
    (lambda () (write-string (jsexpr->string h)))
    #:exists 'replace)
  (when (file-exists? (settings-path))
    (delete-file (settings-path)))
  (rename-file-or-directory tmp (settings-path))
  ;; 0600: the key file is backend-held; nothing else may read it.
  (file-or-directory-permissions (settings-path) #o600)
  (void))

;; Public view: the key is replaced by the sentinel so it never crosses
;; the bridge; an empty key shows as empty (nothing saved yet).
(define (settings-view)
  (define s (load-settings))
  (hasheq 'provider (hash-ref s 'provider)
          'model (hash-ref s 'model)
          'base-url (hash-ref s 'base-url)
          'api-key (if (non-empty-string? (hash-ref s 'api-key ""))
                       saved-sentinel
                       "")
          'redact-enabled (hash-ref s 'redact-enabled)
          'presets (for/list ([p (in-list provider-presets)])
                     (hasheq 'id (preset-id p)
                             'label (preset-label p)
                             'model (preset-model p)
                             'kind (preset-kind p)))))

(define (settings-save! patch)
  (define s (load-settings))
  ;; __SAVED__ round-trips never overwrite the stored key.
  (define new-key
    (let ([v (hash-ref patch 'api-key #f)])
      (cond
        [(not v) (hash-ref s 'api-key "")]
        [(string=? v saved-sentinel) (hash-ref s 'api-key "")]
        [else v])))
  (save-settings!
   (hash-set* s
              'provider (hash-ref patch 'provider (hash-ref s 'provider))
              'model (hash-ref patch 'model (hash-ref s 'model))
              'base-url (hash-ref patch 'base-url (hash-ref s 'base-url))
              'api-key new-key
              'redact-enabled (hash-ref patch 'redact-enabled (hash-ref s 'redact-enabled))))
  (settings-view))

;; Effective call config: preset defaults + user overrides; the env var
;; is consulted only when no key is configured (BYOK convention).
(define (call-config)
  (define s (load-settings))
  (define preset (or (find-preset (hash-ref s 'provider)) (find-preset default-preset-id)))
  (define model
    (let ([m (hash-ref s 'model "")])
      (if (non-empty-string? m) m (preset-model preset))))
  (define base-url
    (let ([b (hash-ref s 'base-url "")])
      (if (non-empty-string? b) b (if (non-empty-string? (preset-base-url preset))
                                      (preset-base-url preset)
                                      (if (string=? (preset-kind preset) "anthropic")
                                          "https://api.anthropic.com/v1"
                                          "https://api.openai.com/v1")))))
  (define api-key
    (let ([k (hash-ref s 'api-key "")])
      (if (non-empty-string? k)
          k
          (let ([env (preset-env-key preset)])
            (and env (getenv env))))))
  (values (preset-id preset) (preset-kind preset) model base-url api-key
          (hash-ref s 'redact-enabled #t)))

(define (advisor-configured?)
  (define-values (_id _kind model base-url api-key _redact) (call-config))
  (and (non-empty-string? model)
       (non-empty-string? base-url)
       ;; ollama is keyless-local; every cloud preset needs a key
       (or (non-empty-string? api-key)
           (let-values ([(_i kind _m _b _k _r) (call-config)])
             (string=? kind "ollama")))))

;; ---- context assembly -----------------------------------------------------------

;; The advisor sees only what the user's refs point at, plus compact
;; library summaries. Everything crosses the wire redacted and the refs
;; are echoed in the message so the UI can show context sources (design
;; invariant 6).
(define (build-advisor-context refs)
  ;; Each ref kind contributes one section; refs the UI shows are the
  ;; same strings the model receives, so context sources stay visible.
  (define sections
    (append
     (for/list ([ref (in-list refs)] #:when (string-prefix? ref "project:"))
       (let ([pid (substring ref 8)])
         (let ([p (get-project pid)])
           (if p
               (format "作品「~a」(状态 ~a)：brief=~a"
                       (hash-ref p 'name)
                       (hash-ref p 'status)
                       (hash-ref p 'brief))
               (format "作品 ~a 不存在" pid)))))
     (for/list ([ref (in-list refs)] #:when (string=? ref "materials"))
       (format "材料库：~a"
               (string-join
                (for/list ([m (in-list (list-materials))])
                  (format "~a(~a) 余 ~a g/~a g"
                          (hash-ref m 'name)
                          (hash-ref m 'type)
                          (hash-ref m 'remaining-g)
                          (hash-ref m 'total-g)))
                "；")))
     (for/list ([ref (in-list refs)] #:when (string=? ref "device"))
       (let ([devices (list-devices)])
         (if (null? devices)
             "设备：尚未连接打印机"
             (format "设备：~a"
                     (string-join
                      (for/list ([d (in-list devices)])
                        (format "~a (~a, ~a)"
                                (hash-ref d 'name)
                                (hash-ref d 'model)
                                (hash-ref d 'kind)))
                      "；")))))
     (for/list ([ref (in-list refs)] #:when (string=? ref "history"))
       (format "最近打印记录：~a 条；失败 ~a 条"
               (length (list-jobs 30))
               (length (filter (lambda (j) (string=? (hash-ref j 'status) "failed"))
                               (list-jobs 30)))))))
  (string-join sections "\n"))

;; ---- confirm-card protocol --------------------------------------------------------

;; The model may append exactly one action proposal as its final line:
;;   <<<CONFIRM>>>{"action":...,"label":...,"body":...,"impact":...}
;; The backend strips it out of the user-visible text and stores it as
;; message.confirm. Nothing here executes anything — the card is data.
(define confirm-marker "<<<CONFIRM>>>")

(define (strip-confirm-marker text)
  (define idx (string-index-of text confirm-marker))
  (if (>= idx 0)
      (values (string-trim (substring text 0 idx)) (string-trim (substring text (+ idx (string-length confirm-marker)))))
      (values text #f)))

(define (string-index-of s needle)
  (define m (regexp-match-positions (regexp (regexp-quote needle)) s))
  (if m (caar m) -1))

;; Pure parser: marker line → confirm-card hasheq or #f.
(define (parse-confirm-card raw)
  (if (non-empty-string? raw)
      (with-handlers ([exn:fail? (lambda (_) #f)])
        (define json (string->jsexpr raw))
        (and (hash? json)
             (hash-ref json 'action #f)
             (hasheq 'label (hash-ref json 'label "待你确认")
                     'body (hash-ref json 'body "")
                     'impact (hash-ref json 'impact "")
                     'action (hash-ref json 'action)
                     'args (hash-ref json 'args (hasheq)))))
      #f))

(define send-confirm-marker-prefix confirm-marker)

;; ---- request bodies (pure, testable) ------------------------------------------------

;; OpenAI-compatible chat completion request; messages carry the system
;; prompt + history. Returns the JSON string.
(define (advisor-request-body model system messages)
  (jsexpr->string
   (hasheq 'model model
           'stream #t
           'messages (list* (hasheq 'role "system" 'content system)
                            (for/list ([m (in-list messages)])
                              (hasheq 'role (hash-ref m 'role)
                                      'content (hash-ref m 'content)))))))

;; Anthropic messages request.
(define (anthropic-request-body model system messages)
  (jsexpr->string
   (hasheq 'model model
           'stream #t
           'max_tokens 2048
           'system system
           'messages (for/list ([m (in-list messages)])
                       (hasheq 'role (hash-ref m 'role)
                               'content (hash-ref m 'content))))))

;; ---- the send path -------------------------------------------------------------------

;; Streams the advisor reply for `message` in `conversation-id` by calling
;; on-delta with text fragments (the route forwards them over the family
;; line protocol) and finally calling on-confirm with the parsed card (or
;; #f). The full reply is persisted by the caller after the stream ends.
;; Raises honestly when BYOK is not configured.
(define (stream-advisor-reply! conversation-id message refs on-delta on-confirm)
  (unless (advisor-configured?)
    (raise (exn:fail "advisor: 未配置模型（设置 → AI 配置里填 API key）"
                     (current-continuation-marks))))
  (define-values (preset-id kind model base-url api-key redact-enabled) (call-config))
  (define context (build-advisor-context refs))
  (define system
    (string-join
     (list "你是 layerly 里的 AI 顾问 Sarah（AI-native 3D 打印工作台）。"
           "职责：解释、比较、起草；一切打印、采购、删除归档动作只能由用户确认执行。"
           "回答要给出具体数字与可执行建议；引用到的数据来源在回答末尾用「依据：」列出。"
           (if (and context (non-empty-string? context))
               (string-append "以下是用户引用的工作台上下文（已脱敏）：\n" context)
               "用户没有引用工作台数据时，不要编造设备或材料数字。")
           (string-append
            "若要提议一个需要用户确认的动作，在回答的最后另起一行输出：\n"
            confirm-marker
            "{\"action\":\"add-shopping-item|mark-material|dispatch-print\",\"label\":\"…\",\"body\":\"…\",\"impact\":\"…\",\"args\":{…}}\n"
            "没有动作提议就不要输出该标记。")
           "始终使用简体中文回答。")))
  (define history
    (for/list ([m (in-list (list-messages conversation-id))]
               ;; confirm cards are proposals, not dialogue turns
               #:unless (hash-ref m 'confirm #f)
               #:when (member (hash-ref m 'role) '("user" "advisor")))
      (hasheq 'role (if (string=? (hash-ref m 'role) "user") "user" "assistant")
              'content (hash-ref m 'content))))

  (define outgoing (if redact-enabled (redacted-text message) message))
  (define turns (append history (list (hasheq 'role "user" 'content outgoing))))
  (define body (if (string=? kind "anthropic")
                   (anthropic-request-body model system turns)
                   (advisor-request-body model system turns)))
  (define headers
    (if (string=? kind "anthropic")
        (list (cons "x-api-key" (or api-key ""))
              (cons "anthropic-version" "2023-06-01")
              (cons "Content-Type" "application/json"))
        (list (cons "Authorization" (string-append "Bearer " (or api-key "")))
              (cons "Content-Type" "application/json"))))
  (define url
    (if (string=? kind "anthropic")
        (string-append base-url "/messages")
        (string-append base-url "/chat/completions")))

  (define collected (make-parameter ""))
  (define (handle-data payload)
    (cond
      [(string=? payload "[DONE]") void]
      [else
       (with-handlers ([exn:fail? void]) ; one malformed frame never kills the stream
         (define frame (string->jsexpr payload))
         (define delta (extract-delta kind frame))
         (when (and delta (non-empty-string? delta))
           (collected (string-append (collected) delta))
           (on-delta delta)))]))
  (stream-request url headers body handle-data)
  ;; Split the marker out of the collected reply; only the clean text is
  ;; user-visible.
  (define-values (clean raw-confirm) (strip-confirm-marker (collected)))
  (on-confirm clean (parse-confirm-card (or raw-confirm ""))))

;; OpenAI: choices[0].delta.content; Anthropic: content_block_delta delta.text.
(define (extract-delta kind frame)
  (if (string=? kind "anthropic")
      (case (hash-ref frame 'type "")
        [("content_block_delta")
         (hash-ref (hash-ref frame 'delta (hasheq)) 'text #f)]
        [else #f])
      (let ([choices (hash-ref frame 'choices '())])
        (and (pair? choices)
             (hash-ref (hash-ref (car choices) 'delta (hasheq)) 'content #f)))))
