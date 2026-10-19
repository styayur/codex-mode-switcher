# Installation, update and removal

Codex Mode Switcher is distributed as a complete archive. The entry script depends on
`src/`, the module manifest, the cmd adapter and the installer. **Do not download only
`codex-mode.ps1`.** A single-file v0.1.0/v0.2.0 entry cannot be upgraded by replacing that
one file.

## Download

1. Open [Releases](https://github.com/styayur/codex-mode-switcher/releases).
2. Download `CodexModeSwitcher-<version>.zip`. This is the only installable asset.
3. Download `SHA256SUMS.txt` and `release-manifest.json`; verify the archive:

```powershell
Get-FileHash .\CodexModeSwitcher-0.2.2.zip -Algorithm SHA256
Get-Content .\SHA256SUMS.txt
```

4. Extract the archive. The extracted folder must contain `install.ps1`, `codex-mode.ps1`,
   `CodexModeSwitcher.psd1` and `src/CodexMode.psm1`.

There is deliberately no standalone `codex-mode.ps1` release asset. `release-manifest.json`
lists the SHA-256 and size of every payload file; CI and `scripts/Test-Release.ps1` reject an
archive missing the module, entry point, installer or manifest coverage.
5. If Windows marks downloaded files as blocked, review them and use `Unblock-File` as
   described in [Windows integration](WINDOWS-INTEGRATION.md#install-and-import-the-module).

## Install

```powershell
pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Install
```

The default program directory is:

```text
%LOCALAPPDATA%\Programs\CodexModeSwitcher
```

The installer deploys the entry script, cmd adapter, module manifest, the complete `src/`
tree, installer, documentation and an ownership receipt. It also creates a
`release-manifest.json` with SHA-256 hashes for the installed payload.

`CODEX_HOME` is not used as a program directory. Existing `config.toml`, `auth.json`,
`mode-switcher/` state and backups, sessions and credentials remain untouched.

Use a different program directory when needed:

```powershell
pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Install `
  -InstallDirectory 'D:\Tools\CodexModeSwitcher'
```

The install directory must be outside `CODEX_HOME`, cannot be a filesystem root and cannot
replace an unowned non-empty directory. The installer does not modify `PATH`, `PSModulePath`,
your PowerShell profile, the registry or the Start Menu by default.

## Upgrade from v0.1.0 or v0.2.0 single-file installations

The installer detects an existing `%CODEX_HOME%\codex-mode.ps1` (and
`codex-mode.cmd`). Before changing it, it copies the original entry to a private backup
directory under `%LOCALAPPDATA%\CodexModeSwitcher\installer\legacy-backups`. It then writes a
small forwarding shim so the familiar `codex-mode.ps1` path continues to work:

```powershell
pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Install
& "$env:CODEX_HOME\codex-mode.ps1" Status
```

The full program is installed under the standalone tool directory. If the old entry was
not in `CODEX_HOME`, pass `-CodexHome` so the installer knows where to look.

If no legacy entry exists, the installer does not create one unless `-CreateLegacyEntry` is
supplied. Use `-NoLegacyEntry` to leave an existing entry completely untouched.

## Update

Run the installer from a newly extracted, newer complete archive:

```powershell
pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Update
```

Update verifies the current installation receipt and hashes first, stages and imports the
new module, then swaps the program directory. Modified program files are refused unless
`-Force` is supplied. The legacy entry backup is retained so uninstall can restore the
original file. An installed copy cannot update itself without a newer source archive.

## Verify

```powershell
pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Verify
pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Verify -Json
```

Verify is read-only. It checks the ownership receipt, every installed file hash, required
module files, module import and recorded legacy shims. `State` is `Healthy`, `Broken` or
`NotInstalled`; the process exit code is non-zero unless it is `Healthy`.

A missing `src/CodexMode.psm1` produces `Codex=ModuleMissing` repair instructions instead of
a raw `Import-Module` exception.

## Uninstall

```powershell
pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Uninstall
```

Uninstall removes the standalone program directory and any forwarding shims created by the
installer. If a legacy entry was replaced, its verified original is restored from the backup.
A modified shim is preserved and reported. Unverified directories are never deleted without
`-Force`, and a directory containing Codex user data is always refused.

Optional Terminal, Start Menu and notification integrations are separate user-level
artifacts. Remove them explicitly before uninstalling the program:

```powershell
& "$env:LOCALAPPDATA\Programs\CodexModeSwitcher\codex-mode.ps1" integration uninstall-all -Apply
```

Uninstall never removes `CODEX_HOME` configuration, credentials, `mode-switcher/` state,
transaction journals or backups. Review those files separately if you intentionally want to
remove your own data.

## Command reference

| Action | Behavior |
| --- | --- |
| `Install` | Install a complete payload. Refuse to replace unowned non-empty directories. |
| `Update` | Replace an existing installation after receipt/hash checks; preserve legacy backups. |
| `Verify` | Read-only receipt, hash, required-file and module-import validation. |
| `Uninstall` | Remove owned program files and shims; restore verified legacy entries; keep user data. |

All actions support `-DryRun`, `-Json` and `-PassThru`. `-WhatIf` is honored through the
installer's `SupportsShouldProcess` contract.
