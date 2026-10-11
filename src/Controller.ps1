function Invoke-CodexMode {
    [CmdletBinding()]
    param(
        [ValidateSet('GPT', 'DeepSeek', 'Toggle', 'Status', 'Init', 'Diagnose', 'Recover')]
        [string]$Mode = 'Status',
        [switch]$Launch, [switch]$DryRun, [switch]$NonInteractive,
        [switch]$WaitForExit, [switch]$TasksStopped,
        [ValidateRange(1, 600)][int]$ExitTimeoutSeconds = 60,
        [ValidateRange(1, 120)][int]$LaunchTimeoutSeconds = 30,
        [string]$DesktopPath, [string]$DesktopAppId, [string]$TransactionId,
        [switch]$NoLogin, [switch]$SkipDoctor
    )
    $ErrorActionPreference = 'Stop'
    $result = Get-ModeResult $Mode
    $result.DryRun = [bool]$DryRun
    $result.LegacyFlagsAccepted = $NoLogin -or $SkipDoctor
    try {
        $result.Stages.Add('Preflight')
        if ($Launch -and $Mode -notin @('GPT', 'DeepSeek', 'Toggle')) {
            Write-ModeFailure 'ArgumentsInvalid' '-Launch is supported only with GPT, DeepSeek or Toggle.'
        }
        if ($TransactionId -and $Mode -ne 'Recover') { Write-ModeFailure 'ArgumentsInvalid' '-TransactionId is only used by Recover.' }
        $context = Get-ModeContext
        $plan = $null; $recovery = $null
        if ($Mode -notin @('Status', 'Diagnose')) {
            $result.Stages.Add('ValidateConfig')
            if ($Mode -eq 'Recover') { $recovery = Read-RecoveryJournal $context $TransactionId }
            else { $plan = Get-SwitchPlan $context $Mode; $result.Action = $plan.Action }
        }
        $result.Stages.Add('DetectDesktopState')
        $identity = Get-DesktopIdentity $DesktopPath $DesktopAppId
        $desktop = Get-DesktopState $identity
        $result.Diagnostics = Get-ModeDiagnostic $context $identity $desktop
        if ($Mode -in @('Status', 'Diagnose')) {
            $result.State = if ($desktop.State -eq 'NotInstalled') { 'Ready' } else { $desktop.State }
            $result.Code = $desktop.State
            $result.Message = 'Local diagnostics only. Process observations do not prove task completion or provider loading.'
            return $result
        }
        $result.Plan = [pscustomobject]@{
            WriteRoles = if ($null -ne $plan) { @($plan.Writes | ForEach-Object { $_.Role }) } else { @($recovery.Journal.files | ForEach-Object { $_.role }) }
            BackupBeforeWrite = $true; Launch = [bool]$Launch; SafeExitRequired = $desktop.State -eq 'Running'
            TasksStoppedAttested = [bool]$TasksStopped
        }
        if ($DryRun) {
            $result.State = if ($desktop.State -eq 'NotInstalled') { 'Ready' } else { $desktop.State }
            $result.Code = 'Preview'
            $result.CanProceed = $desktop.State -in @('Ready', 'NotInstalled') -and (-not $Launch -or $identity.State -eq 'Installed')
            if ($Launch) {
                try { Assert-DesktopHomeBinding $context $identity } catch { $result.CanProceed = $false; $result.Code = 'DesktopHomeUnverified' }
                if ($result.Diagnostics.ActiveProfile -or -not $TasksStopped) { $result.CanProceed = $false }
            }
            if ($result.Diagnostics.RecoveryStatus -ne 'Clear' -and $Mode -ne 'Recover') { $result.CanProceed = $false }
            $result.Message = 'Preview only: no files, locks, prompts, activation or CLI calls. Review diagnostics and task safety before execution.'
            return $result
        }
        if ($desktop.State -eq 'Unknown' -or -not $identity.Reliable) {
            Write-ModeFailure 'DesktopUnknown' 'Desktop identity or running state is Unknown. No switch performed; inspect Diagnose or specify a verified Desktop identity.'
        }
        if ($Launch -and $identity.State -ne 'Installed') { Write-ModeFailure 'DesktopNotInstalled' 'No supported Codex Desktop installation was found. No switch performed.' }
        if ($Launch) {
            Assert-DesktopHomeBinding $context $identity
            if ($result.Diagnostics.ActiveProfile) { Write-ModeFailure 'OverrideConflict' 'An active config profile may override selection. Resolve it before Desktop launch.' }
        }
        if ($desktop.State -eq 'Running') {
            if ($NonInteractive -or -not (Test-InteractiveConsole)) {
                Write-ModeFailure 'DesktopRunning' 'Desktop is running. Finish or stop relevant tasks and exit the app normally, then retry. Non-interactive switching is blocked.'
            }
            if (-not $WaitForExit) { Write-ModeFailure 'DesktopRunning' 'Desktop is running. Exit normally first, or use -WaitForExit for a bounded interactive wait.' }
            if (-not $TasksStopped -and -not (Confirm-DesktopTasksStopped)) { Write-ModeFailure 'Cancelled' 'Switch cancelled; no files changed.' }
            $result.Stages.Add('WaitingForExit')
            $desktop = Wait-DesktopExit $identity $ExitTimeoutSeconds
        } elseif ($Launch -and -not $TasksStopped) {
            if ($NonInteractive -or -not (Test-InteractiveConsole)) {
                Write-ModeFailure 'TaskConfirmationRequired' 'Process absence does not prove task completion. Confirm relevant tasks are stopped, then use -TasksStopped.'
            }
            if (-not (Confirm-DesktopTasksStopped)) { Write-ModeFailure 'Cancelled' 'Switch cancelled; no files changed.' }
        }
        $safetyCheck = {
            $fresh = Get-DesktopIdentity $DesktopPath $DesktopAppId
            if ($fresh.State -cne $identity.State -or $fresh.ExecutablePath -ine $identity.ExecutablePath -or -not $fresh.Reliable) {
                Write-ModeFailure 'DesktopIdentityChanged' 'Desktop installation changed during the operation; retry after inspecting Diagnose.'
            }
            $state = Get-DesktopState $fresh
            if ($state.State -notin @('Ready', 'NotInstalled')) { Write-ModeFailure 'DesktopStateChanged' 'Desktop is running or Unknown during the transaction. No further writes allowed.' }
        }
        $result.Stages.Add('AcquireLock')
        $transaction = if ($Mode -eq 'Recover') { Invoke-TransactionRecovery $context $recovery $safetyCheck }
        else { Invoke-SwitchTransaction $context $plan $safetyCheck }
        $result.TransactionId = $transaction.Id; $result.Committed = $transaction.Committed
        $result.Changed = $transaction.Changed; $result.Rollback = $transaction.Rollback
        $result.State = if ($Mode -eq 'Recover') { 'Ready' } else { 'SwitchCommitted' }
        $result.Code = if ($Mode -eq 'Recover') { 'Recovered' } else { 'SwitchCommitted' }
        $result.Stages.Add($result.State)
        $result.Stages.Add('ReleaseLock')
        $result.Message = if ($Mode -eq 'Recover') { 'Recorded pre-transaction files restored; no application launched.' }
        else { 'Configuration transaction committed. Credentials and sessions were not accessed.' }
        if ($Launch) {
            # Once committed, launch failure never triggers configuration rollback.
            & $safetyCheck
            $onActivation = {
                Assert-SwitchPlanApplied $plan
                $result.State = 'LaunchRequested'; $result.Stages.Add('LaunchRequested'); $result.LaunchRequested = $true
            }
            $observed = Invoke-DesktopLaunch $context $identity $LaunchTimeoutSeconds $onActivation
            $result.State = 'LaunchVerified'; $result.Code = 'LaunchVerified'; $result.LaunchVerified = $true
            $result.Stages.Add('LaunchVerified')
            $result.Message = 'A process matching Desktop identity was observed. Verify provider/model in a new Desktop task; loaded configuration is not proven.'
            $desktop = $observed
        }
        $result.CanProceed = $true
        $result.Diagnostics = Get-ModeDiagnostic $context $identity $desktop
    } catch {
        $errorData = $_.Exception.Data
        $result.State = 'Failed'
        $result.Code = if ($errorData['Code']) { [string]$errorData['Code'] } else { 'OperationFailed' }
        $result.Message = if ($errorData['SafeMessage']) { [string]$errorData['SafeMessage'] }
        else { 'Operation failed. Inspect local file permissions and diagnostics; private exception details are not logged.' }
        if ($errorData['TransactionId']) { $result.TransactionId = [string]$errorData['TransactionId'] }
        if ($errorData['Rollback']) { $result.Rollback = [string]$errorData['Rollback'] }
        if ($errorData['Committed']) { $result.Committed = $true }
        if ($result.Committed) {
            $result.Message += ' Configuration remains committed; no automatic rollback after commit.'
        }
        $result.Stages.Add('Failed')
    }
    return $result
}
