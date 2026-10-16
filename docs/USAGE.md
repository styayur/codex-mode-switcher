# Commands and compatibility

[Back to README](../README.md). Run script examples from the complete checkout in PowerShell 7.4+.

## Commands

| Command | Behavior |
| --- | --- |
| `Status` / `Diagnose` | Read-only local selection, Desktop identity/state, backup and recovery diagnostics. |
| `Init` | Back up an existing config and save its active custom provider. Preserve saved state when on GPT. |
| `GPT` | Capture the active custom provider; select OpenAI/ChatGPT; retain or restore native model/reasoning selection. |
| `DeepSeek` | Restore the saved custom provider's selectors and tables, saving native GPT selection first. |
| `Toggle` | GPT/default → saved provider; custom provider → GPT. |
| `Recover -TransactionId <id>` | Restore an interrupted, uncommitted transaction when recorded hashes and backups still match. |

All mutations stop if Desktop is running or its identity/state is unknown. Without
`-Launch`, commands only change local configuration. Missing Desktop does not block
configuration-only use when discovery is reliable. MCP, sandbox, projects and unrelated
provider settings are preserved. Only one saved custom provider is managed.

```powershell
# Preview: no file creation, lock, prompt or activation
.\codex-mode.ps1 GPT -Launch -DryRun -Json

# Bounded interactive coordination after you finish/stop tasks
.\codex-mode.ps1 GPT -Launch -WaitForExit -ExitTimeoutSeconds 60

# Automation: attest task completion explicitly; running Desktop still blocks
.\codex-mode.ps1 GPT -Launch -NonInteractive -TasksStopped -LaunchTimeoutSeconds 30

# Explicit identity: registered MSIX AUMID or validated signed Win32 GUI executable
.\codex-mode.ps1 Diagnose -DesktopAppId '<registered-AUMID>' -Json
.\codex-mode.ps1 Diagnose -DesktopPath 'C:\Applications\Codex\Desktop.exe' -Json

```

Automatic discovery uses
package/Start-menu metadata or Win32 uninstall registration. Explicit paths must identify
a signed OpenAI Codex GUI application; a CLI executable is rejected. Ambiguous results are
`Unknown`. The executable path, not its process name, establishes a running identity.

`-Json` prints a structured result; `-PassThru` returns a PowerShell object. Failures also
raise a sanitized terminating error for a nonzero script exit. `Committed`, `Rollback`,
`TransactionId` and `LaunchVerified` distinguish switching from startup. `LaunchVerified`
means an identity-matching process was observed; **ProviderLoaded remains NotVerified**.
`TaskActivity` remains `Unknown`. Diagnostics include local paths: redact them before sharing.

### Compatibility with v0.1.0

The five original commands and valid legacy provider state remain supported. `-NoLogin`
and `-SkipDoctor` are accepted compatibility flags with no effect: CLI login and diagnostics
are no longer implicit side effects. GPT now preserves known native model/reasoning fields
instead of always clearing the model. First switching from a custom provider without saved
GPT state still uses Codex/account defaults. Config-only commands now refuse a running or
unidentifiable Desktop. Repeated selections produce stable config; audit journals and
explicit Init backups may still accumulate.


## Authentication and billing

**ChatGPT OAuth is not an OpenAI API key.** ChatGPT subscription access and third-party
API billing are separate. Codex can retain its ChatGPT login while a custom provider is
selected. Configure your provider's appropriate environment-based credential separately;
never put API keys in this repository. This tool does not grant access or change quotas.

The controller does not read, copy, delete or rewrite `auth.json`, and does not invoke
`codex login`, doctor or other CLI commands. Sign in through Desktop when needed.
Credentials must be available to the launched application, which can differ from a shell's
environment for Windows-brokered MSIX activation. See OpenAI's
[Desktop provider configuration guidance](https://learn.chatgpt.com/docs/enterprise/connect-to-a-gateway).


## Compatibility limits

- No guarantee of hot reload or seamless continuation of old sessions across providers.
  Restart normally and verify in a new task. No CLI profiles or internal App Server control.
- Third-party API compatibility belongs to that service and your Codex version; a working
  protocol-compatible endpoint is required. Direct DeepSeek inference is not verified here.
- MSIX `-Launch` currently requires the default Codex home with no conflicting persistent
  `CODEX_HOME`. Brokered environment inheritance is unverified; custom homes are refused.
  Win32 launch explicitly passes `CODEX_HOME`, but its actual Desktop consumption needs E2E testing.
- Only user-level config is edited. An active root profile blocks launch; project, managed,
  environment and application overrides are not comprehensively inspected.
- Conservative TOML editing supports ordinary single-line assignments and bare managed
  keys/provider table names. Multiline values and quoted/array provider tables are refused.
  Unrelated TOML is preserved, not fully parsed; start from valid configuration.
- Each file replacement is atomic on supported filesystems. A multi-file transaction uses
  a recovery journal, not a filesystem-wide atomic commit. Linked/reparse paths are refused.
- The scripts are unsigned. Windows PowerShell 5.1 is used only as the inbox Appx discovery
  bridge; users run the controller with PowerShell 7.4+.
