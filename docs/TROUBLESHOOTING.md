# Troubleshooting and recovery

Run `./codex-mode.ps1 Diagnose -Json` first. It makes no writes and never launches the
CLI or Desktop. Redact local paths and identifying values before sharing output. Do not
attach configuration, backups, credentials or session data.

| Result | Next step |
| --- | --- |
| DesktopRunning | Finish/stop tasks and exit normally. Interactive users may use `-WaitForExit`; noninteractive writes remain blocked. |
| DesktopUnknown / DesktopIdentityChanged | Inspect installation/permissions and retry discovery. Specify a registered AUMID or signed GUI path only if you know it belongs to Codex Desktop. |
| DesktopNotInstalled | Install Desktop or use configuration-only mode after reliable discovery. No supported registration found does not mean every possible portable installation is supported. |
| DesktopHomeUnverified | MSIX launch currently supports only the default home without conflicting persistent CODEX_HOME. Use config-only mode for other homes; verify Desktop's actual environment separately. |
| TaskConfirmationRequired | After verifying relevant tasks have finished/stopped, use `-TasksStopped`. It is an assertion by you, not automatic task detection. |
| Cancelled / ExitTimeout | No selection was applied. Finish exiting and retry. The controller never forces exit. |
| ConfigInvalid / StateInvalid / GptStateInvalid | Fix the supported syntax or review a trusted local backup. Private parser input is not printed. |
| StateMissing | Run Init while the working custom provider is selected. DeepSeek restores one saved provider, not a built-in service preset. |
| ProviderConflict | Another custom provider is active. Init explicitly replaces saved custom state, with backup. Review which provider to retain first. |
| OverrideConflict | An active user-level profile may override the selection. Resolve it before launch; project/managed/environment overrides also need manual inspection. |
| ConcurrentChange / LockBusy | Close configuration editors and wait for another controller invocation to finish. Do not delete locks or overwrite another writer's changes. |
| RecoveryRequired | Inspect PendingTransactions and follow the interrupted transaction procedure below. |
| LaunchFailed / LaunchTimeout / LaunchUnknown / LaunchRace | Check Committed. A committed switch is retained. Inspect Desktop and retry only after resolving task and application state. |
| ModuleMissing | The entry script was copied without `src/`. Download the complete release archive and run `install.ps1 -Action Install`. Do not replace only `codex-mode.ps1`. |
| ReceiptMissing / FilesInvalid | The installed program files are incomplete or modified. Run `install.ps1 -Action Verify -Json`, then reinstall from a complete archive. Uninstall still removes a broken owned installation. |

## Interrupted transaction

Backups live in the selected Codex home's `mode-switcher/backups/`; journals are in
`mode-switcher/transactions/`. Diagnose lists pending transaction IDs without printing
config contents. After stopping tasks and exiting Desktop:

```powershell
.\codex-mode.ps1 Recover -TransactionId '<32-character-recorded-id>' -DryRun -Json
.\codex-mode.ps1 Recover -TransactionId '<32-character-recorded-id>' -NonInteractive -Json
```

Recovery validates the journal, backup hashes, and current before/after hashes. It restores
only this tool's config/state/GPT files. It does not launch Desktop. Unknown newer values,
missing/tampered backups or a committed journal cause refusal. Keep all evidence and review
privately instead of forcing recovery. Recovery is not a general undo command for successful
switches: select GPT/DeepSeek again to change a committed provider.

For a full manual restore, review the exact desired config backup locally, preserve the
current config separately, verify all tasks are stopped and Desktop is closed, and restore
only the chosen file. Do not bulk-copy an entire Codex home or touch credentials/sessions.
An invalid journal or conflicting external edit requires deliberate reconciliation; do not
mark it committed merely to bypass a safety check.

## Startup does not establish provider success

LaunchVerified means a process with the discovered executable identity was observed. It
cannot verify provider selection, billing, authentication or inference. Open a new Desktop
task and check the provider/model yourself. Existing sessions may retain their old settings.
Use a service compatible with your installed Codex version; this project supplies no adapter.

MSIX applications are activated through Windows, not a shell child process. A credential
variable set only in the current shell may not reach them. Configure credentials using your
organization's supported mechanism and verify separately; never paste a key into an issue.

## Download and shortcut issues

Download the complete `CodexModeSwitcher-<version>.zip` release archive, not an individual
script. Verify it against `SHA256SUMS.txt`, extract it and run `install.ps1 -Action Install`.
Review sources and use Unblock-File for MOTW, as shown in
[Windows integration](WINDOWS-INTEGRATION.md). The tool does not change ExecutionPolicy or
bypass required signatures. A v0.1.0/v0.2.0 single-file `codex-mode.ps1` is migrated to a
standalone tool directory with a backup and forwarding shim; it is not upgraded in place.

Profile installation refuses function/alias conflicts and edited owned blocks. Use DryRun,
review the existing profile and its backup, and resolve the conflict manually. Uninstall
from the original checkout before moving it; then install from the new location. A new
PowerShell session loads the installed shortcut functions.
