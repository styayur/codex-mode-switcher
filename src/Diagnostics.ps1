function Protect-SelectionLabel([string]$Value, [string]$Default) {
    if (-not $Value) { return $Default }
    if ($Value.Length -gt 100 -or $Value -match '(?i)(sk-|gh[pousr]_|eyJ|bearer|token|secret|api.?key)' -or
        $Value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$') { return '(redacted)' }
    return $Value
}

function Get-ModeDiagnostic($Context, $Identity, $DesktopState) {
    $configValid = $true
    $provider = '(unknown)'; $model = '(unknown)'; $login = '(unknown)'; $activeProfile = $false
    try {
        $config = Get-FileSnapshot $Context.Files.config
        Assert-ConfigShape $config.Text
        $provider = Protect-SelectionLabel (Get-RootValue $config.Text 'model_provider') 'openai (default)'
        $model = Protect-SelectionLabel (Get-RootValue $config.Text 'model') '(Codex/account default)'
        $login = Protect-SelectionLabel (Get-RootValue $config.Text 'forced_login_method') '(not forced)'
        $activeProfile = @((Get-ConfigPart $config.Text).Root | Where-Object {
            $_ -cmatch '^\s*(?:profile|"profile"|''profile'')\s*='
        }).Count -gt 0
    } catch { $configValid = $false }
    $savedState = 'Missing'
    try {
        if ([IO.File]::Exists($Context.Files.state)) {
            [void](ConvertFrom-ProviderState (Get-FileSnapshot $Context.Files.state).Text)
            $savedState = 'Valid'
        }
    } catch { $savedState = 'Invalid' }
    $gptState = 'Missing'
    try {
        if ([IO.File]::Exists($Context.Files.gpt)) {
            [void](ConvertFrom-GptState (Get-FileSnapshot $Context.Files.gpt).Text)
            $gptState = 'Valid'
        }
    } catch { $gptState = 'Invalid' }
    $pending = @()
    $recoveryStatus = 'Clear'
    try { $pending = @(Get-PendingTransaction $Context); if ($pending.Count) { $recoveryStatus = 'Required' } }
    catch { $recoveryStatus = 'Unknown' }
    $backups = 0
    if ([IO.Directory]::Exists($Context.BackupDirectory)) {
        $backups = @(Get-ChildItem -LiteralPath $Context.BackupDirectory -File -ErrorAction SilentlyContinue).Count
    }
    [pscustomobject]@{
        CodexHome = $Context.Home; ConfigPresent = [IO.File]::Exists($Context.Files.config)
        ConfigValid = $configValid; Provider = $provider; Model = $model; LoginRule = $login
        SavedProviderState = $savedState; SavedGptState = $gptState
        ActiveProfile = $activeProfile; OtherOverrides = 'NotInspected'; TaskActivity = 'Unknown'
        Desktop = $Identity; DesktopState = $DesktopState.State; DesktopStateReliable = $DesktopState.Reliable
        RestartRequired = $DesktopState.State -eq 'Running'; ProviderLoaded = 'NotVerified'
        BackupCount = $backups; RecoveryStatus = $recoveryStatus; PendingTransactions = $pending
    }
}

function Get-ModeResult([string]$Action) {
    [pscustomobject]@{
        Version = $ModeVersion; Action = $Action; State = 'Ready'; Code = 'Ready'; Message = ''
        Changed = $false; Committed = $false; TransactionId = $null; Rollback = 'NotRequired'
        LaunchRequested = $false; LaunchVerified = $false; ProviderLoaded = 'NotVerified'
        DryRun = $false; CanProceed = $false; LegacyFlagsAccepted = $false
        Stages = [Collections.Generic.List[string]]::new(); Plan = $null; Diagnostics = $null
    }
}
