# Contributing

Use Issues for reproducible bugs and small, scoped feature proposals. Report security
issues privately as described in [SECURITY.md](SECURITY.md).

## Development

Use Windows and PowerShell 7.4+. Install Pester 5.7.1 and PSScriptAnalyzer 1.25.0 using
the commands in the README, then run `pwsh -NoProfile -File ./scripts/Test-Project.ps1`.
The same command runs in CI. Pester must be loaded before analysis to avoid autoloading
another installed version during command discovery.

Tests must set CODEX_HOME to an isolated temporary directory, use synthetic endpoints
such as example.invalid, and avoid real login/API calls. Never exercise switches against
your real Codex home as an automated test. Do not add real keys or account data to fixtures.

## Changes

Keep the single-script runtime dependency-free. Preserve unrelated configuration and
back up before modifications. For a new configuration case, add a regression that
checks the observable result and recovery behavior. Unsupported syntax should fail
before mutation rather than be partially interpreted. Update both language guides when
command behavior changes and record user-visible changes in CHANGELOG.md.

Before a pull request, run the complete checks and inspect `git diff --cached` for
credentials, local paths and private data. Describe the problem, resulting behavior and
validation. Contributions are provided under this project's MIT License.
