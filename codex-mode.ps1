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
Import-Module (Join-Path $PSScriptRoot 'src/CodexMode.psm1') -ErrorAction Stop
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
