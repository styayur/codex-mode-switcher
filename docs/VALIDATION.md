# v0.1.0 validation record

Release preparation: 2026-10-04.

## Local checks

- Windows with PowerShell 7.6.5.
- PowerShell parser: all maintained PS1/PSD1 files parsed successfully.
- PSScriptAnalyzer 1.25.0: zero unsuppressed warnings or errors. WriteHost is
  intentional for CLI output; the synthetic CLI test's global state has a scoped
  suppression and is removed after tests. Production code has no such suppression.
- Pester 5.7.1: 40 tests passed, zero failures/skips. Tests use temporary Codex homes,
  synthetic provider endpoints and a synthetic CLI for optional login/doctor calls.
- Git ignore checks: credential/environment/key/token names, local provider state,
  backups, SQLite, logs, sessions and original source materials are excluded.
- TruffleHog 3.97.9: the maintained publication files returned zero findings with
  credential verification disabled (no credentials submitted to provider APIs).
- Additional path/key pattern review found no original machine paths, key-like API
  credentials, GitHub tokens, JWTs or private-key blocks in publication files.

The raw development log and original Chinese guide contain local machine/session
details. They are retained privately as ignored local source materials, outside Git
history and release assets. Their useful observations are summarized in CHANGELOG.md.

## Scope

Tests verify configuration behavior and recovery paths. This release does not claim a
fresh live ChatGPT or DeepSeek inference test. Supplied historical diagnostics are
described separately in CHANGELOG.md. The current protocol requirements and precedence
limitations are documented in the README.

The [CI workflow](https://github.com/styayur/codex-mode-switcher/actions/workflows/ci.yml)
runs syntax, lint and the same Pester suite on Windows. Check the successful run for the
tag's commit rather than assuming this local record proves remote CI execution.
