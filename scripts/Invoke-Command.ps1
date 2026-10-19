#requires -Version 7.4
# The module alias is preferred in PowerShell; this adapter serves cmd/PATH users.
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Action='Status', [Parameter(Position=1)][string]$Target,
    [switch]$Apply, [switch]$DryRun, [switch]$Notify, [switch]$Launch,
    [switch]$NonInteractive, [switch]$TasksStopped, [switch]$WaitForExit,
    [switch]$NoLogin, [switch]$SkipDoctor,
    [int]$ExitTimeoutSeconds=60, [int]$LaunchTimeoutSeconds=30,
    [string]$DesktopPath, [string]$DesktopAppId, [string]$TransactionId
)
$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot '../CodexModeSwitcher.psd1'
$modulePath = Join-Path $PSScriptRoot '../src/CodexMode.psm1'
$missing = @($manifestPath, $modulePath) | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }
if ($missing.Count) {
    $message = 'Codex Mode Switcher is incomplete: required module files are missing. Download the complete CodexModeSwitcher-*.zip archive, extract it, and run install.ps1 -Action Install -Force. Do not download only codex-mode.ps1.'
    [pscustomobject]@{ State = 'Failed'; Code = 'ModuleMissing'; Message = $message; Missing = @($missing | ForEach-Object { [IO.Path]::GetRelativePath((Split-Path $PSScriptRoot -Parent), $_) }) } | ConvertTo-Json -Depth 4
    exit 2
}
try { Import-Module $manifestPath -ErrorAction Stop }
catch {
    $message = 'Codex Mode Switcher is incomplete: the module could not be loaded. Download the complete CodexModeSwitcher-*.zip archive, extract it, and run install.ps1 -Action Install -Force. Do not download only codex-mode.ps1.'
    [pscustomobject]@{ State = 'Failed'; Code = 'ModuleMissing'; Message = $message } | ConvertTo-Json -Depth 4
    exit 2
}
try {
    $result = Invoke-CodexCommand @PSBoundParameters
    $result | ConvertTo-Json -Depth 8
    if ($result.PSObject.Properties['State'] -and $result.State -eq 'Failed') { exit 1 }
} catch {
    $message = $_.Exception.Data['SafeMessage']
    if (-not $message) { $message = 'Command failed. Review command arguments and local diagnostics.' }
    Write-Error $message -ErrorAction Continue
    exit 1
}
