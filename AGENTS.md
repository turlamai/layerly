# Layerly agent contract

Human-first. Agent-native. Local by design.

Start with `raco glaze inspect --json` and `raco glaze doctor --json`.
Run `raco glaze schema check --json` before merging an API change.

## 实现路由（agent 按任务读真源）

- 实现界面以 `design/prototype/` 为准：对照 HTML/CSS/JS 与实物截图验收，不依赖散文复述。
- Token/几何值真源 = `design/prototype/shared.css`（亮暗成对）；`design/DESIGN.md` 只记语义名、用途与决策。
- 行为边界与跨平台一致性以 `design/DESIGN.md` 的不变式与平台差异节为准。
- 改界面先改原型再改实现（tlai-prototype-flow）；动共享层（design/）先 issue 声明，同 commit 落契约。

## Family policy (re-read at every slice boundary)

Record the SHA of each document you worked against:

- Product standard: https://github.com/turlamai/turlamai.github.io/blob/main/docs/PRODUCT-STANDARD.md — SHA:
- Documentation languages: https://github.com/turlamai/turlamai.github.io/blob/main/docs/DOCUMENTATION-LANGUAGES.md — SHA:
- Portfolio: https://github.com/turlamai/turlamai.github.io/blob/main/PORTFOLIO.md — SHA:

## Ownership boundary

- `backend/main.rkt` owns Racket routes, events and window behavior.
- `backend/library/` owns the project library: projects, design versions,
  model files, slice plans, print history and feedback records
  (SQLite + durable files in the app data directory).
- `backend/device/` owns the printer bridge. Printer access is LAN-only
  and local-first: no cloud account is required for core flows. Device
  credentials live in backend-held secure storage and never enter the
  webview.
- `backend/ai/` owns BYOK settings, advisor prompts and LLM calls.
  API keys are held by the backend and never enter the webview; the UI
  sees the `__SAVED__` sentinel.
- `apps/desktop/` and `packages/core/` own the web UI and the typed
  bridge. Business logic does not live in the shell.
- `glaze-schema.json` is a reviewed release contract; update it with
  `raco glaze schema write` and review the diff.
- `dist/`, `apps/desktop/dist/`, `compiled/` are generated output.

## AI governance (family invariant)

AI proposes; the user dispatches. Advisor roles explain, compare and
draft; nothing prints, spends or deletes without an explicit user
confirmation step in the UI. No AI path starts a print job, places an
order, or removes archived objects by itself. Every LLM send path keeps
context redaction explicit and previewable.

## Provenance boundary

Layerly is an independent implementation. Do not copy code, documents or
assets from noncommercially-licensed projects (including the PrintLab
repository, PolyForm Noncommercial 1.0.0). Workflow concepts are not
copyrightable; their expression is. Write original code, original copy
and original assets only.

## Release procedure

发布 = 同值三处：`package.json` 的 version、`backend/main.rkt` 的
`app-version`、`CHANGELOG.md` 顶部 `## [version]` 段 → 推 annotated
tag `v*`，`release.yml` 三平台打包并校验一致性。轻量 tag 会被
validate job 拒绝。

## Verification floor

- `raco test backend/` — unit tests (needs no display).
- `raco glaze schema check --json` — API contract.
- `pnpm check && pnpm build` — frontend types + bundle.
- Manual slice: connect to a printer (or the synthetic fixture) and walk
  one project from brief to archived print before any release tag.

## 设计流程（原型先行）

所有 UI 开发与界面改造一律先原型后代码：brief → `design/DESIGN.md`
视觉契约 → HTML 原型 → 按 HIG 基准评审通过才开工；改界面先改原型再改
代码。契约与原型放本仓 `design/`，实物截图验收后才能作为对外宣传素材。
