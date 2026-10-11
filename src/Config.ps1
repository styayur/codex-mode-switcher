function Get-ConfigPart([string]$Text) {
    $root = [Collections.Generic.List[string]]::new()
    $tables = [Collections.Generic.List[string]]::new()
    $inTables = $false
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -cmatch '^\s*\[') { $inTables = $true }
        if ($inTables) { $tables.Add($line) } else { $root.Add($line) }
    }
    [pscustomobject]@{ Root = $root; Tables = $tables }
}
function Get-RootLine([string]$Text, [string]$Key) {
    foreach ($line in (Get-ConfigPart $Text).Root) {
        if ($line -cmatch ('^\s*' + [regex]::Escape($Key) + '\s*=')) { return $line }
    }
    return $null
}
function Get-RootValue([string]$Text, [string]$Key) {
    $line = Get-RootLine $Text $Key
    if ($null -eq $line) { return $null }
    $match = [regex]::Match($line, '^\s*\w+\s*=\s*(?:"((?:[^"\\]|\\.)*)"|''([^'']*)'')\s*(?:#.*)?$')
    if (-not $match.Success) { Write-ModeFailure 'ConfigInvalid' "Unsupported managed value: $Key. Use a single-line TOML string." }
    if ($match.Groups[1].Success) { return $match.Groups[1].Value }
    return $match.Groups[2].Value
}
function Assert-ConfigShape([string]$Text) {
    # Conservative line editor; refuse syntax that could obscure table boundaries.
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -cmatch '^\s*(#.*)?$') { continue }
        if ($line.Contains('"""') -or $line.Contains("'''")) { Write-ModeFailure 'ConfigInvalid' 'Multiline TOML strings are unsupported.' }
        if ($line -cmatch '^\s*\[') {
            if ($line -cnotmatch '^\s*\[\[?[^\r\n]+\]\]?\s*(?:#.*)?$') { Write-ModeFailure 'ConfigInvalid' 'Unsupported multiline TOML value.' }
            if ($line -cmatch '^\s*\[\[?\s*["'']?model_providers' -and
                $line -cnotmatch '^\s*\[model_providers(?:\.[A-Za-z0-9_-]+)*\]\s*(?:#.*)?$') {
                Write-ModeFailure 'ConfigInvalid' 'Use bare model_providers table names; quoted/array provider tables are unsupported.'
            }
        } elseif ($line -cnotmatch '^\s*[^=]+\s*=\s*\S.*$' -or $line -cmatch '=\s*[\[{]\s*(?:#.*)?$') {
            Write-ModeFailure 'ConfigInvalid' 'Unsupported multiline or malformed TOML.'
        }
    }
    $root = (Get-ConfigPart $Text).Root
    foreach ($key in $SwitchKeys) {
        $pattern = '^\s*' + $key + '\s*='
        if (@($root | Where-Object { $_ -cmatch $pattern }).Count -gt 1) { Write-ModeFailure 'ConfigInvalid' "Duplicate managed key: $key." }
        if (@($root | Where-Object { $_ -cmatch ('^\s*["'']' + $key + '["'']\s*=|^\s*' + $key + '\s*\.') }).Count) {
            Write-ModeFailure 'ConfigInvalid' "Unsupported quoted/dotted managed key: $key."
        }
        [void](Get-RootValue $Text $key)
    }
    $provider = Get-RootValue $Text 'model_provider'
    if ($provider -and $provider -cnotmatch '^[A-Za-z0-9_-]+$') { Write-ModeFailure 'ConfigInvalid' 'Unsupported provider ID.' }
}
function Edit-ProviderTable([string]$Text, [string]$ProviderId, [switch]$Extract) {
    $result = [Collections.Generic.List[string]]::new()
    $selected = $false
    $prefix = 'model_providers.' + $ProviderId
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -cmatch '^\s*\[') {
            $selected = $false
            if ($line -cmatch '^\s*\[([^\]]+)\]\s*(?:#.*)?$') {
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
            if ($line -cmatch ('^\s*' + $key + '\s*=')) { $drop = $true; break }
        }
        if (-not $drop) { $root.Add($line) }
    }
    $remaining = ($root -join "`n") -replace '\n{3,}', "`n`n"
    return ($remaining.TrimEnd() + "`n" + (($parts.Tables -join "`n").TrimEnd()) + "`n").TrimEnd() + "`n"
}
