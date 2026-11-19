#lang racket/base

;; Layerly library — SQLite persistence for the whole workbench: projects,
;; design versions, slice plans, print jobs, feedback, materials, shopping
;; list, purchases, devices, advisor conversations and settings.
;;
;; The database opens lazily on first use: module load must stay pure
;; (schema check and raco test load this module; CI has no writable config
;; dir and tests sandbox via LAYERLY_DATA_DIR). Device access codes live
;; here in backend-held storage and are stripped from every row projected
;; toward the webview.

(require db
         json
         racket/date
         racket/file
         racket/format
         racket/hash
         racket/list
         racket/random
         racket/string
         glaze/sql
         "platform.rkt")

(provide store-init!
         ;; projects
         list-projects project-summary get-project
         create-project! update-project! delete-project!
         set-project-status!
         ;; versions
         list-versions create-version! set-current-version! delete-version!
         ;; slice plans
         list-plans create-plan! set-recommended-plan! delete-plan!
         ;; print jobs
         list-jobs jobs-for-project get-job create-job!
         job-started! job-progress! job-finished! job-failed! job-cancelled!
         ;; feedback
         list-feedback create-feedback!
         ;; materials
         list-materials create-material! update-material! delete-material!
         ;; shopping + purchases
         list-shopping create-shopping-item! delete-shopping-item!
         list-purchases create-purchase! purchase-arrived!
         ;; devices
         list-devices get-device get-device-raw create-device! update-device!
         delete-device! touch-device!
         ;; conversations + messages
         list-conversations get-conversation create-conversation!
         delete-conversation! list-messages add-message!
         ;; settings
         settings-get settings-set!
         ;; files + demo seed
         data-files-dir save-model-file! save-photo-file!
         seed-demo! library-counts
         store-fresh!
         db-path)

;; ---- connection (lazy, like the family stores) ---------------------------

(define db-box (box #f))

(define (db-path)
  (build-path (ensure-app-data-dir!) "layerly.db"))

(define (db)
  (or (unbox db-box)
      (let ([opened (open-sqlite-database (db-path))])
        (set-box! db-box opened)
        opened)))

(define (exec! stmt [params '()])
  (sql-execute! (db) stmt params))

(define (select stmt [params '()])
  (sql-select (db) stmt params))

;; Test support: drop every library file so the next open starts empty.
;; Only tests call this; a real workbench never loses data through it.
(define (store-fresh!)
  (when (unbox db-box)
    (with-handlers ([exn:fail? void])
      (sql-close! (unbox db-box))))
  (set-box! db-box #f)
  (define dir (ensure-app-data-dir!))
  (for ([f (in-list (list (build-path dir "layerly.db")
                          (build-path dir "ai-settings.json")))])
    (when (file-exists? f)
      (delete-file f)))
  (void))

;; ---- ids + time -----------------------------------------------------------

(define (new-id! prefix)
  (string-append prefix "-"
                 (bytes->hex-string (crypto-random-bytes 8))))

(define (bytes->hex-string b)
  (apply string-append
         (for/list ([byte (in-bytes b)])
           (~r byte #:base 16 #:min-width 2 #:pad-string "0"))))

(define (now-iso)
  (define d (current-date))
  (format "~a-~a-~aT~a:~a:~a"
          (~r (date-year d) #:min-width 4 #:pad-string "0")
          (~r (date-month d) #:min-width 2 #:pad-string "0")
          (~r (date-day d) #:min-width 2 #:pad-string "0")
          (~r (date-hour d) #:min-width 2 #:pad-string "0")
          (~r (date-minute d) #:min-width 2 #:pad-string "0")
          (~r (date-second d) #:min-width 2 #:pad-string "0")))

(define (iso-today)
  (substring (now-iso) 0 10))

;; ---- schema ---------------------------------------------------------------

(define (try-add-column! table column decl)
  (with-handlers ([exn:fail? void])
    (exec! (format "ALTER TABLE ~a ADD COLUMN ~a ~a" table column decl))))

(define (store-init!)
  (exec! "CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            brief TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'idea',
            size_text TEXT NOT NULL DEFAULT '',
            target_qty INTEGER NOT NULL DEFAULT 1,
            current_version_id TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL)")
  (exec! "CREATE TABLE IF NOT EXISTS versions (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            label TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            model_file TEXT NOT NULL DEFAULT '',
            material_name TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL)")
  (exec! "CREATE TABLE IF NOT EXISTS slice_plans (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            version_id TEXT NOT NULL,
            label TEXT NOT NULL,
            strategy TEXT NOT NULL DEFAULT '',
            walls INTEGER NOT NULL DEFAULT 3,
            infill TEXT NOT NULL DEFAULT '',
            supports TEXT NOT NULL DEFAULT '无',
            layer_height REAL NOT NULL DEFAULT 0.2,
            nozzle_temp INTEGER NOT NULL DEFAULT 220,
            bed_temp INTEGER NOT NULL DEFAULT 60,
            est_minutes INTEGER NOT NULL DEFAULT 0,
            est_grams REAL NOT NULL DEFAULT 0,
            est_layers INTEGER NOT NULL DEFAULT 0,
            parts_json TEXT NOT NULL DEFAULT '[]',
            recommended INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL)")
  (exec! "CREATE TABLE IF NOT EXISTS print_jobs (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            version_id TEXT NOT NULL DEFAULT '',
            plan_id TEXT NOT NULL DEFAULT '',
            device_id TEXT NOT NULL DEFAULT '',
            seq INTEGER NOT NULL DEFAULT 1,
            total INTEGER NOT NULL DEFAULT 1,
            status TEXT NOT NULL DEFAULT 'queued',
            material_name TEXT NOT NULL DEFAULT '',
            material_hex TEXT NOT NULL DEFAULT '',
            layer INTEGER NOT NULL DEFAULT 0,
            layers INTEGER NOT NULL DEFAULT 0,
            minutes INTEGER NOT NULL DEFAULT 0,
            grams REAL NOT NULL DEFAULT 0,
            lesson TEXT NOT NULL DEFAULT '',
            queued_at TEXT NOT NULL,
            started_at TEXT NOT NULL DEFAULT '',
            ended_at TEXT NOT NULL DEFAULT '')")
  (exec! "CREATE TABLE IF NOT EXISTS feedback (
            id TEXT PRIMARY KEY,
            job_id TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'note',
            text TEXT NOT NULL DEFAULT '',
            photo_file TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL)")
  (exec! "CREATE TABLE IF NOT EXISTS materials (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            brand TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT 'PLA',
            color_name TEXT NOT NULL DEFAULT '',
            color_hex TEXT NOT NULL DEFAULT '#888888',
            remaining_g REAL NOT NULL DEFAULT 0,
            total_g REAL NOT NULL DEFAULT 1000,
            opened_date TEXT NOT NULL DEFAULT '',
            slot INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'ok',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL)")
  (exec! "CREATE TABLE IF NOT EXISTS shopping_list (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            qty INTEGER NOT NULL DEFAULT 1,
            price REAL NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'manual',
            created_at TEXT NOT NULL)")
  (exec! "CREATE TABLE IF NOT EXISTS purchases (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            qty INTEGER NOT NULL DEFAULT 1,
            price REAL NOT NULL DEFAULT 0,
            arrived INTEGER NOT NULL DEFAULT 0,
            purchased_at TEXT NOT NULL,
            arrived_at TEXT NOT NULL DEFAULT '')")
  (exec! "CREATE TABLE IF NOT EXISTS devices (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            model TEXT NOT NULL DEFAULT '',
            host TEXT NOT NULL DEFAULT '',
            serial TEXT NOT NULL DEFAULT '',
            access_code TEXT NOT NULL DEFAULT '',
            kind TEXT NOT NULL DEFAULT 'bambu',
            last_seen TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL)")
  (exec! "CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            scope TEXT NOT NULL DEFAULT 'advisor',
            project_id TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL)")
  (exec! "CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            refs_json TEXT NOT NULL DEFAULT '[]',
            confirm_json TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL)")
  (exec! "CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL)")
  ;; Forward-compatible migrations: swallowed when the column is fresh.
  (try-add-column! "print_jobs" "device_name" "TEXT NOT NULL DEFAULT ''")
  (void))

;; ---- projects ---------------------------------------------------------------

(define (row->project row)
  (hasheq 'id (hash-ref row 'id)
          'name (hash-ref row 'name)
          'brief (hash-ref row 'brief)
          'status (hash-ref row 'status)
          'size-text (hash-ref row 'size_text)
          'target-qty (hash-ref row 'target_qty)
          'current-version-id (hash-ref row 'current_version_id)
          'created-at (hash-ref row 'created_at)
          'updated-at (hash-ref row 'updated_at)))

(define (list-projects)
  (for/list ([row (in-list (select "SELECT * FROM projects ORDER BY updated_at DESC"))])
    (row->project row)))

;; Count per lifecycle status for the filter row and dashboard metrics.
(define (library-counts)
  (define projects (list-projects))
  (define jobs (list-jobs))
  (define materials (list-materials))
  (define (count-status s)
    (length (filter (lambda (p) (string=? (hash-ref p 'status) s)) projects)))
  (hasheq 'projects (length projects)
          'idea (count-status "idea")
          'design (count-status "design")
          'slicing (count-status "slicing")
          'printing (count-status "printing")
          'done (count-status "done")
          'failed (count-status "failed")
          'jobs (length jobs)
          'materials (length materials)
          'stock-g (foldl (lambda (m acc) (+ acc (hash-ref m 'remaining-g))) 0 materials)))

(define (project-summary p)
  ;; Project row plus its current version label and live job progress —
  ;; every surface that shows a project must carry the status pill and,
  ;; while printing, the layerbar (design invariant 1/4).
  (define pid (hash-ref p 'id))
  (define version
    (if (non-empty-string? (hash-ref p 'current-version-id ""))
        (row->version
         (with-handlers ([exn:fail? (lambda (_) #f)])
           (select-one "SELECT * FROM versions WHERE id = ?"
                       (list (hash-ref p 'current-version-id)))))
        #f))
  (define job
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (select-one "SELECT * FROM print_jobs
                   WHERE project_id = ? AND status IN ('queued','printing')
                   ORDER BY queued_at DESC LIMIT 1"
                  (list pid))))
  (define job-h (and job (row->job job)))
  ;; Explicit construction (not hash-union): job rows also carry 'id.
  (for/fold ([acc p]) ([kv (in-list
                            (list (cons 'version-label
                                        (if version (hash-ref version 'label) ""))
                                  (cons 'job job-h)))])
    (hash-set acc (car kv) (cdr kv))))

(define (get-project id)
  (define row (select-one "SELECT * FROM projects WHERE id = ?" (list id)))
  (and row (project-summary (row->project row))))

(define (select-one stmt [params '()])
  (define rows (select stmt params))
  (and (pair? rows) (car rows)))

(define (touch-project! id)
  (exec! "UPDATE projects SET updated_at = ? WHERE id = ?"
         (list (now-iso) id)))

(define (create-project! name brief size-text target-qty)
  (define id (new-id! "p"))
  (define now (now-iso))
  (exec! "INSERT INTO projects (id, name, brief, status, size_text, target_qty,
                               created_at, updated_at)
          VALUES (?, ?, ?, 'idea', ?, ?, ?, ?)"
         (list id name brief size-text target-qty now now))
  (get-project id))

(define (update-project! id patch)
  (when (hash-has-key? patch 'name)
    (exec! "UPDATE projects SET name = ? WHERE id = ?"
           (list (hash-ref patch 'name) id)))
  (when (hash-has-key? patch 'brief)
    (exec! "UPDATE projects SET brief = ? WHERE id = ?"
           (list (hash-ref patch 'brief) id)))
  (when (hash-has-key? patch 'size-text)
    (exec! "UPDATE projects SET size_text = ? WHERE id = ?"
           (list (hash-ref patch 'size-text) id)))
  (when (hash-has-key? patch 'target-qty)
    (exec! "UPDATE projects SET target_qty = ? WHERE id = ?"
           (list (hash-ref patch 'target-qty) id)))
  (when (hash-has-key? patch 'current-version-id)
    (exec! "UPDATE projects SET current_version_id = ? WHERE id = ?"
           (list (hash-ref patch 'current-version-id) id)))
  (touch-project! id)
  (get-project id))

(define (set-project-status! id status)
  (exec! "UPDATE projects SET status = ?, updated_at = ? WHERE id = ?"
         (list status (now-iso) id)))

(define (delete-project! id)
  (exec! "DELETE FROM versions WHERE project_id = ?" (list id))
  (exec! "DELETE FROM slice_plans WHERE project_id = ?" (list id))
  (exec! "DELETE FROM print_jobs WHERE project_id = ?" (list id))
  (exec! "DELETE FROM feedback WHERE project_id = ?" (list id))
  (exec! "DELETE FROM messages WHERE conversation_id IN
            (SELECT id FROM conversations WHERE project_id = ?)" (list id))
  (exec! "DELETE FROM conversations WHERE project_id = ?" (list id))
  (void (exec! "DELETE FROM projects WHERE id = ?" (list id)))
  (void))

;; ---- versions ---------------------------------------------------------------

(define (row->version row)
  (hasheq 'id (hash-ref row 'id)
          'project-id (hash-ref row 'project_id)
          'label (hash-ref row 'label)
          'note (hash-ref row 'note)
          'model-file (hash-ref row 'model_file)
          'material-name (hash-ref row 'material_name)
          'created-at (hash-ref row 'created_at)))

(define (list-versions project-id)
  (for/list ([row (in-list (select "SELECT * FROM versions WHERE project_id = ?
                                    ORDER BY created_at DESC, rowid DESC" (list project-id)))])
    (row->version row)))

(define (create-version! project-id label note model-file material-name)
  (define id (new-id! "v"))
  (exec! "INSERT INTO versions (id, project_id, label, note, model_file,
                                material_name, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)"
         (list id project-id label note model-file material-name (now-iso)))
  ;; First version becomes the project's current version automatically.
  (when (string=? (hash-ref (get-project-raw project-id) 'current_version_id "") "")
    (exec! "UPDATE projects SET current_version_id = ? WHERE id = ?"
           (list id project-id)))
  (touch-project! project-id)
  (row->version (select-one "SELECT * FROM versions WHERE id = ?" (list id))))

(define (get-project-raw id)
  (select-one "SELECT * FROM projects WHERE id = ?" (list id)))

(define (set-current-version! project-id version-id)
  (exec! "UPDATE projects SET current_version_id = ?, updated_at = ?
          WHERE id = ?"
         (list version-id (now-iso) project-id))
  (void))

(define (delete-version! id)
  (define row (select-one "SELECT * FROM versions WHERE id = ?" (list id)))
  (when row
    (define pid (hash-ref row 'project_id))
    (exec! "DELETE FROM versions WHERE id = ?" (list id))
    (when (string=? (hash-ref (get-project-raw pid) 'current_version_id "") id)
      (define rest (list-versions pid))
      (void (exec! "UPDATE projects SET current_version_id = ? WHERE id = ?"
                    (list (if (pair? rest) (hash-ref (car rest) 'id) "") pid))))))

;; ---- slice plans --------------------------------------------------------------

(define (row->plan row)
  (hasheq 'id (hash-ref row 'id)
          'project-id (hash-ref row 'project_id)
          'version-id (hash-ref row 'version_id)
          'label (hash-ref row 'label)
          'strategy (hash-ref row 'strategy)
          'walls (hash-ref row 'walls)
          'infill (hash-ref row 'infill)
          'supports (hash-ref row 'supports)
          'layer-height (hash-ref row 'layer_height)
          'nozzle-temp (hash-ref row 'nozzle_temp)
          'bed-temp (hash-ref row 'bed_temp)
          'est-minutes (hash-ref row 'est_minutes)
          'est-grams (hash-ref row 'est_grams)
          'est-layers (hash-ref row 'est_layers)
          'parts (with-handlers ([exn:fail? (lambda (_) '())])
                   (string->jsexpr (hash-ref row 'parts_json)))
          'recommended (= (hash-ref row 'recommended) 1)
          'created-at (hash-ref row 'created_at)))

(define (list-plans project-id)
  (for/list ([row (in-list (select "SELECT * FROM slice_plans WHERE project_id = ?
                                    ORDER BY recommended DESC, created_at"
                                   (list project-id)))])
    (row->plan row)))

(define (create-plan! project-id version-id plan)
  (define id (new-id! "sp"))
  (exec! "INSERT INTO slice_plans (id, project_id, version_id, label, strategy,
                                   walls, infill, supports, layer_height,
                                   nozzle_temp, bed_temp, est_minutes, est_grams,
                                   est_layers, parts_json, recommended, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)"
         (list id
               project-id version-id
               (hash-ref plan 'label "方案")
               (hash-ref plan 'strategy "")
               (hash-ref plan 'walls 3)
               (hash-ref plan 'infill "")
               (hash-ref plan 'supports "无")
               (hash-ref plan 'layer-height 0.2)
               (hash-ref plan 'nozzle-temp 220)
               (hash-ref plan 'bed-temp 60)
               (hash-ref plan 'est-minutes 0)
               (hash-ref plan 'est-grams 0)
               (hash-ref plan 'est-layers 0)
               (jsexpr->string (hash-ref plan 'parts '()))
               (now-iso)))
  (row->plan (select-one "SELECT * FROM slice_plans WHERE id = ?" (list id))))

(define (set-recommended-plan! id)
  (define row (select-one "SELECT * FROM slice_plans WHERE id = ?" (list id)))
  (when row
    (exec! "UPDATE slice_plans SET recommended = 0 WHERE project_id = ?"
           (list (hash-ref row 'project_id)))
    (exec! "UPDATE slice_plans SET recommended = 1 WHERE id = ?" (list id)))
  (void))

(define (delete-plan! id)
  (void (exec! "DELETE FROM slice_plans WHERE id = ?" (list id))))

;; ---- print jobs -----------------------------------------------------------------

(define (row->job row)
  (hasheq 'id (hash-ref row 'id)
          'project-id (hash-ref row 'project_id)
          'version-id (hash-ref row 'version_id)
          'plan-id (hash-ref row 'plan_id)
          'device-id (hash-ref row 'device_id)
          'device-name (hash-ref row 'device_name "")
          'seq (hash-ref row 'seq)
          'total (hash-ref row 'total)
          'status (hash-ref row 'status)
          'material-name (hash-ref row 'material_name)
          'material-hex (hash-ref row 'material_hex)
          'layer (hash-ref row 'layer)
          'layers (hash-ref row 'layers)
          'minutes (hash-ref row 'minutes)
          'grams (hash-ref row 'grams)
          'lesson (hash-ref row 'lesson)
          'queued-at (hash-ref row 'queued_at)
          'started-at (hash-ref row 'started_at)
          'ended-at (hash-ref row 'ended_at)))

(define (list-jobs [limit 200])
  (for/list ([row (in-list (select "SELECT * FROM print_jobs
                                    ORDER BY queued_at DESC LIMIT ?"
                                   (list limit)))])
    (row->job row)))

(define (jobs-for-project project-id)
  (for/list ([row (in-list (select "SELECT * FROM print_jobs WHERE project_id = ?
                                    ORDER BY queued_at DESC" (list project-id)))])
    (row->job row)))

(define (get-job id)
  (define row (select-one "SELECT * FROM print_jobs WHERE id = ?" (list id)))
  (and row (row->job row)))

(define (create-job! project-id version-id plan-id device-id device-name
                     seq total layers est-minutes est-grams
                     material-name material-hex)
  (define id (new-id! "j"))
  (exec! "INSERT INTO print_jobs (id, project_id, version_id, plan_id, device_id,
                                  device_name, seq, total, status, material_name,
                                  material_hex, layers, minutes, grams, queued_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, ?, ?, ?, ?, ?)"
         (list id project-id version-id plan-id device-id device-name
               seq total material-name material-hex
               layers est-minutes est-grams (now-iso)))
  (set-project-status! project-id "printing")
  (get-job id))

(define (job-started! id)
  (define job (get-job id))
  (when job
    (exec! "UPDATE print_jobs SET status = 'printing', started_at = ?,
                   layer = 0 WHERE id = ?"
           (list (now-iso) id))))

(define (job-progress! id layer)
  (exec! "UPDATE print_jobs SET layer = ? WHERE id = ?"
         (list layer id)))

(define (job-finished! id minutes grams)
  (define job (get-job id))
  (when job
    (exec! "UPDATE print_jobs SET status = 'done', minutes = ?, grams = ?,
                   layer = layers, ended_at = ? WHERE id = ?"
           (list minutes grams (now-iso) id))
    ;; Batch semantics: the last piece (seq = total) completes the batch;
    ;; earlier pieces send the project back to slicing — the next piece
    ;; awaits its print-prep dispatch.
    (define pid (hash-ref job 'project-id))
    (if (< (hash-ref job 'seq 1) (hash-ref job 'total 1))
        (set-project-status! pid "slicing")
        (set-project-status! pid "done"))))

(define (job-failed! id lesson [minutes 0] [grams 0])
  (define job (get-job id))
  (when job
    (exec! "UPDATE print_jobs SET status = 'failed', lesson = ?, minutes = ?,
                   grams = ?, ended_at = ? WHERE id = ?"
           (list lesson minutes grams (now-iso) id))
    (define pid (hash-ref job 'project-id))
    (if (< (hash-ref job 'seq 1) (hash-ref job 'total 1))
        (set-project-status! pid "slicing")
        (set-project-status! pid "failed"))))

(define (job-cancelled! id)
  (define job (get-job id))
  (when job
    (exec! "UPDATE print_jobs SET status = 'cancelled', ended_at = ? WHERE id = ?"
           (list (now-iso) id))
    (define pid (hash-ref job 'project-id))
    ;; Cancellation is a user decision, not a print defect: the batch goes
    ;; back to slicing for a later dispatch, unless it was the last piece.
    (if (< (hash-ref job 'seq 1) (hash-ref job 'total 1))
        (set-project-status! pid "slicing")
        (set-project-status! pid "design"))))

;; ---- feedback --------------------------------------------------------------------

(define (row->feedback row)
  (hasheq 'id (hash-ref row 'id)
          'job-id (hash-ref row 'job_id)
          'project-id (hash-ref row 'project_id)
          'kind (hash-ref row 'kind)
          'text (hash-ref row 'text)
          'photo-file (hash-ref row 'photo_file)
          'created-at (hash-ref row 'created_at)))

(define (list-feedback [project-id #f])
  (define rows
    (if project-id
        (select "SELECT * FROM feedback WHERE project_id = ? ORDER BY created_at DESC"
                (list project-id))
        (select "SELECT * FROM feedback ORDER BY created_at DESC")))
  (for/list ([row (in-list rows)]) (row->feedback row)))

(define (create-feedback! project-id job-id kind text photo-file)
  (define id (new-id! "f"))
  (exec! "INSERT INTO feedback (id, job_id, project_id, kind, text, photo_file, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)"
         (list id job-id project-id kind text photo-file (now-iso)))
  (row->feedback (select-one "SELECT * FROM feedback WHERE id = ?" (list id))))

;; ---- materials ---------------------------------------------------------------------

(define (row->material row)
  (hasheq 'id (hash-ref row 'id)
          'name (hash-ref row 'name)
          'brand (hash-ref row 'brand)
          'type (hash-ref row 'type)
          'color-name (hash-ref row 'color_name)
          'color-hex (hash-ref row 'color_hex)
          'remaining-g (hash-ref row 'remaining_g)
          'total-g (hash-ref row 'total_g)
          'opened-date (hash-ref row 'opened_date)
          'slot (hash-ref row 'slot)
          'status (hash-ref row 'status)
          'notes (hash-ref row 'notes)
          'created-at (hash-ref row 'created_at)
          'updated-at (hash-ref row 'updated_at)))

(define (list-materials)
  (for/list ([row (in-list (select "SELECT * FROM materials ORDER BY created_at"))])
    (row->material row)))

(define (create-material! m)
  (define id (new-id! "m"))
  (define now (now-iso))
  (exec! "INSERT INTO materials (id, name, brand, type, color_name, color_hex,
                                 remaining_g, total_g, opened_date, slot, status,
                                 notes, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
         (list id
               (hash-ref m 'name "新耗材")
               (hash-ref m 'brand "")
               (hash-ref m 'type "PLA")
               (hash-ref m 'color-name "")
               (hash-ref m 'color-hex "#888888")
               (hash-ref m 'remaining-g 0)
               (hash-ref m 'total-g 1000)
               (hash-ref m 'opened-date (iso-today))
               (hash-ref m 'slot 0)
               (hash-ref m 'status "ok")
               (hash-ref m 'notes "")
               now now))
  (row->material (select-one "SELECT * FROM materials WHERE id = ?" (list id))))

(define (update-material! id patch)
  (define keys '((name "name") (brand "brand") (type "type")
                 (color-name "color_name") (color-hex "color_hex")
                 (remaining-g "remaining_g") (total-g "total_g")
                 (opened-date "opened_date") (slot "slot")
                 (status "status") (notes "notes")))
  (for ([k (in-list keys)])
    (define key (car k))
    (when (hash-has-key? patch key)
      (exec! (format "UPDATE materials SET ~a = ? WHERE id = ?" (cadr k))
             (list (hash-ref patch key) id))))
  (exec! "UPDATE materials SET updated_at = ? WHERE id = ?"
         (list (now-iso) id))
  (row->material (select-one "SELECT * FROM materials WHERE id = ?" (list id))))

(define (delete-material! id)
  (void (exec! "DELETE FROM materials WHERE id = ?" (list id))))

;; ---- shopping list + purchases -------------------------------------------------------

(define (row->shopping row)
  (hasheq 'id (hash-ref row 'id)
          'name (hash-ref row 'name)
          'qty (hash-ref row 'qty)
          'price (hash-ref row 'price)
          'source (hash-ref row 'source)
          'created-at (hash-ref row 'created_at)))

(define (list-shopping)
  (for/list ([row (in-list (select "SELECT * FROM shopping_list ORDER BY created_at"))])
    (row->shopping row)))

(define (create-shopping-item! name qty price source)
  (define id (new-id! "s"))
  (exec! "INSERT INTO shopping_list (id, name, qty, price, source, created_at)
          VALUES (?, ?, ?, ?, ?, ?)"
         (list id name qty price source (now-iso)))
  (row->shopping (select-one "SELECT * FROM shopping_list WHERE id = ?" (list id))))

(define (delete-shopping-item! id)
  (void (exec! "DELETE FROM shopping_list WHERE id = ?" (list id))))

(define (row->purchase row)
  (hasheq 'id (hash-ref row 'id)
          'name (hash-ref row 'name)
          'qty (hash-ref row 'qty)
          'price (hash-ref row 'price)
          'arrived (= (hash-ref row 'arrived) 1)
          'purchased-at (hash-ref row 'purchased_at)
          'arrived-at (hash-ref row 'arrived_at)))

(define (list-purchases)
  (for/list ([row (in-list (select "SELECT * FROM purchases ORDER BY purchased_at DESC"))])
    (row->purchase row)))

(define (create-purchase! name qty price)
  (define id (new-id! "pr"))
  (exec! "INSERT INTO purchases (id, name, qty, price, arrived, purchased_at)
          VALUES (?, ?, ?, ?, 0, ?)"
         (list id name qty price (now-iso)))
  (row->purchase (select-one "SELECT * FROM purchases WHERE id = ?" (list id))))

(define (purchase-arrived! id)
  (exec! "UPDATE purchases SET arrived = 1, arrived_at = ? WHERE id = ?"
         (list (iso-today) id))
  (row->purchase (select-one "SELECT * FROM purchases WHERE id = ?" (list id))))

;; ---- devices ------------------------------------------------------------------------

;; Public projection: access codes never cross the bridge (ownership
;; boundary in AGENTS.md).
(define (row->device row)
  (hasheq 'id (hash-ref row 'id)
          'name (hash-ref row 'name)
          'model (hash-ref row 'model)
          'host (hash-ref row 'host)
          'serial (hash-ref row 'serial)
          'kind (hash-ref row 'kind)
          'has-access-code (not (string=? (hash-ref row 'access_code "") ""))
          'last-seen (hash-ref row 'last_seen)
          'created-at (hash-ref row 'created_at)))

(define (list-devices)
  (for/list ([row (in-list (select "SELECT * FROM devices ORDER BY created_at"))])
    (row->device row)))

(define (get-device id)
  (define row (select-one "SELECT * FROM devices WHERE id = ?" (list id)))
  (and row (row->device row)))

;; Full row (backend-only): the manager needs the access code it hides
;; from every public projection.
(define (get-device-raw id)
  (select-one "SELECT * FROM devices WHERE id = ?" (list id)))

(define (create-device! name model host serial access-code kind)
  (define id (new-id! "d"))
  (exec! "INSERT INTO devices (id, name, model, host, serial, access_code, kind, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
         (list id name model host serial access-code kind (now-iso)))
  (get-device id))

(define (update-device! id patch)
  (define keys '((name "name") (model "model") (host "host") (serial "serial")
                 (access-code "access_code") (kind "kind")))
  (for ([k (in-list keys)])
    (define key (car k))
    (when (hash-has-key? patch key)
      ;; __SAVED__ sentinel: the UI sends it back unchanged; skip so a
      ;; round-trip of a masked value cannot overwrite the real code.
      (define v (hash-ref patch key))
      (unless (and (string? v) (string=? v "__SAVED__"))
        (exec! (format "UPDATE devices SET ~a = ? WHERE id = ?" (cadr k))
               (list v id)))))
  (get-device id))

(define (delete-device! id)
  (void (exec! "DELETE FROM devices WHERE id = ?" (list id))))

(define (touch-device! id)
  (exec! "UPDATE devices SET last_seen = ? WHERE id = ?"
         (list (now-iso) id)))

;; ---- conversations + messages --------------------------------------------------------

(define (row->conversation row)
  (hasheq 'id (hash-ref row 'id)
          'scope (hash-ref row 'scope)
          'project-id (hash-ref row 'project_id)
          'title (hash-ref row 'title)
          'created-at (hash-ref row 'created_at)
          'updated-at (hash-ref row 'updated_at)))

(define (list-conversations [project-id #f])
  (define rows
    (if project-id
        (select "SELECT * FROM conversations WHERE project_id = ?
                 ORDER BY updated_at DESC" (list project-id))
        (select "SELECT * FROM conversations ORDER BY updated_at DESC")))
  (for/list ([row (in-list rows)]) (row->conversation row)))

(define (get-conversation id)
  (define row (select-one "SELECT * FROM conversations WHERE id = ?" (list id)))
  (and row (row->conversation row)))

(define (create-conversation! scope project-id title)
  (define id (new-id! "c"))
  (define now (now-iso))
  (exec! "INSERT INTO conversations (id, scope, project_id, title, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?)"
         (list id scope project-id title now now))
  (get-conversation id))

(define (delete-conversation! id)
  (void (exec! "DELETE FROM messages WHERE conversation_id = ?" (list id)))
  (void (exec! "DELETE FROM conversations WHERE id = ?" (list id))))

(define (row->message row)
  (hasheq 'id (hash-ref row 'id)
          'conversation-id (hash-ref row 'conversation_id)
          'role (hash-ref row 'role)
          'content (hash-ref row 'content)
          'refs (with-handlers ([exn:fail? (lambda (_) '())])
                  (string->jsexpr (hash-ref row 'refs_json)))
          'confirm (let ([raw (hash-ref row 'confirm_json "")])
                     (if (string=? raw "")
                         #f
                         (with-handlers ([exn:fail? (lambda (_) #f)])
                           (string->jsexpr raw))))
          'created-at (hash-ref row 'created_at)))

(define (list-messages conversation-id)
  (for/list ([row (in-list (select "SELECT * FROM messages WHERE conversation_id = ?
                                    ORDER BY created_at, rowid" (list conversation-id)))])
    (row->message row)))

(define (add-message! conversation-id role content refs confirm)
  (define id (new-id! "msg"))
  (exec! "INSERT INTO messages (id, conversation_id, role, content, refs_json,
                                confirm_json, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)"
         (list id conversation-id role content
               (jsexpr->string refs)
               (if confirm (jsexpr->string confirm) "")
               (now-iso)))
  (exec! "UPDATE conversations SET updated_at = ? WHERE id = ?"
         (list (now-iso) conversation-id))
  (row->message (select-one "SELECT * FROM messages WHERE id = ?" (list id))))

;; ---- settings ------------------------------------------------------------------------

(define (settings-get key [default #f])
  (define row (select-one "SELECT value FROM settings WHERE key = ?" (list key)))
  (if row
      (with-handlers ([exn:fail? (lambda (_) default)])
        (string->jsexpr (hash-ref row 'value)))
      default))

(define (settings-set! key value)
  (exec! "INSERT INTO settings (key, value) VALUES (?, ?)
          ON CONFLICT(key) DO UPDATE SET value = excluded.value"
         (list key (jsexpr->string value)))
  (void))

;; ---- files ---------------------------------------------------------------------------

;; Models and photos live as plain files under files/, referenced by
;; relative path from library rows; durable, backup-friendly, and never
;; synced anywhere.
(define (data-files-dir)
  (define dir (build-path (ensure-app-data-dir!) "files"))
  (unless (directory-exists? dir)
    (make-directory* dir))
  dir)

(define (save-model-file! project-id filename bytes)
  (save-file! (format "~a" project-id) "models" filename bytes))

(define (save-photo-file! project-id filename bytes)
  (save-file! (format "~a" project-id) "photos" filename bytes))

(define (save-file! project-id kind filename bytes)
  (define dir (build-path (data-files-dir) kind project-id))
  (unless (directory-exists? dir)
    (make-directory* dir))
  ;; Keep only safe file names on disk; uniquify on collision.
  (define safe (regexp-replace* #px"[^A-Za-z0-9._-]" filename "_"))
  (define name/ext
    (regexp-match #px"^(.*?)(\\.[^.]+)?$" safe))
  (define stem (second name/ext))
  (define ext (or (third name/ext) ""))
  (define final
    (let loop ([candidate safe])
      (if (file-exists? (build-path dir candidate))
          (loop (format "~a-~a~a" stem (substring (new-id! "x") 2 8) ext))
          candidate)))
  (define path (build-path dir final))
  (call-with-output-file path (lambda (out) (write-bytes bytes out)) #:exists 'truncate)
  ;; Relative path as stored in library rows: kind/project-id/filename.
  (format "~a/~a/~a" kind project-id final))

;; ---- demo seed -------------------------------------------------------------------------

;; Optional first-run sample workbench, clearly labeled 示例 in the UI.
;; Adds only when the library is empty; never merges into real data.
(define (seed-demo!)
  (unless (= (length (list-projects)) 0)
    (error 'seed-demo! "library not empty; refusing to merge demo data"))
  (define now (now-iso))
  ;; --- projects -----------------------------------------------------------
  (define p1 (create-project! "相机快装板"
                              "把 A7C 固定到三脚架云台上，拆装要快；不耐磕碰的场合优先 PETG。关键尺寸已按云台 3/8\" 螺口核对。"
                              "64 × 42 × 9 mm" 4))
  (define p1id (hash-ref p1 'id))
  (define v1 (create-version! p1id "V1" "手绘草图 + 尺寸标注" "" "PETG 黑"))
  (create-version! p1id "V2" "加厚螺口基座 +1.0 mm" "" "PETG 黑")
  (create-version! p1id "V3" "首件实物反馈：卡扣略松" "" "PETG 黑")
  (define v4 (create-version! p1id "V4" "按 V3 实测松旷改卡扣过盈 +0.15 mm" "" "PETG 黑"))
  (set-current-version! p1id (hash-ref v4 'id))
  (define plan-a
    (create-plan! p1id (hash-ref v4 'id)
                  (hasheq 'label "方案 A" 'strategy "结构优先" 'walls 4
                          'infill "25% gyroid" 'supports "无" 'layer-height 0.20
                          'nozzle-temp 220 'bed-temp 100
                          'est-minutes 140 'est-grams 44 'est-layers 184
                          'parts (list (hasheq 'name "主体 · 快装板" 'slot 1
                                               'note "")
                                       (hasheq 'name "提手护套" 'slot 1
                                               'note "与主体同料")))))
  (create-plan! p1id (hash-ref v4 'id)
                (hasheq 'label "方案 B" 'strategy "外观优先" 'walls 5
                        'infill "20%" 'supports "少" 'layer-height 0.16
                        'nozzle-temp 220 'bed-temp 100
                        'est-minutes 175 'est-grams 48 'est-layers 232
                        'parts (list (hasheq 'name "主体 · 快装板" 'slot 1)
                                     (hasheq 'name "提手护套" 'slot 2))))
  (set-recommended-plan! (hash-ref plan-a 'id))
  (set-project-status! p1id "printing")

  (define p2 (create-project! "线材剪托架"
                              "桌面理线用的托架，卡扣式固定，配色跟桌搭。"
                              "80 × 30 × 12 mm" 2))
  (define p2id (hash-ref p2 'id))
  (define v2-1 (create-version! p2id "V1" "首版" "" "PLA 灰"))
  (create-version! p2id "V2" "加宽卡口" "" "PLA 灰")
  (set-project-status! p2id "slicing")

  (define p3 (create-project! "AMS 干燥盖"
                              "AMS 干燥盒的备用盖子，换干燥剂不用拆整盖。"
                              "120 × 90 × 18 mm" 1))
  (define p3id (hash-ref p3 'id))
  (define v3-1 (create-version! p3id "V1" "首版" "" "PLA 米白"))
  (define v3-2 (create-version! p3id "V2" "卡扣加固" "" "PLA 米白"))
  (set-current-version! p3id (hash-ref v3-2 'id))
  (set-project-status! p3id "done")

  (define p4 (create-project! "桌面线夹"
                              "桌面走线的小夹子。"
                              "40 × 20 × 8 mm" 1))
  (define p4id (hash-ref p4 'id))
  (create-version! p4id "V1" "首版" "" "PLA 橙")
  (set-project-status! p4id "failed")

  (define p5 (create-project! "耳机挂钩"
                              "桌沿挂钩，挂头戴耳机。"
                              "70 × 25 × 40 mm" 2))
  (define p5id (hash-ref p5 'id))
  (define v5 (create-version! p5id "V3" "承重加强" "" "PLA 白"))
  (set-current-version! p5id (hash-ref v5 'id))
  (set-project-status! p5id "done")

  (define p6 (create-project! "零食袋封口夹"
                              "只有 brief，还没开工。"
                              "" 1))
  ;; p6 stays idea with brief only — matches the prototype's empty idea card.

  ;; --- history ------------------------------------------------------------
  (define j1 (create-job! p1id (hash-ref v4 'id) (hash-ref plan-a 'id) "" "X1 Carbon"
                          1 4 184 144 48 "PETG 黑" "#2b2b2e"))
  (job-finished! (hash-ref j1 'id) 144 48)
  (define j2 (create-job! p4id "" "" "" "X1 Carbon" 1 1 24 12 4 "PLA 橙" "#c96f1f"))
  (job-failed! (hash-ref j2 'id)
               "首层离板：PEI 板未清洁 + PLA 受潮。教训已写进桌面线夹 brief。" 12 4)
  (create-feedback! p4id (hash-ref j2 'id) "lesson"
                    "首层离板：PEI 板未清洁 + PLA 受潮。教训已写进桌面线夹 brief。" "")
  (define j3 (create-job! p3id (hash-ref v3-2 'id) "" "" "X1 Carbon" 1 1 56 65 21 "PLA 米白" "#d8d3c8"))
  (job-finished! (hash-ref j3 'id) 65 21)
  (define j4 (create-job! p1id "" "" "" "X1 Carbon" 2 4 184 138 46 "PETG 黑" "#2b2b2e"))
  (job-finished! (hash-ref j4 'id) 138 46)
  (define j5 (create-job! p5id (hash-ref v5 'id) "" "" "X1 Carbon" 1 2 92 102 31 "PLA 白" "#e8e6e0"))
  (job-finished! (hash-ref j5 'id) 102 31)
  (define j6 (create-job! p3id (hash-ref v3-1 'id) "" "" "X1 Carbon" 1 1 52 58 19 "PLA 米白" "#d8d3c8"))
  (job-finished! (hash-ref j6 'id) 58 19)
  (define j7 (create-job! p5id "" "" "" "X1 Carbon" 1 1 76 81 26 "PLA 灰" "#9a978f"))
  (job-finished! (hash-ref j7 'id) 81 26)
  (define j8 (create-job! p2id (hash-ref v2-1 'id) "" "" "X1 Carbon" 1 1 64 72 24 "PLA 灰" "#9a978f"))
  (job-finished! (hash-ref j8 'id) 72 24)
  ;; The live printing job — drives the dashboard layerbar like the prototype.
  (define live
    (create-job! p1id (hash-ref v4 'id) (hash-ref plan-a 'id) "" "X1 Carbon"
                 3 4 184 140 44 "PETG 黑" "#2b2b2e"))
  (job-started! (hash-ref live 'id))
  (job-progress! (hash-ref live 'id) 114)
  ;; Curated final states: job lifecycles above already moved several
  ;; projects (a finished demo job flips its project); reassert what the
  ;; prototype filter row shows.
  (set-project-status! p1id "printing")
  (set-project-status! p2id "slicing")
  (set-project-status! p3id "done")
  (set-project-status! p4id "failed")
  (set-project-status! p5id "done")

  ;; --- feedback archive ------------------------------------------------------
  (create-feedback! p3id "" "photo" "装上后贴合，换干燥剂不用拆整盖" "")
  (create-feedback! p5id "" "photo" "挂了两周没掉，承重够用" "")

  ;; --- materials ------------------------------------------------------------
  (create-material! (hasheq 'name "PETG 黑" 'brand "Bambu" 'type "PETG"
                            'color-name "黑" 'color-hex "#2b2b2e"
                            'remaining-g 820 'total-g 1000
                            'opened-date "2026-10-12" 'slot 1 'status "ok"))
  (create-material! (hasheq 'name "PLA 米白" 'brand "Bambu" 'type "PLA"
                            'color-name "米白" 'color-hex "#d8d3c8"
                            'remaining-g 450 'total-g 1000
                            'opened-date "2026-10-05" 'slot 2 'status "ok"))
  (create-material! (hasheq 'name "PLA 橙" 'brand "第三方" 'type "PLA"
                            'color-name "橙" 'color-hex "#c96f1f"
                            'remaining-g 120 'total-g 1000
                            'opened-date "2026-08-15" 'slot 0 'status "moisture-risk"
                            'notes "受潮风险 · 已开封 90 天"))
  (create-material! (hasheq 'name "PETG 灰" 'brand "Bambu" 'type "PETG"
                            'color-name "灰" 'color-hex "#8a8d91"
                            'remaining-g 1200 'total-g 1500
                            'opened-date "" 'slot 0 'status "ok"))
  (create-material! (hasheq 'name "PLA 透明" 'brand "第三方" 'type "PLA"
                            'color-name "透明" 'color-hex "#e3e6e8"
                            'remaining-g 350 'total-g 1000
                            'opened-date "2026-09-20" 'slot 0 'status "ok"))

  ;; --- shopping + purchases ----------------------------------------------------
  (create-shopping-item! "PETG 黑 · 1 卷" 1 89 "ai")
  (create-shopping-item! "AMS 干燥剂" 2 35 "manual")
  (create-shopping-item! "P1S 备用喷嘴" 1 49 "manual")
  (define pur1 (create-purchase! "PETG 黑" 2 178))
  (purchase-arrived! (hash-ref pur1 'id))
  (define pur2 (create-purchase! "PEI 清洁剂" 1 25))
  (purchase-arrived! (hash-ref pur2 'id))

  ;; --- device ------------------------------------------------------------------
  ;; reuse an existing fixture device (first-run onboarding may have made
  ;; one); the demo only registers a printer when the list is empty
  (unless (> (length (list-devices)) 0)
    (create-device! "X1 Carbon" "X1 Carbon" "192.168.1.34" "" "" "fixture"))
  ;; --- advisor conversation -------------------------------------------------------
  (define conv (create-conversation! "advisor" "" "耗材与回抽"))
  (add-message! (hash-ref conv 'id) "user"
                "X1 最近打 PETG 总有点拉丝，是温度问题还是料受潮了？"
                '() #f)
  (add-message! (hash-ref conv 'id) "advisor"
                "对照你的打印记录，最近 3 次拉丝都出现在同一类行程上——大概率是回抽不足，不是受潮。建议：回抽行程 +0.2mm（0.8 → 1.0mm），并把腔温升到 50°C 再开始打印。\n另外提醒：AMS 槽位 3 的 PLA 橙已开封 90 天，确有受潮风险，但这次拉丝的主因是回抽。"
                (list "历史 · 3 次拉丝记录" "AMS 槽位 3" "维护页")
                #f)
  (add-message! (hash-ref conv 'id) "user" "PLA 橙还能用吗？" '() #f)
  (add-message! (hash-ref conv 'id) "advisor"
                "还能用，但要分打什么。受潮的 PLA 容易出水纹和气孔——外观件不建议再用它；打结构件、夹具这类非外观件没问题。两条路：烘干 4h（55°C）后继续用，或者直接降级，专打非外观件。"
                (list "材料库" "AMS 槽位 3") #f)
  (add-message! (hash-ref conv 'id) "advisor"
                "把 PLA 橙标记为『降级 · 非外观件专用』"
                '()
                (hasheq 'kind "material-status"
                        'label "待你确认"
                        'body "把 PLA 橙标记为『降级 · 非外观件专用』"
                        'impact "材料库 1 处修改 · 可撤销"
                        'action "downgrade-material"
                        'args (hasheq 'material "PLA 橙")))
  (void))
