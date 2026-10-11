function Get-ShortcutBlock([string]$EntryPath) {
    $literal = $EntryPath.Replace("'", "''")
    @'
# codex-mode-switcher shortcuts: begin
# Registration only. No discovery, login or Desktop launch during shell startup.
if (-not (Get-Command cdx-gpt -ListImported -ErrorAction SilentlyContinue)) {
    function global:cdx-gpt { & '__ENTRY__' GPT -Launch @args }
}
if (-not (Get-Command cdx-deepseek -ListImported -ErrorAction SilentlyContinue)) {
    function global:cdx-deepseek { & '__ENTRY__' DeepSeek -Launch @args }
}
# codex-mode-switcher shortcuts: end
'@.Replace('__ENTRY__', $literal)
}

function Invoke-DesktopShortcut {
    [CmdletBinding()]
    param(
        [ValidateSet('Install', 'Uninstall')][string]$Action = 'Install',
        [Parameter(Mandatory)][string]$ProfilePath,
        [switch]$DryRun
    )
    $ErrorActionPreference = 'Stop'
    if (-not [IO.Path]::IsPathFullyQualified($ProfilePath) -or [IO.Path]::GetExtension($ProfilePath) -ine '.ps1') {
        Write-ModeFailure 'ProfileInvalid' 'ProfilePath must be an absolute .ps1 path.'
    }
    $entry = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../codex-mode.ps1'))
    if ($entry -match '[\r\n]') { Write-ModeFailure 'ProfileInvalid' 'The script path contains unsupported characters.' }
    $snapshot = Get-FileSnapshot $ProfilePath
    $text = $snapshot.Text
    $block = (Get-ShortcutBlock $entry) -replace '\r\n', "`n"
    $normalized = $text -replace '\r\n', "`n"
    $begin = '# codex-mode-switcher shortcuts: begin'
    $end = '# codex-mode-switcher shortcuts: end'
    $hasBlock = $normalized.Contains($begin) -or $normalized.Contains($end)
    if ($hasBlock -and (-not $normalized.Contains($block) -or
        [regex]::Matches($normalized, [regex]::Escape($begin)).Count -ne 1 -or
        [regex]::Matches($normalized, [regex]::Escape($end)).Count -ne 1)) {
        Write-ModeFailure 'ProfileConflict' 'The existing shortcut block was edited or belongs to another checkout. Preserve it and inspect manually.'
    }
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { Write-ModeFailure 'ProfileInvalid' 'Existing profile syntax is invalid; no change made.' }
    if ($Action -eq 'Install' -and -not $hasBlock) {
        $definitions = @($ast.FindAll({ param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            ($node.Name -replace '^global:', '') -in @('cdx-gpt', 'cdx-deepseek')
        }, $true))
        $commands = @(Get-Command cdx-gpt,cdx-deepseek -ListImported -ErrorAction SilentlyContinue)
        # Alias/Set-Item constructions are conservatively detected as text too.
        if ($definitions.Count -or $commands.Count -or $text -match '(?i)\bcdx-(gpt|deepseek)\b') {
            Write-ModeFailure 'ProfileConflict' 'An existing cdx-gpt or cdx-deepseek definition would conflict. No profile change made.'
        }
        $updated = $text.TrimEnd() + "`n`n" + $block + "`n"
    } elseif ($Action -eq 'Uninstall' -and $hasBlock) {
        # Preserve the user's content/newlines outside our exact owned block.
        $existingBlock = if ($text.Contains($block)) { $block } else { $block.Replace("`n", "`r`n") }
        $updated = $text.Replace($existingBlock, '')
    } else { $updated = $text }
    $result = [pscustomobject]@{ Action = $Action; DryRun = [bool]$DryRun; Changed = $updated -cne $text
        ProfilePath = $ProfilePath; BackupPath = $null; Preview = if ($DryRun -and $Action -eq 'Install') { $block } else { $null } }
    if ($DryRun -or -not $result.Changed) { return $result }
    [void][Management.Automation.Language.Parser]::ParseInput($updated, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { Write-ModeFailure 'ProfileInvalid' 'Generated profile did not pass syntax validation.' }
    Assert-RegularPath $ProfilePath
    [IO.Directory]::CreateDirectory((Split-Path $ProfilePath)) | Out-Null
    $lock = $null
    try {
        $lock = [IO.File]::Open(($ProfilePath + '.codex-mode.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
        Assert-SnapshotCurrent $snapshot
        if ($snapshot.Exists) {
            $result.BackupPath = $ProfilePath + '.codex-mode.' + [guid]::NewGuid().ToString('N') + '.bak'
            [IO.File]::WriteAllBytes($result.BackupPath, $snapshot.Bytes)
            if ((Get-FileSnapshot $result.BackupPath).Hash -cne $snapshot.Hash) { Write-ModeFailure 'BackupInvalid' 'Profile backup validation failed.' }
        }
        Assert-SnapshotCurrent $snapshot
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($updated)
        Write-AtomicFile $ProfilePath $bytes
        if ((Get-FileSnapshot $ProfilePath).Hash -cne (Get-ByteHash $bytes)) { Write-ModeFailure 'ProfileConflict' 'Profile changed during installation. Preserve the backup and inspect manually.' }
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
    return $result
}
