# Changelog

## [0.2.0] - Unreleased

### Added

- Windows Desktop Controller with explicit Launch, bounded normal-exit coordination,
  structured Diagnose, DryRun and NonInteractive modes. No Desktop/task termination.
- Registered MSIX AUMID discovery and public Windows activation; signed Win32 GUI
  executable validation. Exact executable-path process matching, with Unknown on ambiguity.
- Journaled config/provider/GPT-state transactions: verified byte backups, atomic file
  replacement, concurrent-edit checks and conditional pre-commit rollback/recovery.
- Explicit profile shortcut install/preview/uninstall with backups and conflict refusal.
- Isolated Desktop lifecycle, discovery, fault/recovery and profile regression coverage;
  architecture, troubleshooting and separate mocked/native/manual acceptance records.

### Changed

- GPT now retains native model and reasoning selection through custom-provider round trips.
- Managed TOML key matching respects case, preserving unrelated case-distinct keys.
- Original commands and legacy provider state remain compatible. NoLogin/SkipDoctor remain
  accepted but no longer invoke CLI login/doctor. Authentication stays in Desktop.
- Config-only mutations also refuse a running or unidentifiable Desktop. The complete src/
  directory is now required beside the entry script.

### Safety boundaries and pending acceptance

- Startup failure after a durable commit does not roll back config. Changes detected after
  commit stop activation while preserving newer data. Process observation is not provider
  verification; task activity remains unknown without user attestation.
- MSIX launch with custom CODEX_HOME is conservatively refused pending environment evidence.
- Real Windows MSIX discovery was observed read-only. Actual MSIX/Win32 launch, new-task
  provider selection and credential environment E2E remain required before release.

[0.2.0]: https://github.com/styayur/codex-mode-switcher/compare/main...feat/desktop-controller-v0.2.0

## [0.1.0] - 2026-10-04

### Added

- First public MIT release with English and Chinese documentation, security and
  contribution guidance, and a Windows CI workflow for syntax, lint and Pester.
- Regression coverage using isolated Codex homes and synthetic provider fixtures.
- State validation, legacy state compatibility, unique config/state backups,
  atomic file writes and a lock for concurrent script invocations.
- Read-only Status and safe failures for missing, corrupt or inconsistent state.

### Changed

- Retained Init, GPT, DeepSeek, Toggle and Status plus NoLogin/SkipDoctor switches.
  DeepSeek continues to mean restoration of the single saved custom provider.
- GPT selects OpenAI with ChatGPT authentication and leaves model selection to
  Codex/account defaults. Custom selectors and provider tables are restored separately
  from unrelated MCP, sandbox and project settings.
- Repeated selections no longer accumulate management comments or provider tables.
- NoLogin also skips Status/Init login queries. Doctor is called only when advertised
  by the installed CLI. Successful API-key login status no longer counts as ChatGPT login.
- Unsupported multiline/quoted managed TOML forms stop mutation instead of risking
  a partial or ambiguous provider capture.

### Historical validation retained from the development log

The supplied pre-release notes describe Windows 11, PowerShell 7.6.6 and Codex CLI
0.159.2. They record custom-provider capture via Init while ChatGPT remained logged in,
followed by a GPT switch selecting OpenAI/ChatGPT. Codex diagnostics loaded config,
recognized ChatGPT authentication, completed a WebSocket handshake and reached the
ChatGPT endpoint. The diagnostic summary had zero failures but environment warnings.

The log also demonstrates a downloaded script being blocked by MOTW and succeeding
after Unblock-File. Raw doctor output, personal paths, session identifiers and machine
inventory are intentionally excluded from the public repository.

These are historical single-environment observations. The raw log does not demonstrate
a live DeepSeek inference request, a DeepSeek restore, or Toggle. Restoration and Toggle
are covered by the release's isolated regression suite, not by claims of live API testing.

[0.1.0]: https://github.com/styayur/codex-mode-switcher/releases/tag/v0.1.0
