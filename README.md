# Codex Mode Switcher

Switch Codex Desktop between GPT and one saved custom provider configuration, with preview, guarded transactions and conditional recovery.

**Windows · PowerShell-native · CLI-first · Read-only-first · Reversible operations · Minimal dependencies**

[![CI](https://github.com/styayur/codex-mode-switcher/actions/workflows/ci.yml/badge.svg)](https://github.com/styayur/codex-mode-switcher/actions/workflows/ci.yml)
[中文说明](docs/README.zh-CN.md) · [Releases](https://github.com/styayur/codex-mode-switcher/releases) · [Recovery](docs/TROUBLESHOOTING.md)

For people who already have a working custom provider in Codex Desktop and want to stop editing `config.toml` by hand. The tool saves one provider and native GPT model/reasoning selections. Windows Terminal, Start Menu and notifications are optional integrations.

**Live Desktop provider end-to-end behavior remains unverified.** Observing an application process does not prove that it loaded a provider. This is an independent community tool, unaffiliated with OpenAI or DeepSeek.

## Quick start

Use **Windows and PowerShell 7.4+**, as your normal user. No administrator access, Codex CLI or third-party runtime module is required. Keep the whole distribution, including `src/`.

```powershell
git clone https://github.com/styayur/codex-mode-switcher.git
cd codex-mode-switcher
pwsh -NoProfile -File ./codex-mode.ps1 Diagnose -Json
```

`Diagnose` reads local configuration and Windows application metadata; it does not write configuration or launch Desktop. Output includes local paths: redact it before sharing. Review downloaded source; see [archive verification and MOTW handling](docs/WINDOWS-INTEGRATION.md#install-and-import-the-module) if execution is blocked. Organization signing policy still applies.

Actual read-only diagnostic excerpt on Windows (2026-10-16; selected fields only):

```text
State          : Running
Changed        : False
Committed      : False
LaunchVerified : False
ProviderLoaded : NotVerified
```

Preview the switch before changing anything:

```powershell
pwsh -NoProfile -File ./codex-mode.ps1 GPT -DryRun -Json
```

Dry Run reports the plan without creating files, locks, prompts or activation. A preview can refuse unsupported config or report `CanProceed=false` while Desktop is running; that is not a completed switch.

## Save and switch

Start with an **already working custom provider configuration**. Finish or stop relevant tasks, exit Desktop normally and close configuration editors before any write:

```powershell
./codex-mode.ps1 Init -DryRun
./codex-mode.ps1 Init
./codex-mode.ps1 GPT -DryRun
./codex-mode.ps1 GPT
./codex-mode.ps1 Status
# To return to the saved custom provider, with Desktop closed:
./codex-mode.ps1 DeepSeek -DryRun
./codex-mode.ps1 DeepSeek
```

`DeepSeek` is the legacy command name for whichever single custom provider you saved. It does not create accounts, supply models or translate protocols. These script commands change configuration only. Add `-Launch` explicitly to GPT/DeepSeek/Toggle to request application activation and confirm task safety; the controller never closes Desktop for you. Verify the provider/model in a new Desktop task.

## Optional Windows integration

```powershell
Import-Module ./CodexModeSwitcher.psd1
Start-CodexMode GPT -DryRun
codex-mode install terminal           # Preview only
codex-mode integration list
codex-mode integration uninstall-all  # Preview only
```

**`Start-CodexMode` launches by default; the script does not.** Use `-ConfigurationOnly` for the module's configuration-only operation. Integration install/uninstall requires explicit `-Apply`; nothing is installed by importing the module. See [Windows integration](docs/WINDOWS-INTEGRATION.md) for ownership checks, Start Menu, notifications and removal.

## Safety and limits

- Writes refuse a running or unidentifiable Desktop. Task completion is a user assertion, not automatic detection.
- Verified backups and journals support conditional recovery of interrupted transactions. `Recover` cannot undo an already committed switch; launch failure retains the committed selection.
- Per-file replacement is atomic; a multi-file transaction is not filesystem-wide atomic. The lock does not control external editors.
- Backups can contain secrets already in your configuration. Keep them private. Authentication/session stores are outside the controller's managed data; it does not sign you in or change access/billing.
- Only supported user-level TOML forms are edited. Active profiles and other overrides can affect the result; multiline/quoted managed forms are conservatively refused.
- MSIX launch with a custom Codex home is blocked. Win32 home consumption, real integration UI and provider inference require separate manual acceptance. No hot-reload or old-session continuity guarantee is made.

## Documentation

| Need | Guide |
| --- | --- |
| Commands, automation flags and compatibility | [Usage](docs/USAGE.md) |
| Install a module, verify a release, add/remove integrations | [Windows integration](docs/WINDOWS-INTEGRATION.md) |
| Diagnose or recover an interrupted operation | [Troubleshooting](docs/TROUBLESHOOTING.md) |
| Transaction and activation design | [Architecture and source evidence](docs/architecture/README.md) |
| What was actually tested | [Desktop validation](docs/DESKTOP-VALIDATION.md) · [Historical v0.1 validation](docs/VALIDATION.md) |
| Version history | [Changelog](CHANGELOG.md) |

<a id="architecture"></a>
<a id="usage"></a>

## License, contributing and security

[MIT](LICENSE) · [Contributing and tests](CONTRIBUTING.md) · [Security and private reporting](SECURITY.md)
