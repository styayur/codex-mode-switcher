#requires -Version 7.4
<#
.SYNOPSIS
Switch Codex between ChatGPT OAuth and one saved custom provider.
.PARAMETER Mode
Status (default), Init, GPT, DeepSeek (saved provider), or Toggle.
.PARAMETER NoLogin
Skip all Codex login commands, including login status.
.PARAMETER SkipDoctor
Skip optional diagnostics after GPT selection.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('GPT', 'DeepSeek', 'Toggle', 'Status', 'Init')]
    [string]$Mode = 'Status',
    [switch]$NoLogin,
    [switch]$SkipDoctor
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$CodexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path $HOME '.codex'
} else { [IO.Path]::GetFullPath($env:CODEX_HOME) }
$ConfigPath = Join-Path $CodexHome 'config.toml'
$StateDir = Join-Path $CodexHome 'mode-switcher'
$StatePath = Join-Path $StateDir 'deepseek-state.json'
$BackupDir = Join-Path $StateDir 'backups'
$ManagedComment = '# Managed provider/auth selection: codex-mode.ps1'
$SwitchKeys = @('model', 'model_provider', 'model_catalog_json',
    'openai_base_url', 'chatgpt_base_url', 'forced_login_method')

function Read-Config {
    if (-not [IO.File]::Exists($ConfigPath)) { return '' }
    [IO.File]::ReadAllText($ConfigPath)
}
function Write-AtomicText([string]$Path, [string]$Text) {
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Backup-File([string]$Path, [string]$Prefix, [string]$Extension) {
    if ([IO.File]::Exists($Path)) {
        $name = '{0}.{1}.{2}.{3}' -f $Prefix, (Get-Date -Format 'yyyyMMdd-HHmmss-fff'),
            ([guid]::NewGuid().ToString('N')), $Extension
        [IO.File]::Copy($Path, (Join-Path $BackupDir $name), $false)
    }
}
function Get-ConfigPart([string]$Text) {
    $root = [Collections.Generic.List[string]]::new()
    $tables = [Collections.Generic.List[string]]::new()
    $inTables = $false
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*\[') { $inTables = $true }
        if ($inTables) { $tables.Add($line) } else { $root.Add($line) }
    }
    [pscustomobject]@{ Root = $root; Tables = $tables }
}
function Get-RootLine([string]$Text, [string]$Key) {
    foreach ($line in (Get-ConfigPart $Text).Root) {
        if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) { return $line }
    }
    return $null
}
function Get-RootValue([string]$Text, [string]$Key) {
    $line = Get-RootLine $Text $Key
    if ($null -eq $line) { return $null }
    $match = [regex]::Match($line, '^\s*\w+\s*=\s*(?:"((?:[^"\\]|\\.)*)"|''([^'']*)'')\s*(?:#.*)?$')
    if (-not $match.Success) { throw "Unsupported managed value: $Key. Use a single-line TOML string." }
    if ($match.Groups[1].Success) { return $match.Groups[1].Value }
    return $match.Groups[2].Value
}
function Assert-ConfigShape([string]$Text) {
    # Conservative line editor; refuse syntax that could obscure table boundaries.
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*(#.*)?$') { continue }
        if ($line.Contains('"""') -or $line.Contains("'''")) { throw 'Multiline TOML strings are unsupported.' }
        if ($line -match '^\s*\[') {
            if ($line -notmatch '^\s*\[\[?[^\r\n]+\]\]?\s*(?:#.*)?$') { throw 'Unsupported multiline TOML value.' }
            if ($line -match '^\s*\[\[?\s*["'']?model_providers' -and
                $line -notmatch '^\s*\[model_providers(?:\.[A-Za-z0-9_-]+)*\]\s*(?:#.*)?$') {
                throw 'Use bare model_providers table names; quoted/array provider tables are unsupported.'
            }
        } elseif ($line -notmatch '^\s*[^=]+\s*=\s*\S.*$' -or $line -match '=\s*[\[{]\s*(?:#.*)?$') {
            throw 'Unsupported multiline or malformed TOML.'
        }
    }
    $root = (Get-ConfigPart $Text).Root
    foreach ($key in $SwitchKeys) {
        $pattern = '^\s*' + $key + '\s*='
        if (@($root | Where-Object { $_ -match $pattern }).Count -gt 1) { throw "Duplicate managed key: $key." }
        if (@($root | Where-Object { $_ -match ('^\s*["'']' + $key + '["'']\s*=|^\s*' + $key + '\s*\.') }).Count) {
            throw "Unsupported quoted/dotted managed key: $key."
        }
        [void](Get-RootValue $Text $key)
    }
    $provider = Get-RootValue $Text 'model_provider'
    if ($provider -and $provider -notmatch '^[A-Za-z0-9_-]+$') { throw 'Unsupported provider ID.' }
}
function Edit-ProviderTable([string]$Text, [string]$ProviderId, [switch]$Extract) {
    $result = [Collections.Generic.List[string]]::new()
    $selected = $false
    $prefix = 'model_providers.' + $ProviderId
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*\[') {
            $selected = $false
            if ($line -match '^\s*\[([^\]]+)\]\s*(?:#.*)?$') {
                $table = $Matches[1].Trim()
                $selected = ($table -ceq $prefix -or $table.StartsWith($prefix + '.', [StringComparison]::Ordinal))
            }
        }
        if ($selected -eq [bool]$Extract) { $result.Add($line) }
    }
    return (($result -join "`n").TrimEnd() + "`n")
}
function ConvertTo-SelectedRoot([string]$Text, [string[]]$Lines) {
    $parts = Get-ConfigPart $Text
    $root = [Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) { if ($line) { $root.Add($line) } }
    $root.Add('')
    foreach ($line in $parts.Root) {
        if ($line.Trim() -eq $ManagedComment) { continue }
        $drop = $false
        foreach ($key in $SwitchKeys) {
            if ($line -match ('^\s*' + $key + '\s*=')) { $drop = $true; break }
        }
        if (-not $drop) { $root.Add($line) }
    }
    $remaining = ($root -join "`n") -replace '\n{3,}', "`n`n"
    return ($remaining.TrimEnd() + "`n" + (($parts.Tables -join "`n").TrimEnd()) + "`n").TrimEnd() + "`n"
}
function Save-ProviderState([string]$Text) {
    $provider = Get-RootValue $Text 'model_provider'
    if (-not $provider -or $provider -ceq 'openai') { return $false }
    $tables = Edit-ProviderTable $Text $provider -Extract
    if ([string]::IsNullOrWhiteSpace($tables)) {
        throw 'Active custom provider has no supported table; refusing to switch without recoverable state.'
    }
    $state = [ordered]@{ schema_version = 1; provider_id = $provider; captured_at = (Get-Date).ToString('o') }
    foreach ($key in $SwitchKeys) { $state[$key] = Get-RootLine $Text $key }
    $state['provider_tables'] = $tables.TrimEnd()
    Backup-File $StatePath 'state' 'json'
    Write-AtomicText $StatePath ($state | ConvertTo-Json -Depth 5)
    return $true
}
function Read-ProviderState {
    if (-not [IO.File]::Exists($StatePath)) { throw 'No saved custom provider. Run Init while your working custom provider is active.' }
    $state = [IO.File]::ReadAllText($StatePath) | ConvertFrom-Json -AsHashtable
    if ($state -isnot [Collections.IDictionary]) { throw 'Invalid provider state object.' }
    if ($state.Contains('schema_version') -and $state.schema_version -ne 1) { throw 'Unsupported state version.' }
    $id = $state['provider_id']
    if ($id -isnot [string] -or $id -notmatch '^[A-Za-z0-9_-]+$' -or $id -ceq 'openai') { throw 'Invalid saved provider ID.' }
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($key in $SwitchKeys) {
        $value = $state[$key]
        if ($null -ne $value -and $value -isnot [string]) { throw "Invalid saved field: $key." }
        if ($value) {
            if ($value -match '[\r\n]' -or $value -notmatch ('^\s*' + $key + '\s*=')) { throw "Invalid saved line: $key." }
            $lines.Add($value)
        }
    }
    $tables = $state['provider_tables']
    if ($tables -isnot [string] -or [string]::IsNullOrWhiteSpace($tables)) { throw 'Missing saved provider tables.' }
    $rootText = $lines -join "`n"
    Assert-ConfigShape ($rootText + "`n" + $tables)
    if ((Get-RootValue $rootText 'model_provider') -cne $id) { throw 'Saved provider selector mismatch.' }
    if ([string]::IsNullOrWhiteSpace((Edit-ProviderTable $tables $id -Extract)) -or
        -not [string]::IsNullOrWhiteSpace((Edit-ProviderTable $tables $id))) {
        throw 'State contains unrelated configuration; refusing restore.'
    }
    [pscustomobject]@{ ProviderId = $id; Lines = $lines; Tables = $tables }
}
function Write-ConfigChange([string]$Original, [string]$Updated) {
    if ((Read-Config) -cne $Original) { throw 'Config changed during operation; close other editors and retry.' }
    if ($Original -ceq $Updated) { return }
    Backup-File $ConfigPath 'config' 'toml'
    Write-AtomicText $ConfigPath $Updated
}
function Invoke-GptSelection {
    $original = Read-Config
    Assert-ConfigShape $original
    [void](Save-ProviderState $original)
    $text = $original
    $provider = Get-RootValue $text 'model_provider'
    if ($provider -and $provider -cne 'openai') { $text = Edit-ProviderTable $text $provider }
    $text = ConvertTo-SelectedRoot $text @($ManagedComment, 'model_provider = "openai"', 'forced_login_method = "chatgpt"')
    Write-ConfigChange $original $text
    Write-Host '[OK] GPT: openai provider with ChatGPT OAuth. Model uses the Codex/account default.'
}
function Invoke-ProviderRestore {
    $state = Read-ProviderState
    $original = Read-Config
    Assert-ConfigShape $original
    $provider = Get-RootValue $original 'model_provider'
    if ($provider -and $provider -cne 'openai' -and $provider -cne $state.ProviderId) {
        throw 'A different custom provider is active. Run Init to explicitly save it first.'
    }
    $text = Edit-ProviderTable $original $state.ProviderId
    $text = ConvertTo-SelectedRoot $text (@($ManagedComment) + @($state.Lines))
    $text = $text.TrimEnd() + "`n`n" + $state.Tables.TrimEnd() + "`n"
    Write-ConfigChange $original $text
    Write-Host "[OK] Restored custom provider: $($state.ProviderId)"
    $match = [regex]::Match($state.Tables, '(?m)^\s*env_key\s*=\s*["'']([^"'']+)["'']')
    if ($match.Success -and [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($match.Groups[1].Value))) {
        Write-Warning "Provider environment variable $($match.Groups[1].Value) is absent in this process. Restart the terminal after changing persistent variables."
    }
}
function Show-Status {
    $text = Read-Config
    $provider = Get-RootValue $text 'model_provider'
    $model = Get-RootValue $text 'model'
    $login = Get-RootValue $text 'forced_login_method'
    Write-Host "Codex home : $CodexHome"
    Write-Host "Config     : $(if ([IO.File]::Exists($ConfigPath)) { 'present' } else { 'missing' })"
    Write-Host "Provider   : $(if ($provider) { $provider } else { 'openai (default)' })"
    Write-Host "Model      : $(if ($model) { $model } else { '(Codex/account default)' })"
    Write-Host "Login rule : $(if ($login) { $login } else { '(not forced)' })"
    Write-Host "DS state   : $(if ([IO.File]::Exists($StatePath)) { 'saved (not validated by Status)' } else { 'not saved' })"
}
function Invoke-CodexCheck([bool]$GptSelected, [bool]$SkipLogin, [bool]$OmitDoctor) {
    if ($SkipLogin -and ($OmitDoctor -or -not $GptSelected)) { return }
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        Write-Warning 'Codex was not found in PATH. Local configuration operations are complete.'
        return
    }
    if (-not $SkipLogin) {
        # An API-key login can also exit successfully. Check the ChatGPT label.
        $status = & codex login status 2>&1
        $loginExit = $LASTEXITCODE
        if ($GptSelected -and ($loginExit -ne 0 -or ($status -join "`n") -notmatch '(?i)logged in using chatgpt')) {
            Write-Host '[AUTH] Requesting ChatGPT browser login.'
            & codex login
            if ($LASTEXITCODE -ne 0) { throw 'Codex login failed. Configuration is saved; use a backup to revert.' }
        } else { Write-Host "[AUTH] Codex login status exit code: $loginExit (not a connectivity check)." }
    }
    if ($GptSelected -and -not $OmitDoctor) {
        $help = & codex --help 2>&1
        if (($help -join "`n") -match '(?m)^\s+doctor\b') {
            & codex doctor
            if ($LASTEXITCODE -ne 0) { Write-Warning 'Codex diagnostics returned a nonzero exit code; configuration remains saved.' }
        } else { Write-Warning 'This Codex CLI does not advertise doctor. Skipping optional diagnostics.' }
    }
}
$gptSelected = $false
if ($Mode -eq 'Status') { Show-Status } else {
    [IO.Directory]::CreateDirectory($BackupDir) | Out-Null
    $lock = $null
    try {
        $lock = [IO.File]::Open((Join-Path $StateDir '.lock'), [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $action = $Mode
        if ($action -eq 'Toggle') {
            $provider = Get-RootValue (Read-Config) 'model_provider'
            $action = if (-not $provider -or $provider -ceq 'openai') { 'DeepSeek' } else { 'GPT' }
        }
        switch ($action) {
            'GPT' { Invoke-GptSelection; $gptSelected = $true }
            'DeepSeek' { Invoke-ProviderRestore }
            'Init' {
                $text = Read-Config
                Assert-ConfigShape $text
                Backup-File $ConfigPath 'config' 'toml'
                if (Save-ProviderState $text) { Write-Host '[OK] Saved current custom provider.' }
                else { Write-Host '[INFO] No active custom provider; existing saved state is unchanged.' }
                Show-Status
            }
        }
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
}
if ($Mode -ne 'DeepSeek') { Invoke-CodexCheck $gptSelected ([bool]$NoLogin) ([bool]$SkipDoctor) }
