# Architecture evidence

Source review: `5e99e50cebf50521b9da35969dcc533942615ec5` (2026-10-09).

The marked Mermaid block in [README](../../README.md) is the only maintained diagram source. GitHub renders it natively in the reader's theme. No duplicate SVG or independent `.mmd` is committed; extracted Mermaid and SVG files are disposable verification artifacts.

The diagram describes mutation commands; Status only reads selection metadata, and Init saves state without switching config. The file lock wraps reading/validation and mutation; it does not coordinate with other editors. Write-ConfigChange rechecks the original text before backup and atomic replacement.

DeepSeek is the legacy command name for one saved custom provider, not a hard-coded remote service. Saved fragments are validated before restoration. Full backup rollback is manual, distinct from restoring the saved provider selection. A login/diagnostic failure does not roll back the config automatically. Auth credentials are owned by the optional Codex subprocess; state/backups can contain secrets already embedded in config and must stay private.

## Source map

- [codex-mode.ps1](../../codex-mode.ps1): `function Assert-ConfigShape`, `function Save-ProviderState`, `function Read-ProviderState`, `function Write-ConfigChange`, `function Write-AtomicText`, `[IO.FileShare]::None`, `function Invoke-CodexCheck`
- [tests/codex-mode.Tests.ps1](../../tests/codex-mode.Tests.ps1): `Describe`

The anchors in `evidence.json` catch renamed/deleted source symbols; they do not prove call semantics. The source review above checked the actual call sites and boundaries. A significant change to data flow, persistence, authentication, recovery or process boundaries requires reviewing this diagram and updating the evidence. Routine edits do not require redrawing it.

## Verification

Requires Python 3, Node.js 22+ and network access for the documentation-only Mermaid CLI. From the repository root:

```sh
python docs/architecture/verify.py --render
```

This checks local README image references and source anchors, extracts the authoritative block, renders it twice with Mermaid CLI 11.12.0 using deterministic IDs, compares SVG bytes, validates SVG XML, and also renders the dark theme. If the bundled browser is unavailable, pass `--chrome /absolute/path/to/chrome` (or set `PUPPETEER_EXECUTABLE_PATH`). The CLI version is pinned; its transitive npm dependencies and the browser are environment-dependent, so the byte comparison proves repeatability within the same installed toolchain. Output goes to a temporary directory, never application runtime dependencies. GitHub Markdown/browser rendering still requires visual review; CLI validation alone is not evidence of GitHub rendering.

GitDiagram returned an initial diagram on 2026-10-09 for the public repository as a discovery aid. Its page reported **0 source files read**, so its README-derived connections were checked directly against the local PowerShell source. Its generated output is not imported as authoritative architecture or licensed artwork. No private source, config or credentials were submitted.

Existing repository licenses and third-party notices continue to apply. These diagrams are documentation authored from this repository's public source; no app icons, installer assets or third-party marks are replaced.
