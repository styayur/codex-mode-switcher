function Get-ModeContext {
    $directory = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $HOME '.codex' }
    else { $env:CODEX_HOME }
    if (-not [IO.Path]::IsPathFullyQualified($directory)) {
        Write-ModeFailure 'HomeInvalid' 'CODEX_HOME must be an absolute filesystem path.'
    }
    $directory = [IO.Path]::GetFullPath($directory)
    $stateDirectory = Join-Path $directory 'mode-switcher'
    [pscustomobject]@{
        Home = $directory
        StateDirectory = $stateDirectory
        BackupDirectory = Join-Path $stateDirectory 'backups'
        JournalDirectory = Join-Path $stateDirectory 'transactions'
        LockPath = Join-Path $stateDirectory '.lock'
        Files = [ordered]@{
            config = Join-Path $directory 'config.toml'
            state = Join-Path $stateDirectory 'deepseek-state.json'
            gpt = Join-Path $stateDirectory 'gpt-state.json'
        }
    }
}

function ConvertTo-ProviderState([string]$Text) {
    $provider = Get-RootValue $Text 'model_provider'
    if (-not $provider -or $provider -ceq 'openai') { return $null }
    $tables = Edit-ProviderTable $Text $provider -Extract
    if ([string]::IsNullOrWhiteSpace($tables)) {
        Write-ModeFailure 'ProviderMissing' 'Active custom provider has no supported table; refusing to switch without recoverable state.'
    }
    $state = [ordered]@{ schema_version = 1; provider_id = $provider; captured_at = [DateTime]::UtcNow.ToString('o') }
    foreach ($key in $SwitchKeys) { $state[$key] = Get-RootLine $Text $key }
    $state.provider_tables = $tables.TrimEnd()
    $state | ConvertTo-Json -Depth 5
}

function ConvertFrom-ProviderState([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-ModeFailure 'StateMissing' 'No saved custom provider. Run Init while your working custom provider is active.'
    }
    try { $state = ConvertFrom-Json -InputObject $Text -AsHashtable -ErrorAction Stop }
    catch { Write-ModeFailure 'StateInvalid' 'Saved provider JSON is invalid; configuration was not changed.' }
    if ($state -isnot [Collections.IDictionary]) { Write-ModeFailure 'StateInvalid' 'Invalid provider state object.' }
    if ($state.Contains('schema_version') -and $state.schema_version -ne 1) { Write-ModeFailure 'StateInvalid' 'Unsupported state version.' }
    $id = $state['provider_id']
    if ($id -isnot [string] -or $id -cnotmatch '^[A-Za-z0-9_-]+$' -or $id -ceq 'openai') {
        Write-ModeFailure 'StateInvalid' 'Invalid saved provider ID.'
    }
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($key in $SwitchKeys) {
        $value = $state[$key]
        if ($null -ne $value -and $value -isnot [string]) { Write-ModeFailure 'StateInvalid' 'Invalid saved selector type.' }
        if ($value) {
            if ($value -match '[\r\n]' -or $value -cnotmatch ('^\s*' + $key + '\s*=')) {
                Write-ModeFailure 'StateInvalid' 'Invalid saved selector line.'
            }
            $lines.Add($value)
        }
    }
    $tables = $state['provider_tables']
    if ($tables -isnot [string] -or [string]::IsNullOrWhiteSpace($tables)) { Write-ModeFailure 'StateInvalid' 'Missing saved provider tables.' }
    $rootText = $lines -join "`n"
    Assert-ConfigShape ($rootText + "`n" + $tables)
    if ((Get-RootValue $rootText 'model_provider') -cne $id) { Write-ModeFailure 'StateInvalid' 'Saved provider selector mismatch.' }
    if ([string]::IsNullOrWhiteSpace((Edit-ProviderTable $tables $id -Extract)) -or
        -not [string]::IsNullOrWhiteSpace((Edit-ProviderTable $tables $id))) {
        Write-ModeFailure 'StateInvalid' 'State contains unrelated configuration; refusing restore.'
    }
    [pscustomobject]@{ ProviderId = $id; Lines = @($lines); Tables = $tables }
}

function ConvertTo-GptState([string]$Text) {
    $state = [ordered]@{ schema_version = 1 }
    foreach ($key in $NativeKeys) { $state[$key] = Get-RootLine $Text $key }
    $state | ConvertTo-Json
}

function ConvertFrom-GptState([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    try { $state = ConvertFrom-Json -InputObject $Text -AsHashtable -ErrorAction Stop }
    catch { Write-ModeFailure 'GptStateInvalid' 'Saved GPT selection JSON is invalid.' }
    if ($state -isnot [Collections.IDictionary] -or $state['schema_version'] -ne 1) {
        Write-ModeFailure 'GptStateInvalid' 'Invalid saved GPT selection version.'
    }
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($key in $NativeKeys) {
        $value = $state[$key]
        if ($null -ne $value -and $value -isnot [string]) { Write-ModeFailure 'GptStateInvalid' 'Invalid saved GPT field.' }
        if ($value) {
            if ($value -match '[\r\n]' -or $value -cnotmatch ('^\s*' + $key + '\s*=')) {
                Write-ModeFailure 'GptStateInvalid' 'Invalid saved GPT line.'
            }
            $lines.Add($value)
        }
    }
    Assert-ConfigShape ($lines -join "`n")
    return @($lines)
}

function Get-SwitchPlan($Context, [string]$Mode) {
    $snapshots = [ordered]@{}
    foreach ($role in $Context.Files.Keys) { $snapshots[$role] = Get-FileSnapshot $Context.Files[$role] }
    $original = $snapshots.config.Text
    Assert-ConfigShape $original
    $provider = Get-RootValue $original 'model_provider'
    $isGpt = -not $provider -or $provider -ceq 'openai'
    $action = if ($Mode -eq 'Toggle') { if ($isGpt) { 'DeepSeek' } else { 'GPT' } } else { $Mode }
    $desired = [ordered]@{}
    switch ($action) {
        'Init' {
            if (-not $isGpt) { $desired.state = ConvertTo-ProviderState $original }
        }
        'GPT' {
            $text = $original
            if (-not $isGpt) {
                $desired.state = ConvertTo-ProviderState $original
                [void](ConvertFrom-ProviderState $desired.state)
                $text = Edit-ProviderTable $text $provider
                $native = @(ConvertFrom-GptState $snapshots.gpt.Text)
            } else {
                # Re-selecting GPT preserves the current native model selection.
                $native = @($NativeKeys | ForEach-Object { Get-RootLine $original $_ } | Where-Object { $_ })
            }
            $desired.config = ConvertTo-SelectedRoot $text (@($ManagedComment, 'model_provider = "openai"', 'forced_login_method = "chatgpt"') + $native)
        }
        'DeepSeek' {
            $saved = ConvertFrom-ProviderState $snapshots.state.Text
            if (-not $isGpt -and $provider -cne $saved.ProviderId) {
                Write-ModeFailure 'ProviderConflict' 'A different custom provider is active. Run Init to explicitly save it first.'
            }
            if ($isGpt -and $snapshots.config.Exists) { $desired.gpt = ConvertTo-GptState $original }
            $text = Edit-ProviderTable $original $saved.ProviderId
            $text = ConvertTo-SelectedRoot $text (@($ManagedComment) + @($saved.Lines))
            $desired.config = $text.TrimEnd() + "`n`n" + $saved.Tables.TrimEnd() + "`n"
        }
    }
    if ($desired.Contains('config')) { Assert-ConfigShape $desired.config }
    if ($desired.Contains('state')) { [void](ConvertFrom-ProviderState $desired.state) }
    $writes = [Collections.Generic.List[object]]::new()
    # State is durable before config replacement; both participate in rollback.
    foreach ($role in @('state', 'gpt', 'config')) {
        if ($desired.Contains($role) -and $desired[$role] -cne $snapshots[$role].Text) {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($desired[$role])
            $writes.Add([pscustomobject]@{ Role = $role; Before = $snapshots[$role]; Bytes = $bytes; Hash = Get-ByteHash $bytes })
        }
    }
    [pscustomobject]@{ Action = $action; Snapshots = $snapshots; Writes = @($writes); BackupConfig = $action -eq 'Init' }
}
