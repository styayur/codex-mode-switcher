#requires -Version 7.4
<#
.SYNOPSIS
Explicitly install or uninstall cdx-gpt/cdx-deepseek profile functions.
.DESCRIPTION
DryRun previews the managed block. Existing user commands are never overwritten.
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall')][string]$Action = 'Install',
    [string]$ProfilePath = $PROFILE.CurrentUserAllHosts,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../src/CodexMode.psm1')
try { Invoke-DesktopShortcut -Action $Action -ProfilePath $ProfilePath -DryRun:$DryRun }
catch {
    $safeMessage = $_.Exception.Data['SafeMessage']
    if (-not $safeMessage) { $safeMessage = 'Profile operation failed. Inspect local permissions; private exception details are not logged.' }
    throw $safeMessage
}
