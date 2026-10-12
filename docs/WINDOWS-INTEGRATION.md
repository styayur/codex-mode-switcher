# Windows native integration

v0.2.1 adds a reusable PowerShell module and opt-in native integrations around the existing
Desktop Controller. It does not manage authentication, edit session databases, provide a
model gateway, run background services, or replace Codex's official configuration.

## Install and import the module

Windows and PowerShell 7.4+ are required. Download `CodexModeSwitcher-0.2.1.zip` and
`SHA256SUMS.txt` from the GitHub release. Verify the archive hash and review the source.
The archive contains a `CodexModeSwitcher/` directory with the manifest and runtime files.
Use a normal current-user module directory; no administrator access is necessary:

```powershell
Get-FileHash .\CodexModeSwitcher-0.2.1.zip -Algorithm SHA256
$moduleRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell/Modules'
if (Test-Path (Join-Path $moduleRoot 'CodexModeSwitcher')) {
    throw 'An installation already exists. Review it and uninstall integrations before upgrading.'
}
Expand-Archive .\CodexModeSwitcher-0.2.1.zip -DestinationPath $moduleRoot
Import-Module CodexModeSwitcher
Get-Command -Module CodexModeSwitcher
```

For a portable checkout, use `Import-Module ./CodexModeSwitcher.psd1`. The archive and
checkout must stay together with src/ and entry scripts. Nothing changes PSModulePath,
PATH or your PowerShell profile automatically. Importing the module only defines commands.

If a reviewed download is blocked by Mark of the Web, use Unblock-File on its PowerShell
and C# source files. The project never modifies ExecutionPolicy or bypasses signing policy.

| Command | Behavior |
| --- | --- |
| Start-CodexMode GPT / DeepSeek / Toggle | Safe selection **and launch** by default; ConfigurationOnly opts out. |
| Get-CodexStatus | Read-only local controller status. |
| Test-CodexEnvironment | Read-only Desktop/config/environment diagnosis. |
| codex-mode GPT / DeepSeek / Toggle | Original configuration-only default; Launch opts in. |
| codex-mode install / uninstall | Preview unless Apply is supplied. |
| codex-mode integration list | Read-only ownership, file paths, presence and uninstallability. |
| codex-mode integration uninstall-all | Preview/removal of recorded Terminal, Start Menu and notification files only. |

Module functions return structured results. Check State, Committed and LaunchVerified;
State=Failed is not a successful switch. The original script and cmd adapter also return
a failing exit status. Start-CodexMode supports WhatIf/Confirm in addition to DryRun.

In cmd.exe, run `codex-mode.cmd install terminal`, or explicitly place the distribution
on PATH to use `codex-mode install terminal`. The wrapper invokes PowerShell with NoProfile;
it does not install or launch anything beyond the requested operation.

## Preview and approval

```powershell
codex-mode install terminal
codex-mode install terminal -Apply
codex-mode install startmenu
codex-mode install startmenu -Apply
codex-mode integration list | ConvertTo-Json -Depth 6
codex-mode integration uninstall-all
codex-mode integration uninstall-all -Apply
```

Review the displayed paths and commands before supplying Apply. DryRun overrides Apply.
The manager does not open a prompt or infer approval from noninteractive execution.
Missing Terminal returns Unavailable without creating state. Other integrations remain usable.

## Windows Terminal

Uses Microsoft's [JSON fragment extension mechanism](https://learn.microsoft.com/en-us/windows/terminal/json-fragment-extensions),
with a separate UTF-8 fragment under the current user's LocalApplicationData:

```text
Microsoft/Windows Terminal/Fragments/styayur.codex-mode-switcher/profiles.json
```

It adds Codex GPT, Codex DeepSeek and Codex Diagnose with three stable, project-specific
GUIDs. It does not read or rewrite settings.json/JSONC, update existing profiles, change
the default profile, or merge arbitrary user settings. Fragment support must be enabled
in your Terminal installation. Restart/reload Terminal if new profiles are not shown.
Presence of wt.exe establishes availability, not that Terminal consumed the fragment.

GPT/DeepSeek open PowerShell with the original script, Launch and WaitForExit. They still
require normal task completion/exit confirmation; shortcuts never force-close Desktop.
Diagnose is read-only. NoExit keeps results visible for review, including failure output.

## Start Menu

Creates native `.lnk` files in the current user's Programs/Codex Mode Switcher folder:
Codex GPT, Codex DeepSeek and Codex Diagnose. Uses Windows Shell COM and an application
identity property. No desktop shortcuts, right-click menus, task scheduler, service or
tray agent are created. Shortcut arguments quote the installed script path.

## Optional notifications

```powershell
codex-mode install notifications       # Preview
codex-mode install notifications -Apply
Start-CodexMode GPT -Notify
.\codex-mode.ps1 DeepSeek -Launch -Notify
codex-mode uninstall notifications -Apply
```

Enabling notifications creates a separate `Codex Mode Switcher.lnk` identity shortcut
with AUMID `styayur.CodexModeSwitcher`, pointing to read-only Diagnose. This follows the
documented [desktop toast identity requirement](https://learn.microsoft.com/en-us/windows/win32/shell/enable-desktop-toast-with-appusermodelid).
The toast body has no activation action or custom protocol. There is no persistent
COM activator or notification daemon.

Sending is also opt-in per command with Notify. Only fixed outcome labels cross into a
short-lived hidden Windows PowerShell 5.1 WinRT helper; no provider values, paths, keys,
raw exception text or config data are passed. The helper has a 15-second deadline; only
that owned helper can be stopped on timeout, never Desktop. Failure is isolated from the
core result and cannot trigger config rollback. Focus Assist, policy or notification
settings may suppress display. API acknowledgement does not prove a visible toast.

## Ownership and recovery

Receipts live in LocalApplicationData/CodexModeSwitcher/integrations/ownership.json.
They contain fixed artifact IDs and SHA-256 hashes, never arbitrary deletion paths.
Targets are derived from known user folders. Linked/reparse paths are refused. A separate
exclusive integration lock coordinates this tool's installers without changing the
Desktop config transaction mechanism.

Existing unowned files are never adopted or overwritten. Repeated installation leaves
matching artifacts unchanged. Missing owned artifacts can be recreated. Modified owned
files cause a conflict; all-uninstall checks conflicts before removing anything. Unowned
files are skipped. Uninstall backs up matching bytes first; ownership data is backed up
before updates. Backups, the lock, receipts and empty directories are retained for audit.
The list command describes managed artifacts and identifies the receipt/backup locations.

Creation stages bytes and atomically moves without overwriting a destination. Failure
attempts to remove only matching files created in that invocation and recreate removed
files only where no newer file exists. Known ownership bytes are restored conditionally.
External edits are preserved. An abrupt process/power failure can leave an unrecorded
artifact or missing recorded file: list reports Conflict/Partial, not success. Inspect
private backups and reconcile deliberately; an unowned leftover is never auto-deleted.
There is no multi-file filesystem atomicity or lock over other applications. Keep editors
closed during installation/uninstall to avoid the final check/delete race.

Before moving or upgrading the distribution, uninstall its integrations and then reinstall
from the new location. The manager does not silently rewrite installed command paths.
Legacy cdx-gpt/cdx-deepseek PowerShell profile blocks use their separate installer/uninstaller;
they are outside the three integration types managed here. Module files are also not removed
by integration uninstall-all.

## Verification boundary

On 2026-10-12, the complete local syntax/lint/Pester run passed **115 tests**, with no
failures or skips: all 89 Desktop/config regressions plus 26 module/integration cases.
Mermaid source/link checks and repeatable light/dark rendering passed. TruffleHog 3.97.9
reported zero findings in the 46-file publishable snapshot with live credential verification
disabled; private-path/credential-pattern checks also passed. The release PR records CI
for the exact committed source.

Pester uses TestDrive folders and synthetic configuration. It exercises real Windows Shell
shortcut serialization/property reading only inside TestDrive, never the user's actual
Start Menu, Terminal settings or Codex home. Toast sending is mocked; no test displays a
real notification or launches Desktop. The full original regression suite is retained.

Manual checks remain: Terminal profile visibility, actual Start Menu search/launch, visible
toast behavior under Windows policy, and the Desktop provider E2E checklist in
[DESKTOP-VALIDATION.md](DESKTOP-VALIDATION.md). This release does not claim those interactive
observations occurred merely because native file tests or CI passed.
