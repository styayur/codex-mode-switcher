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
Import-Module (Join-Path $PSScriptRoot '../CodexModeSwitcher.psd1')
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
