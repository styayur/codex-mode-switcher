# Changelog

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
