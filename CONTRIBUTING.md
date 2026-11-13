# Contributing to Layerly

Thank you for looking under the hood. Layerly is free software
(AGPL-3.0, see [LICENSE](LICENSE)): by submitting a pull request you
agree your contribution is licensed under AGPL-3.0.

## Ground rules

1. **The glaze schema is the contract.** `glaze.rktd` and
   `glaze-schema.json` own the reviewed application contract between
   the Racket backend and the UI. Run `raco glaze schema check --json`
   before merging an API change; update the baseline only with
   `raco glaze schema write` and review the diff.
2. **Ownership boundaries are fixed.** `backend/main.rkt` owns routes,
   events and window behavior; `backend/library/` owns project, material
   and print-history storage; `backend/device/` owns the printer bridge
   (LAN-only, credentials never leave the backend); `backend/ai/` owns
   BYOK settings and LLM calls; `apps/desktop/` and `packages/core/`
   own the web UI and the typed bridge. Business logic does not live in
   the shell.
3. **AI proposes; the user dispatches.** Advisor roles explain, compare
   and draft. No AI path starts a print job, places an order, or deletes
   archived objects by itself — every one of those actions has an
   explicit confirmation step in the UI.
4. **Prototype first.** UI changes start in `design/prototype/` (see
   `design/DESIGN.md`), land there first, and are then carried into the
   implementation. `design/prototype/shared.css` is the single source
   for visual tokens.
5. **Independent implementation.** Do not copy code, documents or
   assets from noncommercially-licensed projects. Write original code,
   copy and assets only.

## Development

```sh
pnpm install
pnpm build          # build the frontend into apps/desktop/dist
raco glaze dev      # run the native app
raco test backend/  # backend unit tests
raco glaze schema check --json
pnpm check          # frontend type check
```
