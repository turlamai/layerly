# Security Policy

Layerly is local-first: projects, materials and print history live in a
local database in the app data directory, printer access is LAN-only,
and LLM API keys are held by the backend (never rendered in the UI) and
sent only to the endpoint you configure. Reports are taken seriously and
handled quickly.

## Reporting a vulnerability

Email **security@jrtx.site** (or open a GitHub security advisory on this
repository). Include reproduction steps, affected versions, and your
assessment of impact. You will get an acknowledgment within 72 hours.

Please do not open public issues for security problems.

## Scope

In scope:

- Device credential handling (printer access codes, secure storage)
- LLM API key storage and the redaction path of anything sent to a
  configured endpoint
- The loopback/API transport between the webview and the backend
- Update artifact signature verification

Out of scope:

- The printer vendor's own cloud services and firmware
- Third-party LLM endpoints you configure yourself
- Social engineering of the user into printing dangerous objects
  (safety guidance is advisory by design)
