# Layerly

> AI-native 3D printing workbench — from idea to object.

Layerly is a desktop workbench for personal 3D printing: it keeps the
whole life of an object in one place — the brief, the design versions,
the model, the slice plans, the material it was printed in, the print
records and the photos of the finished part — and puts an AI advisor
next to that library. The advisor knows your printer, your filaments
and your past prints; it explains, compares and drafts, while every
action that matters (dispatching a print, buying filament, deleting an
archive) stays an explicit decision of yours.

Everything runs locally on your machine. Printer access is LAN-only;
no cloud account is required for core flows.

## Status

Skeleton stage. The design baseline (`design/DESIGN.md` +
`design/prototype/`) precedes implementation, per the family's
prototype-first flow.

## Requirements

- Racket (with the `glaze` package) and a native system WebView
  - macOS: WKWebView (built in)
  - Windows: WebView2
  - Linux: WebKitGTK
- Node.js 22+ and pnpm

## Development

```sh
pnpm install
pnpm build          # build the frontend into apps/desktop/dist
raco glaze dev      # run the native app
raco test backend/  # backend unit tests
raco glaze schema check --json
pnpm check          # frontend type check
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for ground rules, and
[README.zh-CN.md](README.zh-CN.md) for the full Chinese readme.

## License

[AGPL-3.0](LICENSE). Layerly is an independent implementation; it does
not contain code from noncommercially-licensed projects.
