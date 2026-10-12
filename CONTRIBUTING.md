# Contributing

Use Issues for reproducible bugs and scoped proposals. Report vulnerabilities privately
as described in [SECURITY.md](SECURITY.md). Contributions use the project's MIT License.

## Development checks

Use Windows and PowerShell 7.4+. Install Pester 5.7.1 and PSScriptAnalyzer 1.25.0 as shown
in the README, then run `pwsh -NoProfile -File ./scripts/Test-Project.ps1`. This is the same
command used in CI. Import Pester before lint to avoid autoloading a different assembly.

Run `python docs/architecture/verify.py` after source/docs changes. Diagram changes also
require the pinned Mermaid render check described in [architecture docs](docs/architecture/README.md).
Node/Python are development tools; keep the shipped controller free of external runtime modules.

## Safety and scope

Tests must isolate CODEX_HOME in TestDrive and mock Desktop discovery/activation. Use only
synthetic endpoints such as example.invalid. Never switch the developer's real config,
launch/close real Desktop, contact providers, or read credentials/sessions in automation.
Fault tests should check before/after bytes and the transaction/launch boundary, not only
mock call counts. Preserve existing regression scenarios; document intentional compatibility
changes rather than silently dropping tests.

Keep Desktop-only, Native-first and Zero-resident scope. Do not add a gateway, GUI, daemon,
CLI profile launcher, forced termination or private Desktop API. Preserve unrelated config,
back up before writes and refuse unsupported/ambiguous state. Update both language guides,
troubleshooting, architecture evidence and CHANGELOG for behavior changes.

Before a PR, run the full checks, review staged changes for credentials/private paths and
scan tracked files/history with a secret scanner. Do not publish raw host diagnostics.
Report mocked tests, read-only Windows observations and actual Desktop E2E separately.
Record interactive acceptance separately using [DESKTOP-VALIDATION.md](docs/DESKTOP-VALIDATION.md).
The v0.2.1 integration release explicitly retains those unverified Desktop limits; do not
describe mock/native-file tests as live UI or provider acceptance.

Integration tests must mock Get-IntegrationContext into TestDrive. Native Shell shortcut
creation is allowed only there; real toast submission, Start Menu installation and Terminal
settings changes are forbidden in automated tests. Build distributable archives from clean
tracked source using scripts/Build-Release.ps1, never zip the whole working directory.
