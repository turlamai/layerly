# Layerly

**Product:** [Website](https://jrtx.site/products/layerly/) · **Support:** [Issues & feedback](https://github.com/turlamai/layerly/issues) · [Development policy](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.md)

**From idea to object — a local-first 3D printing workbench.**

**English** · [简体中文](README.zh-CN.md)

> **Development preview — skeleton stage.** This is a design/architecture implementation, not a released consumer app. There is no verified installer, paid edition, checkout or trial expiry.

## The workflow

Layerly aims to keep a printed object's lifecycle together: the brief, design iterations, 3D model, slicer plan, filament/materials, print attempts and finished photos. A BYOK AI advisor may explain and draft, but sending a print, buying materials and deleting content require an explicit human decision.

The core workflow is local. Printer access is intended over the LAN without a required cloud account. **These are design goals, not proof that all integration paths work today.**

## Platforms and status

Target platforms are macOS, Windows and Linux using [Glaze](https://github.com/turlamai/glaze), a Racket backend and a native system WebView. Current work starts at [design/DESIGN.md](design/DESIGN.md) and [design/prototype](design/prototype/).

No published installer has completed packaged acceptance. Do not use the present skeleton to control a production printer unattended.

## Developer quick start

Prerequisites: Racket and the `glaze` package; Node.js 22+ and pnpm; WKWebView (macOS), WebView2 (Windows) or WebKitGTK (Linux).

```sh
pnpm install
pnpm build          # frontend -> apps/desktop/dist
raco glaze dev      # developer host
raco test backend/  # backend unit tests
raco glaze schema check --json
pnpm check          # frontend type check
```

Commands are developer workflows and do **not** establish production package readiness.

## Data, privacy and recovery

Core records are intended to stay on the local computer. Critical actions require confirmation. Persistent formats, backups, migrations and reliable recovery must be tested before product release; do not trust a prototype with irreplaceable work.

## Feedback

File an [issue](https://github.com/turlamai/layerly/issues) with a minimal reproducible scenario, OS/toolchain, and non-confidential sample models. See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidance.

## License

[AGPL-3.0](LICENSE). No code from noncommercially licensed projects is included. The [family delivery policy](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.md) does not change existing license rights.
