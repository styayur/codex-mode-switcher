#requires -Version 7.4
<#
.SYNOPSIS
Entry point for installing, updating, verifying or uninstalling Codex Mode Switcher.
.DESCRIPTION
Run this script from a complete extracted release archive. The installer deploys the
whole module beside the entry script in a standalone tool directory and does not
rewrite Codex configuration, credentials, sessions or user backups.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Install', 'Update', 'Verify', 'Uninstall')]
    [string]$Action = 'Install',
    [string]$InstallDirectory,
    [string]$CodexHome,
    [string]$SourceDirectory,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoLegacyEntry,
    [switch]$CreateLegacyEntry,
    [switch]$Json,
    [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'scripts/Install-CodexMode.ps1'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    $message = @(
        'Codex Mode Switcher is incomplete: install.ps1 is present but scripts/Install-CodexMode.ps1 is missing.'
        'Download the complete CodexModeSwitcher-*.zip release archive and extract it before installing.'
        'Do not download only codex-mode.ps1 or install.ps1; both depend on the full distribution.'
        'No Codex configuration, credentials, sessions or backups were changed.'
    ) -join [Environment]::NewLine
    if ($Json) {
        [pscustomobject]@{ State = 'Failed'; Code = 'InstallerMissing'; Message = $message } | ConvertTo-Json -Depth 4
    } else {
        [Console]::Error.WriteLine($message)
    }
    exit 2
}
& $installer @PSBoundParameters
exit $LASTEXITCODE
