<div align="center">

# Codex Mode Switcher

**A small PowerShell tool for switching Codex provider and authentication selection.**

**Status:** 🟡 Initial release · **Version:** `0.1.0`

[Quick Start](#quick-start) · [Usage](#usage) · [Architecture](#architecture) · [中文说明](docs/README.zh-CN.md) · [Releases](https://github.com/styayur/codex-mode-switcher/releases) · [Issues](https://github.com/styayur/codex-mode-switcher/issues)

[![CI](https://github.com/styayur/codex-mode-switcher/actions/workflows/ci.yml/badge.svg)](https://github.com/styayur/codex-mode-switcher/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/styayur/codex-mode-switcher)](https://github.com/styayur/codex-mode-switcher/releases/latest)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![PowerShell 7.4+](https://img.shields.io/badge/PowerShell-7.4%2B-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6)

</div>

Switch between **ChatGPT OAuth / Codex plan usage** and **one saved custom API
provider**, such as DeepSeek, without repeatedly editing `~/.codex/config.toml`.
The script saves provider state, backs up configuration before changes, and restores
the provider's original model and endpoint settings. It has no runtime module dependencies.

This is an independent community project, unaffiliated with OpenAI or DeepSeek.

## Quick Start

Requirements: Windows, PowerShell **7.4+**, and a working Codex CLI installation for
login and diagnostics. Configuration-only commands also work without Codex in PATH.
Use your normal user account; administrator access is unnecessary.

Download `codex-mode.ps1` from the [release](https://github.com/styayur/codex-mode-switcher/releases/latest)
or clone this repository. Review the script first. If Windows attaches Mark of the Web
(MOTW) to the download, `Unblock-File` can remove that mark:

```powershell
Unblock-File .\codex-mode.ps1
```

The script never changes ExecutionPolicy. Unblocking does not override an enforced
organization policy or an AllSigned requirement; follow your administrator's policy.

Start with your **already working custom provider configuration** selected in Codex:

```powershell
.\codex-mode.ps1 Init
.\codex-mode.ps1 Status
.\codex-mode.ps1 GPT
.\codex-mode.ps1 DeepSeek
.\codex-mode.ps1 Toggle
```

`DeepSeek` is the original command name: it restores whichever single custom provider
you saved, even if that provider has another ID. The script does not create a new API
account, choose a DeepSeek model, or install a protocol adapter.

Close active Codex tasks and configuration editors before switching. Start a new CLI
session or restart the client afterward; running threads may retain earlier settings.

## Authentication and billing

**ChatGPT OAuth is not an OpenAI API key.** Codex supports ChatGPT sign-in and API-key
authentication as separate options. ChatGPT sign-in uses eligible plan access (including
Plus); API-key access uses the provider's API billing. This script does not grant access
or change quotas. See [Codex authentication](https://learn.chatgpt.com/docs/auth).

Codex can keep its ChatGPT login while a custom provider is selected. A provider using
`env_key` with `requires_openai_auth = false` takes its API credential from that environment
variable. `requires_openai_auth = true` instead uses OpenAI authentication and ignores
`env_key`, so review your provider setup before saving it.

The script never reads, copies, deletes, or rewrites the credential store itself. Its
optional `codex login` command delegates authentication to Codex, which may update that
store. `Status` reports configuration and a login-status exit code; neither proves that
an inference request will succeed.

## Usage

| Command | Behavior |
| --- | --- |
| `Status` (default) | Report current provider/model, login rule and state-file presence; no local filesystem writes. |
| `Init` | Back up config and save the active custom provider. With OpenAI or no config, preserve existing saved state. |
| `GPT` | Save the active custom provider, select `openai` and force `chatgpt` login. Remove custom model/catalog/endpoints. |
| `DeepSeek` | Validate and restore saved selectors and provider tables into the current config. |
| `Toggle` | OpenAI/default → saved provider; any active custom provider → GPT. |

GPT leaves the model unset so Codex/account defaults choose it. MCP, sandbox, projects,
other providers, and other root settings are retained. Edits to those settings made
while in GPT mode also survive restoration.

Repeated GPT and DeepSeek produce stable configuration. Repeated Init safely refreshes
the saved provider and creates backups. Init while in GPT does not replace custom state.
Only one custom state is stored: saving another replaces it, with the previous state backed up.
Restoring while a different custom provider is active fails until you explicitly save it.

```powershell
# Local config only: no login queries, browser flow, or doctor
.\codex-mode.ps1 GPT -NoLogin -SkipDoctor

# Separate Codex home for this shell; default is Join-Path $HOME '.codex'
$env:CODEX_HOME = Join-Path $HOME 'codex-alternate'
.\codex-mode.ps1 Status -NoLogin
```

`-NoLogin` skips all Codex login commands, including Status/Init queries. `-SkipDoctor`
skips GPT diagnostics. Otherwise GPT checks for a ChatGPT login and invokes `codex login`
when the status command fails or does not identify ChatGPT. This depends on Codex's
English status label. Doctor runs only if advertised in `codex --help`; failures warn
without rolling back the saved configuration. Login failure reports an error after the
configuration has been saved.

## Architecture

```text
codex-mode.ps1
  -> $env:CODEX_HOME or $HOME/.codex
     -> config.toml                    current user-level selection
     -> mode-switcher/
        -> deepseek-state.json         saved provider selectors and tables
        -> backups/config.*.toml       exact pre-change configuration
        -> backups/state.*.json        previous saved provider state
        -> .lock                       serializes this script's writes

GPT:      capture custom state -> back up config -> select OpenAI / ChatGPT
DeepSeek: validate saved state -> back up config -> restore custom provider
```

Saved root keys: `model`, `model_provider`, `model_catalog_json`, `openai_base_url`,
`chatgpt_base_url`, and `forced_login_method`. The active `[model_providers.<id>]`
table and its nested tables are saved. The legacy state filename and valid pre-release
state files without a schema version remain supported.

Config and state writes use a same-directory temporary file and atomic file replacement.
Config is checked for concurrent edits before replacement. The lock coordinates this
script's invocations; external applications do not honor it. Backups are created before
each config change; Init also backs up an existing config. No config exists to back up
on the first GPT command in an empty home.

## Recovery

A missing/corrupt saved state stops restoration without altering config. A valid saved
state can restore selectors into a missing config, but cannot recover unrelated settings
that were in that missing file. For full recovery, inspect and select a config backup:

```powershell
$codexDir = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
Get-ChildItem (Join-Path $codexDir 'mode-switcher/backups') -Filter 'config.*.toml'
# Select and review the required backup before copying it to config.toml.
```

## Security

- Keep API keys in environment variables or your credential manager, never this repository.
- The tool does not extract keys from the environment or include them in state or status output.
- Provider state contains configuration fragments; backups contain the full config.
  If your config has embedded keys, static authorization headers or private paths, those
  will also be in these local files. Migrate secrets to `env_key`/environment headers first.
- `.gitignore` excludes auth files, local config/state/backups, environments, common key/token
  filenames, databases, logs and sessions. It cannot detect a secret in any arbitrary filename.
- Treat the Codex home, state and backups as private local data. Do not attach them to issues.
- No automatic cleanup deletes backups or session data. Review disk usage yourself.

See [SECURITY.md](SECURITY.md) for private vulnerability reporting.

## Testing

CI uses a Windows runner, PowerShell syntax parsing, PSScriptAnalyzer **1.25.0**, and
Pester **5.7.1**. Install these development dependencies and run:

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -RequiredVersion 1.25.0 -Scope CurrentUser -Force
pwsh -NoProfile -File .\scripts\Test-Project.ps1
```

Tests use isolated temporary Codex homes and synthetic endpoints. They exercise Status,
Init, both selections, Toggle, repeated operations, custom home paths, byte-exact backups,
missing/corrupt/injected state, unsupported configuration, locks and unrelated settings.
They do not contact real providers or use real credentials.

## Limitations

- This is a conservative line editor, not a full TOML parser. Use ordinary single-line
  assignments, bare managed root keys and bare provider table names/IDs. Multiline values,
  quoted provider table components and provider array tables are rejected before mutation.
  Unrelated quoted project headers, one-line arrays and unrelated array tables are preserved.
  Start from valid TOML; unrelated values are not fully syntax-validated.
- Only user-level config is changed. Project/profile/managed settings or CLI overrides can
  take precedence. Existing threads may keep their provider/model settings.
- Only one saved custom provider is managed. There is no provider registry or UI.
- Protocol support depends on the Codex version and endpoint. Current Codex configuration
  documents `wire_api = "responses"`; direct DeepSeek connectivity or a Chat Completions
  endpoint is not guaranteed. Supply a compatible working endpoint/adapter yourself.
  See [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Windows PowerShell 5.1 is unsupported. Windows is the tested platform. The script is unsigned.
- Atomic replacement requires filesystem support. External editors can still race the final
  write; the script's lock is not an operating-system-wide Codex configuration lock.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Keep changes small, add regression coverage for
configuration behavior, and use only synthetic fixtures in reports and tests.

## License

[MIT](LICENSE), following the Stya Yur Open Source Studio
[license policy](https://github.com/styayur/styayur/blob/main/LICENSE_POLICY.md) for small
scripts and automation. OpenAI, Codex, ChatGPT and DeepSeek names belong to their respective owners.
