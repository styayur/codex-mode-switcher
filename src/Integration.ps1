function Get-IntegrationContext {
    if (-not $IsWindows) { Write-ModeFailure 'WindowsRequired' 'Windows integrations require Windows.' }
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    $programs = [Environment]::GetFolderPath('Programs')
    $state = Join-Path $local 'CodexModeSwitcher/integrations'
    [pscustomobject]@{
        State = $state; Ledger = Join-Path $state 'ownership.json'; Lock = Join-Path $state '.lock'
        Backups = Join-Path $state 'backups'
        Terminal = Join-Path $local 'Microsoft/Windows Terminal/Fragments/styayur.codex-mode-switcher/profiles.json'
        Programs = Join-Path $programs 'Codex Mode Switcher'
        Entry = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../codex-mode.ps1'))
        PowerShell = Join-Path $PSHOME 'pwsh.exe'
    }
}

function Get-IntegrationTarget($Context) {
    @(
        [pscustomobject]@{ Id='terminal'; Kind='terminal'; Path=$Context.Terminal; Mode=$null }
        [pscustomobject]@{ Id='startmenu-gpt'; Kind='startmenu'; Path=(Join-Path $Context.Programs 'Codex GPT.lnk'); Mode='GPT' }
        [pscustomobject]@{ Id='startmenu-deepseek'; Kind='startmenu'; Path=(Join-Path $Context.Programs 'Codex DeepSeek.lnk'); Mode='DeepSeek' }
        [pscustomobject]@{ Id='startmenu-diagnose'; Kind='startmenu'; Path=(Join-Path $Context.Programs 'Codex Diagnose.lnk'); Mode='Diagnose' }
        [pscustomobject]@{ Id='notifications'; Kind='notifications'; Path=(Join-Path $Context.Programs 'Codex Mode Switcher.lnk'); Mode='Diagnose' }
    )
}

function Get-IntegrationSnapshot([string]$Path) {
    Assert-RegularPath $Path
    if ([IO.Directory]::Exists($Path)) { Write-ModeFailure 'IntegrationConflict' 'An integration file path is occupied by a directory.' }
    $exists = [IO.File]::Exists($Path)
    [byte[]]$bytes = [byte[]]::new(0)
    if ($exists) { $bytes = [IO.File]::ReadAllBytes($Path) }
    [pscustomobject]@{ Path=$Path; Exists=$exists; Bytes=$bytes; Hash=$(if ($exists) { Get-ByteHash $bytes } else { 'absent' }) }
}

function Read-IntegrationLedger($Context) {
    $snapshot = Get-FileSnapshot $Context.Ledger
    if (-not $snapshot.Exists) { return [ordered]@{ owner='styayur.codex-mode-switcher'; schema_version=1; entries=@() } }
    try {
        $ledger = $snapshot.Text | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($ledger.owner -cne 'styayur.codex-mode-switcher' -or $ledger.schema_version -ne 1) { throw 'Invalid owner/version' }
        $known = @((Get-IntegrationTarget $Context).Id)
        $seen = @()
        foreach ($entry in $ledger.entries) {
            if ($entry.id -cnotin $known -or $entry.id -cin $seen -or $entry.hash -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid record' }
            $seen += $entry.id
        }
        if ($ledger.entries -isnot [array]) { throw 'Invalid entries' }
        return $ledger
    } catch { Write-ModeFailure 'IntegrationStateInvalid' 'Integration ownership data is invalid. No user files may be changed until it is reviewed locally.' }
}

function Write-IntegrationLedger($Context, $Ledger) {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Ledger | ConvertTo-Json -Depth 6))
    Write-AtomicFile $Context.Ledger $bytes
    if ((Get-IntegrationSnapshot $Context.Ledger).Hash -cne (Get-ByteHash $bytes)) { Write-ModeFailure 'IntegrationVerificationFailed' 'Ownership record verification failed.' }
}

function Write-NewIntegrationFile([string]$Path, [byte[]]$Bytes) {
    Assert-RegularPath $Path
    $temporary=$Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $stream=[IO.File]::Open($temporary,'CreateNew','Write','None')
        try { $stream.Write($Bytes); $stream.Flush($true) } finally { $stream.Dispose() }
        # Same-directory atomic move, refusing an existing destination.
        [IO.File]::Move($temporary,$Path)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Test-TerminalAvailable {
    $null -ne (Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-IntegrationArgument($Context, [string]$Mode) {
    if ($Context.Entry -match '["\r\n]' -or $Context.PowerShell -match '["\r\n]') { Write-ModeFailure 'IntegrationPathInvalid' 'Installation paths contain unsupported characters.' }
    $suffix = if ($Mode -in @('GPT','DeepSeek')) { ' -Launch -WaitForExit' } else { '' }
    return ('-NoLogo -NoProfile -NoExit -File "{0}" {1}{2}' -f $Context.Entry, $Mode, $suffix)
}

function ConvertTo-IntegrationPayload($Context, $Target) {
    if ($Target.Kind -eq 'terminal') {
        $modes = @('GPT','DeepSeek','Diagnose')
        $guids = @('{637765c7-37ae-4520-9e2b-43b4efaeafba}','{8917d7cc-d9cc-4f59-9977-d6687880a8af}','{6b8ef1ab-0205-47b7-94e0-ea799d5c0867}')
        $profiles = @(for ($i=0; $i -lt $modes.Count; $i++) {
            [ordered]@{ guid=$guids[$i]; name=('Codex ' + $modes[$i]);
                commandline=('"{0}" {1}' -f $Context.PowerShell, (Get-IntegrationArgument $Context $modes[$i]));
                startingDirectory='%USERPROFILE%'; hidden=$false }
        })
        return ,([Text.UTF8Encoding]::new($false).GetBytes((@{ profiles=$profiles } | ConvertTo-Json -Depth 6)))
    }
    if (-not ('CodexMode.NativeShortcut' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'NativeShortcut.cs') }
    $temporary = Join-Path $Context.State ([guid]::NewGuid().ToString('N') + '.lnk')
    try {
        [CodexMode.NativeShortcut]::Create($temporary, $Context.PowerShell,
            (Get-IntegrationArgument $Context $Target.Mode), 'styayur.CodexModeSwitcher')
        if ([CodexMode.NativeShortcut]::GetAppId($temporary) -cne 'styayur.CodexModeSwitcher') {
            Write-ModeFailure 'IntegrationVerificationFailed' 'Shortcut application identity failed verification.'
        }
        return ,([IO.File]::ReadAllBytes($temporary))
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Get-CodexIntegration {
    [CmdletBinding()]
    param()
    $ErrorActionPreference = 'Stop'
    $context = Get-IntegrationContext
    $ledger = Read-IntegrationLedger $context
    foreach ($kind in @('terminal','startmenu','notifications')) {
        $files = @(foreach ($target in (Get-IntegrationTarget $context | Where-Object Kind -EQ $kind)) {
            $record = @($ledger.entries | Where-Object id -CEQ $target.Id)
            $current = Get-IntegrationSnapshot $target.Path
            [pscustomobject]@{ Id=$target.Id; Path=$target.Path; Owned=($record.Count -eq 1); Present=$current.Exists
                Matches=($record.Count -eq 1 -and $current.Hash -ceq $record[0].hash) }
        })
        $owned = @($files | Where-Object Owned)
        $conflicts = @($files | Where-Object { $_.Present -and -not $_.Matches })
        $status = if ($conflicts.Count) { 'Conflict' } elseif (-not $owned.Count) { 'NotInstalled' }
        elseif (@($files | Where-Object Matches).Count -eq $files.Count) { 'Installed' } else { 'Partial' }
        [pscustomobject]@{ Kind=$kind; Status=$status; Files=$files
            CanUninstall=($owned.Count -gt 0 -and -not @($owned | Where-Object { $_.Present -and -not $_.Matches }).Count)
            OwnershipFile=$context.Ledger; RetainedBackups=$context.Backups }
    }
}

function Invoke-CodexIntegration {
    [CmdletBinding()]
    param(
        [ValidateSet('Install','Uninstall')][string]$Action = 'Install',
        [Parameter(Mandatory)][ValidateSet('terminal','startmenu','notifications','all')][string]$Kind,
        [switch]$Apply, [switch]$DryRun
    )
    $ErrorActionPreference = 'Stop'
    if ($Kind -eq 'all' -and $Action -ne 'Uninstall') { Write-ModeFailure 'ArgumentsInvalid' 'all is supported only for uninstall.' }
    $context = Get-IntegrationContext
    $targets = @(Get-IntegrationTarget $context | Where-Object { $Kind -eq 'all' -or $_.Kind -eq $Kind })
    $result = [pscustomobject]@{ Action=$Action; Kind=$Kind; State='Preview'; Changed=$false
        Files=@($targets.Path)
        Commands=@(foreach ($mode in @('GPT','DeepSeek','Diagnose')) {
            '"{0}" {1}' -f $context.PowerShell, (Get-IntegrationArgument $context $mode)
        })
        Message='Preview only. Review these paths and commands, then repeat with -Apply to approve changes.' }
    if ($Action -eq 'Install' -and $Kind -eq 'terminal' -and -not (Test-TerminalAvailable)) {
        $result.State='Unavailable'; $result.Message='Windows Terminal (wt.exe) was not found. No files changed.'; return $result
    }
    $ledger = Read-IntegrationLedger $context
    # Preview and real operations both refuse conflicts. Never adopt an unowned file.
    foreach ($target in $targets) {
        $current = Get-IntegrationSnapshot $target.Path
        $record = @($ledger.entries | Where-Object id -CEQ $target.Id)
        if ($current.Exists -and (($record.Count -and $record[0].hash -cne $current.Hash) -or
            (-not $record.Count -and $Action -eq 'Install'))) {
            Write-ModeFailure 'IntegrationConflict' 'An integration file is unowned or was modified. Preserve it and review locally; no overwrite or removal performed.'
        }
    }
    if (-not $Apply -or $DryRun) { return $result }
    if ($Action -eq 'Uninstall' -and -not @($ledger.entries | Where-Object { $_.id -cin $targets.Id }).Count) {
        $result.State='Unchanged'; $result.Message='No owned integration files to uninstall.'; return $result
    }
    foreach ($path in @($context.State,$context.Backups,$context.Lock)) { Assert-RegularPath $path }
    [IO.Directory]::CreateDirectory($context.State) | Out-Null
    $lock = $null
    $created = [Collections.Generic.List[object]]::new()
    $removed = [Collections.Generic.List[object]]::new()
    $original = Get-FileSnapshot $context.Ledger
    $proposedHash = $null
    try {
        try { $lock=[IO.File]::Open($context.Lock,'OpenOrCreate','ReadWrite','None') }
        catch { Write-ModeFailure 'IntegrationBusy' 'Another integration operation holds the lock.' }
        Assert-SnapshotCurrent $original
        # Re-read after locking; preflight may have overlapped another installer.
        $ledger = Read-IntegrationLedger $context
        if ($original.Exists) {
            [IO.Directory]::CreateDirectory($context.Backups) | Out-Null
            $backup=Join-Path $context.Backups ('ownership.' + [guid]::NewGuid().ToString('N') + '.bak')
            $stream=[IO.File]::Open($backup,'CreateNew','Write','None')
            try { $stream.Write($original.Bytes); $stream.Flush($true) } finally { $stream.Dispose() }
            if ((Get-IntegrationSnapshot $backup).Hash -cne $original.Hash) { Write-ModeFailure 'IntegrationVerificationFailed' 'Ownership backup verification failed.' }
        }
        foreach ($target in $targets) {
            $current = Get-IntegrationSnapshot $target.Path
            $record = @($ledger.entries | Where-Object id -CEQ $target.Id)
            if ($current.Exists -and $record.Count -and $current.Hash -cne $record[0].hash) { Write-ModeFailure 'IntegrationConflict' 'Owned integration changed concurrently; it was preserved.' }
            if ($Action -eq 'Install') {
                if ($current.Exists) {
                    if (-not $record.Count) { Write-ModeFailure 'IntegrationConflict' 'Unowned integration file exists; it was preserved.' }
                    continue
                }
                $bytes = ConvertTo-IntegrationPayload $context $target
                Assert-RegularPath $target.Path
                [IO.Directory]::CreateDirectory((Split-Path $target.Path)) | Out-Null
                Write-NewIntegrationFile $target.Path $bytes
                $expected = Get-ByteHash $bytes
                $created.Add([pscustomobject]@{ Path=$target.Path; Hash=$expected })
                if ((Get-IntegrationSnapshot $target.Path).Hash -cne $expected) { Write-ModeFailure 'IntegrationConflict' 'New integration failed verification.' }
                $ledger.entries=@($ledger.entries | Where-Object id -CNE $target.Id) + @(@{ id=$target.Id; hash=$expected })
            } elseif ($record.Count) {
                if ($current.Exists) {
                    [IO.Directory]::CreateDirectory($context.Backups) | Out-Null
                    $backup=Join-Path $context.Backups ($target.Id + '.' + [guid]::NewGuid().ToString('N') + '.bak')
                    $stream=[IO.File]::Open($backup,'CreateNew','Write','None')
                    try { $stream.Write($current.Bytes); $stream.Flush($true) } finally { $stream.Dispose() }
                    if ((Get-IntegrationSnapshot $backup).Hash -cne $current.Hash -or
                        (Get-IntegrationSnapshot $target.Path).Hash -cne $current.Hash) { Write-ModeFailure 'IntegrationConflict' 'Backup or target changed; removal stopped.' }
                    [IO.File]::Delete($target.Path)
                    $removed.Add($current)
                }
                $ledger.entries=@($ledger.entries | Where-Object id -CNE $target.Id)
            }
        }
        if (-not $created.Count -and -not $removed.Count -and $original.Exists -and
            ($original.Text | ConvertFrom-Json -AsHashtable | ConvertTo-Json -Depth 6) -ceq ($ledger | ConvertTo-Json -Depth 6)) {
            $result.State='Unchanged'; $result.Message='Already in the requested state.'; return $result
        }
        Assert-SnapshotCurrent $original
        $proposedHash = Get-ByteHash ([Text.UTF8Encoding]::new($false).GetBytes(($ledger | ConvertTo-Json -Depth 6)))
        Write-IntegrationLedger $context $ledger
        $result.State='Applied'; $result.Changed=$created.Count -gt 0 -or $removed.Count -gt 0
        $result.Message='Owned integrations updated. Existing user settings were preserved. Empty directories and backup records are retained.'
    } catch {
        # Restore only files this invocation changed, and only at known byte boundaries.
        $rollbackIncomplete = $false
        foreach ($file in $created) {
            try { if ((Get-IntegrationSnapshot $file.Path).Hash -ceq $file.Hash) { [IO.File]::Delete($file.Path) } } catch { $rollbackIncomplete = $true }
        }
        foreach ($file in $removed) {
            try {
                Write-NewIntegrationFile $file.Path $file.Bytes
            } catch { $rollbackIncomplete = $true } # A newer file must never be replaced during rollback.
        }
        try {
            if ($proposedHash -and (Get-IntegrationSnapshot $context.Ledger).Hash -ceq $proposedHash) {
                if ($original.Exists) { Write-AtomicFile $context.Ledger $original.Bytes }
                else { [IO.File]::Delete($context.Ledger) }
            }
        } catch { $rollbackIncomplete = $true } # Retain records/backups for local review when restoration is unsafe.
        $message='Integration update stopped. Matching new files were removed and removed files restored where safe. Inspect integration list and retained backups before retrying.'
        if ($rollbackIncomplete) { $message += ' Some restoration steps need manual review.' }
        Write-ModeFailure 'IntegrationFailed' $message
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
    return $result
}
