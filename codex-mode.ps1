#requires -Version 7.4
<#
.SYNOPSIS
Select Codex Desktop provider configuration and optionally launch Desktop.
.DESCRIPTION
Uses a guarded configuration transaction. Never terminates Desktop or runs Codex CLI.
NoLogin and SkipDoctor are accepted for compatibility; all modes are now CLI-free.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('GPT', 'DeepSeek', 'Toggle', 'Status', 'Init', 'Diagnose', 'Recover')]
    [string]$Mode = 'Status',
    [switch]$Launch, [switch]$DryRun, [switch]$NonInteractive,
    [switch]$WaitForExit, [switch]$TasksStopped,
    [ValidateRange(1, 600)][int]$ExitTimeoutSeconds = 60,
    [ValidateRange(1, 120)][int]$LaunchTimeoutSeconds = 30,
    [string]$DesktopPath, [string]$DesktopAppId, [string]$TransactionId,
    [switch]$NoLogin, [switch]$SkipDoctor, [switch]$Json, [switch]$PassThru, [switch]$Notify
)
$ErrorActionPreference = 'Stop'
$moduleFile = Join-Path $PSScriptRoot 'src/CodexMode.psm1'
$moduleFiles = @(
    'CodexMode.psm1', 'Config.ps1', 'Controller.ps1', 'DesktopDiscovery.ps1',
    'DesktopLifecycle.ps1', 'Diagnostics.ps1', 'Get-WindowsInventory.ps1',
    'Integration.ps1', 'NativeShortcut.cs', 'Notification.ps1', 'Public.ps1',
    'Shortcut.ps1', 'Show-Notification.ps1', 'State.ps1', 'Transaction.ps1',
    'WindowsActivation.cs'
)
$missingModuleFiles = @($moduleFiles | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path (Join-Path $PSScriptRoot 'src') $_) -PathType Leaf)
} | ForEach-Object { "src/$_" })
if ($missingModuleFiles.Count) {
    $installerPath = Join-Path $PSScriptRoot 'scripts/Install-CodexMode.ps1'
    $repair = if (Test-Path -LiteralPath $installerPath -PathType Leaf) {
        "pwsh -NoProfile -File `"$installerPath`" -Action Install -Force"
    } else {
        'pwsh -NoProfile -File .\CodexModeSwitcher\install.ps1 -Action Install -Force'
    }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('Codex Mode Switcher is incomplete: the entry script is present but required module files are missing:')
    foreach ($missing in $missingModuleFiles) { $lines.Add("  - $missing") }
    $lines.Add('')
    $lines.Add('A v0.1.0/v0.2.0 single-file codex-mode.ps1 cannot be upgraded by replacing only that file.')
    $lines.Add('Do not download only codex-mode.ps1. Download the complete CodexModeSwitcher-*.zip release archive, extract it, and run its installer:')
    $lines.Add("  $repair")
    $lines.Add('')
    $lines.Add('The installer deploys the full module to a standalone tool directory and safely migrates an existing single-file entry.')
    $lines.Add('It does not modify Codex configuration, credentials, sessions or backups under CODEX_HOME.')
    $message = $lines -join [Environment]::NewLine
    if ($Json) {
        [pscustomobject]@{
            State = 'Failed'; Code = 'ModuleMissing'; Message = $message
            Entry = $PSCommandPath; Missing = @($missingModuleFiles); RepairCommand = $repair
        } | ConvertTo-Json -Depth 5
    } else {
        [Console]::Error.WriteLine($message)
    }
    exit 2
}
Import-Module $moduleFile -ErrorAction Stop
$parameters = @{} + $PSBoundParameters
$parameters.Remove('Json')
$parameters.Remove('PassThru')
$parameters.Remove('Notify')
$parameters.Remove('Mode')
$result = Invoke-CodexCommand -Action $Mode -Notify:$Notify @parameters
if ($Json) { $result | ConvertTo-Json -Depth 8 }
elseif ($PassThru) { $result }
else {
    if ($null -ne $result.Diagnostics) {
        $info = $result.Diagnostics
        Write-Host "Provider   : $($info.Provider)"
        Write-Host "Model      : $($info.Model)"
        Write-Host "Config     : $(if ($info.ConfigPresent) { 'present' } else { 'missing' })"
        Write-Host "Login rule : $($info.LoginRule)"
        Write-Host "DS state   : $($info.SavedProviderState)"
        Write-Host "Desktop    : $($info.DesktopState) / $($info.Desktop.ActivationMethod)"
        Write-Host "Recovery   : $($info.RecoveryStatus)"
    }
    Write-Host "[$($result.State)] $($result.Message)"
    if ($result.TransactionId) { Write-Host "Transaction: $($result.TransactionId) / rollback: $($result.Rollback)" }
}
if ($result.State -eq 'Failed') {
    # Safe, classified messages only; never print nested config/JSON exceptions.
    throw "$($result.Code): $($result.Message)"
}
