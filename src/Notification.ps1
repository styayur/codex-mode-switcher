function Get-NotificationOutcome($Result) {
    # Never forward provider names, config values, paths or exception text to Windows.
    if ($Result.State -eq 'Failed') {
        if ($Result.Committed) { return 'CommittedLaunchFailed' }
        if ($Result.Code -eq 'DesktopRunning') { return 'DesktopRunning' }
        return 'Failed'
    }
    if ($Result.Committed -and $Result.Action -eq 'GPT') { return 'GPT' }
    if ($Result.Committed -and $Result.Action -eq 'DeepSeek') { return 'DeepSeek' }
    return 'Completed'
}

function Request-WindowsNotification([string]$Outcome) {
    $process = [Diagnostics.Process]::new()
    try {
        $process.StartInfo.FileName=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $process.StartInfo.UseShellExecute=$false
        $process.StartInfo.CreateNoWindow=$true
        $process.StartInfo.RedirectStandardOutput=$true
        $process.StartInfo.RedirectStandardError=$true
        foreach ($value in @('-NoLogo','-NoProfile','-NonInteractive','-File',
            (Join-Path $PSScriptRoot 'Show-Notification.ps1'),'-Outcome',$Outcome)) { $process.StartInfo.ArgumentList.Add($value) }
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) {
            $process.Kill() # Only this invocation's notification helper, never Desktop.
            return 'TimedOut'
        }
        [void]$stdout.GetAwaiter().GetResult(); [void]$stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -eq 0) { return 'Requested' }
        return 'Unavailable'
    } finally { $process.Dispose() }
}

function Send-ModeNotification($Result) {
    try {
        $setting = @(Get-CodexIntegration | Where-Object Kind -EQ 'notifications')
        if ($setting.Count -ne 1 -or $setting[0].Status -ne 'Installed') { return 'NotConfigured' }
        return Request-WindowsNotification (Get-NotificationOutcome $Result)
    } catch { return 'Unavailable' } # Notification failure never changes a core result.
}
