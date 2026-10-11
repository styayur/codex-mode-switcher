function Write-ModeFailure([string]$Code, [string]$Message) {
    $exception = [InvalidOperationException]::new($Message)
    $exception.Data['Code'] = $Code
    $exception.Data['SafeMessage'] = $Message
    throw $exception
}

function Assert-RegularPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                Write-ModeFailure 'LinkedPath' 'Linked configuration/state paths are unsupported; no files were changed.'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Get-ByteHash([byte[]]$Bytes) { [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant() }

function Get-FileSnapshot([string]$Path) {
    Assert-RegularPath $Path
    if ([IO.Directory]::Exists($Path)) { Write-ModeFailure 'PathInvalid' 'A managed file path points to a directory.' }
    $exists = [IO.File]::Exists($Path)
    [byte[]]$bytes = [byte[]]::new(0)
    if ($exists) { $bytes = [IO.File]::ReadAllBytes($Path) }
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes).TrimStart([char]0xfeff)
    [pscustomobject]@{ Path = $Path; Exists = $exists; Bytes = $bytes; Text = $text
        Hash = if ($exists) { Get-ByteHash $bytes } else { 'absent' } }
}

function Assert-SnapshotCurrent($Snapshot) {
    if ((Get-FileSnapshot $Snapshot.Path).Hash -cne $Snapshot.Hash) {
        Write-ModeFailure 'ConcurrentChange' 'Configuration or provider state changed concurrently; re-run after closing other editors.'
    }
}

function Assert-SwitchPlanApplied($Plan) {
    foreach ($role in $Plan.Snapshots.Keys) {
        $write = @($Plan.Writes | Where-Object { $_.Role -eq $role })
        $expected = if ($write.Count) { $write[0].Hash } else { $Plan.Snapshots[$role].Hash }
        if ((Get-FileSnapshot $Plan.Snapshots[$role].Path).Hash -cne $expected) {
            Write-ModeFailure 'ConcurrentChange' 'Configuration or provider state changed after commit. No activation attempted; newer files are preserved.'
        }
    }
}

function Write-AtomicFile([string]$Path, [byte[]]$Bytes) {
    Assert-RegularPath $Path
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($Bytes); $stream.Flush($true) } finally { $stream.Dispose() }
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Write-TransactionJournal($Context, $Journal) {
    $path = Join-Path $Context.JournalDirectory ($Journal.id + '.json')
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Journal | ConvertTo-Json -Depth 8))
    Write-AtomicFile $path $bytes
    if ((Get-FileSnapshot $path).Hash -cne (Get-ByteHash $bytes)) {
        Write-ModeFailure 'JournalVerificationFailed' 'Transaction journal verification failed.'
    }
}

function Get-PendingTransaction($Context) {
    if (-not [IO.Directory]::Exists($Context.JournalDirectory)) { return @() }
    $pending = [Collections.Generic.List[string]]::new()
    Assert-RegularPath $Context.JournalDirectory
    foreach ($file in (Get-ChildItem -LiteralPath $Context.JournalDirectory -Filter '*.json' -File)) {
        try {
            $journal = (Get-FileSnapshot $file.FullName).Text | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ($journal.status -notin @('Committed', 'RolledBack', 'Recovered')) { $pending.Add($file.BaseName) }
        } catch { $pending.Add($file.BaseName) }
    }
    return @($pending)
}

function Undo-TransactionWrite($Context, $Entries) {
    # Check every boundary before restoring any file. Never overwrite another writer.
    foreach ($entry in $Entries) {
        $current = Get-FileSnapshot $Context.Files[$entry.role]
        if ($current.Hash -cne $entry.before_hash -and $current.Hash -cne $entry.after_hash) { return 'Conflict' }
        if ($entry.before_hash -ne 'absent' -and
            (Get-FileSnapshot (Join-Path $Context.BackupDirectory $entry.backup)).Hash -cne $entry.before_hash) { return 'BackupInvalid' }
    }
    foreach ($entry in @($Entries | Sort-Object { $_.role -eq 'config' } -Descending)) {
        $path = $Context.Files[$entry.role]
        $current = Get-FileSnapshot $path
        if ($current.Hash -ceq $entry.before_hash) { continue }
        if ($current.Hash -cne $entry.after_hash) { return 'Conflict' }
        if ($entry.before_hash -eq 'absent') {
            [IO.File]::Delete($path)
        } else {
            $backup = Get-FileSnapshot (Join-Path $Context.BackupDirectory $entry.backup)
            if ($backup.Hash -cne $entry.before_hash) { return 'BackupInvalid' }
            Assert-SnapshotCurrent $current
            Write-AtomicFile $path $backup.Bytes
        }
        if ((Get-FileSnapshot $path).Hash -cne $entry.before_hash) { return 'VerificationFailed' }
    }
    return 'Restored'
}

function Invoke-SwitchTransaction($Context, $Plan, [scriptblock]$SafetyCheck) {
    Assert-RegularPath $Context.StateDirectory
    Assert-RegularPath $Context.BackupDirectory
    Assert-RegularPath $Context.JournalDirectory
    Assert-RegularPath $Context.LockPath
    [IO.Directory]::CreateDirectory($Context.BackupDirectory) | Out-Null
    [IO.Directory]::CreateDirectory($Context.JournalDirectory) | Out-Null
    $lock = $null
    $journal = $null
    try {
        try { $lock = [IO.File]::Open($Context.LockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { Write-ModeFailure 'LockBusy' 'Another switch or recovery holds the configuration lock.' }
        if (@(Get-PendingTransaction $Context).Count) {
            Write-ModeFailure 'RecoveryRequired' 'An incomplete transaction needs recovery before another switch. Run Diagnose.'
        }
        foreach ($snapshot in $Plan.Snapshots.Values) { Assert-SnapshotCurrent $snapshot }
        & $SafetyCheck
        $id = [guid]::NewGuid().ToString('N')
        $entries = [Collections.Generic.List[object]]::new()
        $backupRoles = @($Plan.Writes | ForEach-Object { $_.Role })
        if ($Plan.BackupConfig -and 'config' -notin $backupRoles) { $backupRoles += 'config' }
        foreach ($role in $backupRoles) {
            $before = $Plan.Snapshots[$role]
            $extension = if ($role -eq 'config') { 'toml' } else { 'json' }
            $backupName = "$role.$id.$extension"
            if ($before.Exists) {
                $backupPath = Join-Path $Context.BackupDirectory $backupName
                $stream = [IO.File]::Open($backupPath, 'CreateNew', 'Write', 'None')
                try { $stream.Write($before.Bytes); $stream.Flush($true) } finally { $stream.Dispose() }
                if ((Get-FileSnapshot $backupPath).Hash -cne $before.Hash) { Write-ModeFailure 'BackupInvalid' 'Backup verification failed.' }
            }
            $write = @($Plan.Writes | Where-Object { $_.Role -eq $role })
            $entries.Add([ordered]@{ role = $role; before_hash = $before.Hash
                after_hash = if ($write.Count) { $write[0].Hash } else { $before.Hash }
                backup = if ($before.Exists) { $backupName } else { $null } })
        }
        $journal = [ordered]@{ schema_version = 1; id = $id; action = $Plan.Action
            started_at = [DateTime]::UtcNow.ToString('o'); status = 'Prepared'; rollback = 'NotRequired'; files = @($entries) }
        Write-TransactionJournal $Context $journal
        # Recheck after backups/journal I/O, before the first file replacement.
        foreach ($snapshot in $Plan.Snapshots.Values) { Assert-SnapshotCurrent $snapshot }
        & $SafetyCheck
        foreach ($write in $Plan.Writes) {
            Assert-SnapshotCurrent $write.Before
            Write-AtomicFile $write.Before.Path $write.Bytes
            if ((Get-FileSnapshot $write.Before.Path).Hash -cne $write.Hash) {
                Write-ModeFailure 'WriteVerificationFailed' 'Written file verification failed.'
            }
        }
        foreach ($entry in $entries) {
            if ((Get-FileSnapshot $Context.Files[$entry.role]).Hash -cne $entry.after_hash) {
                Write-ModeFailure 'ConcurrentChange' 'Files changed before transaction commit.'
            }
        }
        if ($Plan.Action -ne 'Init') { Assert-ConfigShape (Get-FileSnapshot $Context.Files.config).Text }
        # COMMIT POINT: verified files + durable Committed journal, before launch.
        $journal.status = 'Committed'
        Write-TransactionJournal $Context $journal
        return [pscustomobject]@{ Id = $id; Changed = $Plan.Writes.Count -gt 0; Committed = $true; Rollback = 'NotRequired' }
    } catch {
        $failure = $_.Exception
        if ($null -ne $journal) {
            $rollback = 'Failed'
            # A durable committed record is authoritative, even if the caller lost
            # the acknowledgement. Never roll back across that boundary.
            try {
                $disk = (Get-FileSnapshot (Join-Path $Context.JournalDirectory ($journal.id + '.json'))).Text | ConvertFrom-Json
                if ($disk.status -eq 'Committed') {
                    $failure.Data['Committed'] = $true
                    $rollback = 'NotAttemptedAfterCommit'
                } else { $rollback = Undo-TransactionWrite $Context $journal.files }
            } catch { $rollback = 'Failed' }
            if ($rollback -ne 'NotAttemptedAfterCommit') {
                $journal.status = if ($rollback -eq 'Restored') { 'RolledBack' } else { 'RecoveryRequired' }
                $journal.rollback = $rollback
                try { Write-TransactionJournal $Context $journal } catch { $rollback = 'JournalUpdateFailed' }
            }
            $failure.Data['TransactionId'] = $journal.id
            $failure.Data['Rollback'] = $rollback
        }
        throw $failure
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
}

function Read-RecoveryJournal($Context, [string]$TransactionId) {
    if ($TransactionId -cnotmatch '^[a-f0-9]{32}$') { Write-ModeFailure 'RecoveryInvalid' 'TransactionId must be a recorded 32-character transaction ID.' }
    try {
        $snapshot = Get-FileSnapshot (Join-Path $Context.JournalDirectory "$TransactionId.json")
        $journal = $snapshot.Text | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($journal.schema_version -ne 1 -or $journal.id -cne $TransactionId -or
            $journal.status -notin @('Prepared', 'RecoveryRequired', 'RolledBack', 'Recovered')) { throw 'Invalid journal' }
        $roles = @()
        foreach ($entry in $journal.files) {
            if ($entry.role -notin @('config', 'state', 'gpt') -or $entry.role -in $roles) { throw 'Invalid role' }
            $roles += $entry.role
            foreach ($hash in @($entry.before_hash, $entry.after_hash)) {
                if ($hash -cnotmatch '^(absent|[a-f0-9]{64})$') { throw 'Invalid hash' }
            }
            if ($entry.before_hash -ne 'absent') {
                $extension = if ($entry.role -eq 'config') { 'toml' } else { 'json' }
                if ($entry.backup -cne "$($entry.role).$TransactionId.$extension") { throw 'Invalid backup name' }
                if ((Get-FileSnapshot (Join-Path $Context.BackupDirectory $entry.backup)).Hash -cne $entry.before_hash) { throw 'Invalid backup' }
            }
        }
    } catch { Write-ModeFailure 'RecoveryInvalid' 'Recovery journal or backup is invalid, missing, or already committed. No files restored.' }
    [pscustomobject]@{ Journal = $journal; Snapshot = $snapshot }
}

function Invoke-TransactionRecovery($Context, $Recovery, [scriptblock]$SafetyCheck) {
    $lock = $null
    try {
        $lock = [IO.File]::Open($Context.LockPath, 'OpenOrCreate', 'ReadWrite', 'None')
        Assert-SnapshotCurrent $Recovery.Snapshot
        & $SafetyCheck
        $outcome = Undo-TransactionWrite $Context $Recovery.Journal.files
        if ($outcome -ne 'Restored') { Write-ModeFailure 'RecoveryConflict' 'Recovery stopped: files differ from recorded transaction values. Keep backups and inspect locally.' }
        $Recovery.Journal.status = 'Recovered'
        $Recovery.Journal.rollback = 'Restored'
        Write-TransactionJournal $Context $Recovery.Journal
        [pscustomobject]@{ Id = $Recovery.Journal.id; Changed = $true; Committed = $false; Rollback = 'Restored' }
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
}
