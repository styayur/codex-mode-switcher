function Start-CodexMode {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)][ValidateSet('GPT', 'DeepSeek', 'Toggle')][string]$Mode = 'GPT',
        [switch]$ConfigurationOnly, [switch]$Notify, [switch]$DryRun, [switch]$NonInteractive,
        [switch]$TasksStopped, [switch]$WaitForExit,
        [ValidateRange(1, 600)][int]$ExitTimeoutSeconds = 60,
        [ValidateRange(1, 120)][int]$LaunchTimeoutSeconds = 30,
        [string]$DesktopPath, [string]$DesktopAppId
    )
    $parameters = @{} + $PSBoundParameters
    $parameters.Remove('ConfigurationOnly'); $parameters.Remove('Notify')
    $parameters.Remove('WhatIf'); $parameters.Remove('Confirm')
    $parameters['Mode'] = $Mode
    $parameters['Launch'] = -not $ConfigurationOnly
    if (-not $DryRun -and -not $PSCmdlet.ShouldProcess('Codex Desktop configuration', "Select $Mode")) {
        $parameters['DryRun'] = $true
    }
    $result = Invoke-CodexMode @parameters
    if ($Notify -and -not $parameters['DryRun']) { [void](Send-ModeNotification $result) }
    return $result
}

function Get-CodexStatus {
    [CmdletBinding()]
    param([string]$DesktopPath, [string]$DesktopAppId)
    Invoke-CodexMode Status @PSBoundParameters
}

function Test-CodexEnvironment {
    [CmdletBinding()]
    param([string]$DesktopPath, [string]$DesktopAppId)
    Invoke-CodexMode Diagnose @PSBoundParameters
}

function Invoke-CodexCommand {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][ValidateSet('GPT','DeepSeek','Toggle','Status','Init','Diagnose','Recover','install','uninstall','integration')]
        [string]$Action = 'Status',
        [Parameter(Position = 1)][string]$Target,
        [switch]$Apply, [switch]$DryRun, [switch]$Notify, [switch]$Launch,
        [switch]$NonInteractive, [switch]$TasksStopped, [switch]$WaitForExit,
        [switch]$NoLogin, [switch]$SkipDoctor,
        [ValidateRange(1, 600)][int]$ExitTimeoutSeconds = 60,
        [ValidateRange(1, 120)][int]$LaunchTimeoutSeconds = 30,
        [string]$DesktopPath, [string]$DesktopAppId, [string]$TransactionId
    )
    if ($Action -in @('install','uninstall','integration')) {
        if ($Action -eq 'integration' -and $Target -eq 'list') { return Get-CodexIntegration }
        if ($Action -eq 'integration' -and $Target -eq 'uninstall-all') {
            return Invoke-CodexIntegration -Action Uninstall -Kind all -Apply:$Apply -DryRun:$DryRun
        }
        if ($Action -eq 'integration' -or $Target -notin @('terminal','startmenu','notifications')) {
            Write-ModeFailure 'ArgumentsInvalid' 'Use install/uninstall terminal|startmenu|notifications, or integration list|uninstall-all.'
        }
        return Invoke-CodexIntegration -Action $Action -Kind $Target -Apply:$Apply -DryRun:$DryRun
    }
    if ($Target -or $Apply) { Write-ModeFailure 'ArgumentsInvalid' 'Target and Apply are integration options only.' }
    $parameters = @{} + $PSBoundParameters
    foreach ($key in @('Action','Target','Apply','Notify')) { $parameters.Remove($key) }
    $result = Invoke-CodexMode -Mode $Action @parameters
    if ($Notify -and -not $DryRun -and $Action -notin @('Status','Diagnose')) { [void](Send-ModeNotification $result) }
    return $result
}
