function Test-InteractiveConsole {
    [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

function Confirm-DesktopTasksStopped {
    (Read-Host 'Finish or stop relevant tasks, then exit Desktop normally. Type YES to continue, anything else to cancel') -ceq 'YES'
}

function Wait-DesktopExit($Identity, [int]$TimeoutSeconds) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $state = Get-DesktopState $Identity
        if ($state.State -eq 'Ready') { return $state }
        if ($state.State -ne 'Running') { Write-ModeFailure 'DesktopUnknown' 'Desktop identity/state became Unknown while waiting; no switch performed.' }
        Start-Sleep -Milliseconds 250
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    Write-ModeFailure 'ExitTimeout' 'Desktop did not exit within the timeout. No switch performed.'
}

function Assert-DesktopHomeBinding($Context, $Identity) {
    if ($Identity.Kind -eq 'Msix') {
        # Activation is brokered by Windows; a shell-only CODEX_HOME is not a
        # verified environment for the app. Refuse rather than edit the wrong home.
        $default = [IO.Path]::GetFullPath((Join-Path $HOME '.codex')).TrimEnd('\', '/')
        if ($Context.Home.TrimEnd('\', '/') -ine $default) {
            Write-ModeFailure 'DesktopHomeUnverified' 'MSIX activation with a custom CODEX_HOME is unverified. Use configuration-only mode or the default Desktop home.'
        }
        foreach ($scope in @('User', 'Machine')) {
            $value = [Environment]::GetEnvironmentVariable('CODEX_HOME', $scope)
            if ($value -and [IO.Path]::GetFullPath($value).TrimEnd('\', '/') -ine $default) {
                Write-ModeFailure 'DesktopHomeUnverified' 'Persistent CODEX_HOME conflicts with the verified default Desktop home.'
            }
        }
    }
}

function Request-DesktopActivation($Context, $Identity) {
    if ($Identity.Kind -eq 'Msix') {
        if (-not ('CodexMode.WindowsActivation' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'WindowsActivation.cs') }
        return [CodexMode.WindowsActivation]::Activate($Identity.Aumid)
    }
    if ($Identity.Kind -eq 'Win32') {
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $Identity.ExecutablePath
        $startInfo.WorkingDirectory = Split-Path $Identity.ExecutablePath
        $startInfo.UseShellExecute = $false
        $startInfo.Environment['CODEX_HOME'] = $Context.Home
        # A visible interactive window is the explicitly requested result.
        $process = [Diagnostics.Process]::Start($startInfo)
        try { return $process.Id } finally { $process.Dispose() }
    }
    Write-ModeFailure 'DesktopUnknown' 'No validated Windows activation method is available.'
}

function Invoke-DesktopLaunch($Context, $Identity, [int]$TimeoutSeconds, [scriptblock]$BeforeActivation) {
    $before = Get-DesktopState $Identity
    if ($before.State -ne 'Ready') { Write-ModeFailure 'LaunchRace' 'Desktop state changed after commit. Configuration remains committed; no activation attempted.' }
    & $BeforeActivation
    try { [void](Request-DesktopActivation $Context $Identity) }
    catch { Write-ModeFailure 'LaunchFailed' 'Windows activation failed. Configuration remains committed; private exception details are not logged.' }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $observed = Get-DesktopState $Identity
        if ($observed.State -eq 'Running' -and $observed.Reliable) {
            return $observed
        }
        if ($observed.State -eq 'Unknown') { Write-ModeFailure 'LaunchUnknown' 'Activation was requested but Desktop identity could not be verified. Configuration remains committed.' }
        Start-Sleep -Milliseconds 250
    } while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    Write-ModeFailure 'LaunchTimeout' 'Desktop process was not observed before the launch timeout. Configuration remains committed.'
}
