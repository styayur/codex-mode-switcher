BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot) 'src/CodexMode.psm1')
    $script:OriginalHome = $env:CODEX_HOME
    $script:Entry = Join-Path (Split-Path $PSScriptRoot) 'codex-mode.ps1'
    $script:Fixture = @'
model_provider = "custom"
model = "custom-test"
model_reasoning_effort = "low"
sandbox_mode = "workspace-write"
[model_providers.custom]
name = "Synthetic provider"
base_url = "https://example.invalid/v1"
wire_api = "responses"
env_key = "SYNTHETIC_PROVIDER_CREDENTIAL"
[mcp_servers.example]
command = "synthetic-mcp"
'@
}
AfterAll { $env:CODEX_HOME = $script:OriginalHome }

Describe 'Desktop Controller and transaction boundaries' {
    BeforeEach {
        $env:CODEX_HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($env:CODEX_HOME) | Out-Null
        $script:Config = Join-Path $env:CODEX_HOME 'config.toml'
        [IO.File]::WriteAllText($script:Config, $script:Fixture)
        $script:Activated = $false
        Mock Get-DesktopIdentity -ModuleName CodexMode {
            [pscustomobject]@{ State = 'Installed'; Reason = 'Synthetic'; Reliable = $true; Kind = 'Win32'
                ExecutablePath = 'C:\synthetic\Desktop.exe'; AllExecutablePaths = @('C:\synthetic\Desktop.exe')
                Aumid = $null; PackageFamily = $null; Version = 'test'; ActivationMethod = 'CreateProcess' }
        }
        Mock Get-DesktopState -ModuleName CodexMode {
            [pscustomobject]@{ State = if ($script:Activated) { 'Running' } else { 'Ready' }
                Reliable = $true; ProcessIds = @(); TaskActivity = 'Unknown' }
        }
        Mock Request-DesktopActivation -ModuleName CodexMode { $script:Activated = $true; return 777 }
        Mock Test-InteractiveConsole -ModuleName CodexMode { $true }
        Mock Confirm-DesktopTasksStopped -ModuleName CodexMode { $true }
    }

    It 'commits and launches an installed stopped Desktop without claiming provider loading' {
        $result = Invoke-CodexMode GPT -Launch -NonInteractive -TasksStopped
        $result.State | Should -Be 'LaunchVerified'
        $result.Committed | Should -BeTrue
        $result.ProviderLoaded | Should -Be 'NotVerified'
        $result.Stages.IndexOf('ReleaseLock') | Should -BeLessThan $result.Stages.IndexOf('LaunchRequested')
        Should -Invoke Request-DesktopActivation -ModuleName CodexMode -Times 1 -Exactly
    }
    It 'preserves native GPT model and reasoning through GPT-custom-GPT' {
        (Invoke-CodexMode Init).State | Should -Be 'SwitchCommitted'
        [IO.File]::WriteAllText($script:Config, "model_provider = 'openai'`nmodel = 'native-test'`nmodel_reasoning_effort = 'high'`n[mcp_servers.extra]`ncommand = 'keep'")
        (Invoke-CodexMode GPT).State | Should -Be 'SwitchCommitted'
        [IO.File]::ReadAllText($script:Config) | Should -Match "model = 'native-test'"
        (Invoke-CodexMode DeepSeek).State | Should -Be 'SwitchCommitted'
        [IO.File]::ReadAllText($script:Config) | Should -Match 'model = "custom-test"'
        (Invoke-CodexMode GPT).State | Should -Be 'SwitchCommitted'
        $text = [IO.File]::ReadAllText($script:Config)
        $text | Should -Match "model = 'native-test'"
        $text | Should -Match "model_reasoning_effort = 'high'"
        $text | Should -Match '\[mcp_servers.extra\]'
        $before = $text
        [void](Invoke-CodexMode GPT)
        [IO.File]::ReadAllText($script:Config) | Should -BeExactly $before
    }
    It 'blocks Launch when Desktop is not installed before writing' {
        Mock Get-DesktopIdentity -ModuleName CodexMode {
            [pscustomobject]@{ State = 'NotInstalled'; Reliable = $true; Kind = $null; ActivationMethod = $null }
        }
        Mock Get-DesktopState -ModuleName CodexMode { [pscustomobject]@{ State = 'NotInstalled'; Reliable = $true } }
        (Invoke-CodexMode GPT -Launch -TasksStopped -NonInteractive).Code | Should -Be 'DesktopNotInstalled'
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher') | Should -BeFalse
    }
    It 'blocks non-interactive switching while Desktop runs even with task attestation' {
        Mock Get-DesktopState -ModuleName CodexMode { [pscustomobject]@{ State = 'Running'; Reliable = $true } }
        (Invoke-CodexMode GPT -Launch -WaitForExit -TasksStopped -NonInteractive).Code | Should -Be 'DesktopRunning'
        [IO.File]::ReadAllText($script:Config) | Should -BeExactly $script:Fixture
        Should -Invoke Request-DesktopActivation -ModuleName CodexMode -Times 0
    }
    It 'blocks configuration-only mutations when Desktop is running' {
        Mock Get-DesktopState -ModuleName CodexMode { [pscustomobject]@{ State = 'Running'; Reliable = $true } }
        (Invoke-CodexMode GPT -NonInteractive).Code | Should -Be 'DesktopRunning'
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher') | Should -BeFalse
    }
    It 'blocks an unreliable application identity' {
        Mock Get-DesktopIdentity -ModuleName CodexMode {
            [pscustomobject]@{ State = 'Unknown'; Reliable = $false; Kind = $null; ActivationMethod = $null }
        }
        Mock Get-DesktopState -ModuleName CodexMode { [pscustomobject]@{ State = 'Unknown'; Reliable = $false } }
        (Invoke-CodexMode GPT -NonInteractive).Code | Should -Be 'DesktopUnknown'
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher') | Should -BeFalse
    }
    It 'does not treat absence of a process as task-completion attestation' {
        (Invoke-CodexMode GPT -Launch -NonInteractive).Code | Should -Be 'TaskConfirmationRequired'
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher') | Should -BeFalse
    }
    It 'honors cancellation before creating files' {
        Mock Confirm-DesktopTasksStopped -ModuleName CodexMode { $false }
        (Invoke-CodexMode GPT -Launch).Code | Should -Be 'Cancelled'
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher') | Should -BeFalse
    }
    It 'waits only after confirmation and proceeds after observed normal exit' {
        $script:Exited = $false
        Mock Get-DesktopState -ModuleName CodexMode {
            [pscustomobject]@{ State = if ($script:Exited) { 'Ready' } else { 'Running' }; Reliable = $true }
        }
        Mock Wait-DesktopExit -ModuleName CodexMode { $script:Exited = $true; [pscustomobject]@{ State = 'Ready'; Reliable = $true } }
        $result = Invoke-CodexMode GPT -WaitForExit
        $result.State | Should -Be 'SwitchCommitted'
        $result.Stages | Should -Contain 'WaitingForExit'
        Should -Invoke Confirm-DesktopTasksStopped -ModuleName CodexMode -Times 1
    }
    It 'bounds the wait for a Desktop that does not exit' {
        Mock Get-DesktopState -ModuleName CodexMode { [pscustomobject]@{ State = 'Running'; Reliable = $true } }
        $result = Invoke-CodexMode GPT -WaitForExit -ExitTimeoutSeconds 1
        $result.Code | Should -Be 'ExitTimeout'
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher') | Should -BeFalse
    }
    It 'creates GPT config in an empty home' {
        Remove-Item -LiteralPath $script:Config
        (Invoke-CodexMode GPT -NonInteractive).Committed | Should -BeTrue
        [IO.File]::ReadAllText($script:Config) | Should -Match 'model_provider = "openai"'
    }
    It 'rejects a corrupt saved custom state without exposing its contents' {
        [void](Invoke-CodexMode GPT)
        $path = Join-Path $env:CODEX_HOME 'mode-switcher/deepseek-state.json'
        [IO.File]::WriteAllText($path, '{"private": "SYNTHETIC_PRIVATE_VALUE"')
        $result = Invoke-CodexMode DeepSeek
        $result.Code | Should -Be 'StateInvalid'
        ($result | ConvertTo-Json -Depth 8) | Should -Not -Match 'SYNTHETIC_PRIVATE_VALUE'
    }
    It 'rolls back newly written provider state when config write fails' {
        Mock Write-AtomicFile -ModuleName CodexMode -ParameterFilter { $Path.EndsWith('config.toml') } { throw 'Synthetic write failure' }
        $result = Invoke-CodexMode GPT
        $result.State | Should -Be 'Failed'
        $result.Committed | Should -BeFalse
        $result.Rollback | Should -Be 'Restored'
        [IO.File]::ReadAllText($script:Config) | Should -BeExactly $script:Fixture
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher/deepseek-state.json') | Should -BeFalse
    }
    It 'restores the previous state bytes on pre-commit failure' {
        [void](Invoke-CodexMode Init)
        $statePath = Join-Path $env:CODEX_HOME 'mode-switcher/deepseek-state.json'
        $before = [IO.File]::ReadAllText($statePath)
        Mock Write-AtomicFile -ModuleName CodexMode -ParameterFilter { $Path.EndsWith('config.toml') } { throw 'Synthetic write failure' }
        (Invoke-CodexMode GPT).Rollback | Should -Be 'Restored'
        [IO.File]::ReadAllText($statePath) | Should -BeExactly $before
    }
    It 'detects config changes while waiting/discovering before mutation' {
        Mock Get-DesktopState -ModuleName CodexMode {
            [IO.File]::WriteAllText((Join-Path $env:CODEX_HOME 'config.toml'), '# external edit')
            [pscustomobject]@{ State = 'Ready'; Reliable = $true }
        }
        (Invoke-CodexMode GPT).Code | Should -Be 'ConcurrentChange'
        [IO.File]::ReadAllText($script:Config) | Should -BeExactly '# external edit'
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher/deepseek-state.json') | Should -BeFalse
    }
    It 'does not overwrite a concurrent writer during rollback' {
        Mock Write-TransactionJournal -ModuleName CodexMode -ParameterFilter { $Journal.status -eq 'Committed' } {
            [IO.File]::WriteAllText((Join-Path $env:CODEX_HOME 'config.toml'), '# concurrent edit after apply')
            throw 'Synthetic commit failure'
        }
        $result = Invoke-CodexMode GPT
        $result.Rollback | Should -Be 'Conflict'
        [IO.File]::ReadAllText($script:Config) | Should -BeExactly '# concurrent edit after apply'
        (Invoke-CodexMode Diagnose).Diagnostics.RecoveryStatus | Should -Be 'Required'
        (Invoke-CodexMode GPT).Code | Should -Be 'RecoveryRequired'
    }
    It 'reports activation failure separately and retains the committed config' {
        Mock Request-DesktopActivation -ModuleName CodexMode { throw 'Synthetic activation failure' }
        $result = Invoke-CodexMode GPT -Launch -TasksStopped -NonInteractive
        $result.State | Should -Be 'Failed'
        $result.Committed | Should -BeTrue
        $result.Rollback | Should -Be 'NotRequired'
        [IO.File]::ReadAllText($script:Config) | Should -Match 'model_provider = "openai"'
    }
    It 'does not roll back external edits when activation fails' {
        Mock Request-DesktopActivation -ModuleName CodexMode {
            [IO.File]::WriteAllText((Join-Path $env:CODEX_HOME 'config.toml'), '# changed by external app')
            throw 'Synthetic activation failure'
        }
        $result = Invoke-CodexMode GPT -Launch -TasksStopped -NonInteractive
        $result.Committed | Should -BeTrue
        [IO.File]::ReadAllText($script:Config) | Should -BeExactly '# changed by external app'
    }
    It 'blocks activation when configuration changes after commit' {
        Mock Get-DesktopState -ModuleName CodexMode {
            $journals = @(Get-ChildItem (Join-Path $env:CODEX_HOME 'mode-switcher/transactions') -Filter '*.json' -ErrorAction SilentlyContinue)
            foreach ($file in $journals) {
                if ((Get-Content $file.FullName -Raw | ConvertFrom-Json).status -eq 'Committed') {
                    [IO.File]::WriteAllText((Join-Path $env:CODEX_HOME 'config.toml'), '# newer external selection')
                }
            }
            [pscustomobject]@{ State = 'Ready'; Reliable = $true }
        }
        $result = Invoke-CodexMode GPT -Launch -TasksStopped -NonInteractive
        $result.Code | Should -Be 'ConcurrentChange'
        $result.Committed | Should -BeTrue
        $result.LaunchRequested | Should -BeFalse
        [IO.File]::ReadAllText($script:Config) | Should -BeExactly '# newer external selection'
        Should -Invoke Request-DesktopActivation -ModuleName CodexMode -Times 0
    }
    It 'does not call an activation acknowledgement verified launch' {
        Mock Request-DesktopActivation -ModuleName CodexMode { 777 }
        $result = Invoke-CodexMode GPT -Launch -TasksStopped -LaunchTimeoutSeconds 1 -NonInteractive
        $result.Code | Should -Be 'LaunchTimeout'
        $result.Committed | Should -BeTrue
        $result.LaunchVerified | Should -BeFalse
    }
    It 'DryRun creates no state, backup, lock or launcher side effects' {
        $before = @(Get-ChildItem -LiteralPath $env:CODEX_HOME -Recurse -Force | ForEach-Object FullName)
        $result = Invoke-CodexMode GPT -Launch -DryRun -TasksStopped -NonInteractive
        $result.DryRun | Should -BeTrue
        $result.Plan.WriteRoles | Should -Contain 'config'
        (@(Get-ChildItem -LiteralPath $env:CODEX_HOME -Recurse -Force | ForEach-Object FullName) -join '|') | Should -BeExactly ($before -join '|')
        [IO.File]::ReadAllText($script:Config) | Should -BeExactly $script:Fixture
        Should -Invoke Request-DesktopActivation -ModuleName CodexMode -Times 0
        Should -Invoke Confirm-DesktopTasksStopped -ModuleName CodexMode -Times 0
    }
    It 'DryRun remains side effect free when the entire home is absent' {
        $env:CODEX_HOME = Join-Path $TestDrive 'absent-home'
        (Invoke-CodexMode GPT -DryRun).Code | Should -Be 'Preview'
        Test-Path $env:CODEX_HOME | Should -BeFalse
    }
    It 'keeps embedded provider credentials out of status, plans and transaction journals' {
        $text = $script:Fixture.Replace('name = "Synthetic provider"', 'name = "Synthetic provider"' + "`nexperimental_bearer_token = 'SYNTHETIC_PRIVATE_VALUE'")
        [IO.File]::WriteAllText($script:Config, $text)
        $result = Invoke-CodexMode GPT
        $result.Committed | Should -BeTrue
        $journal = Get-Content (Join-Path $env:CODEX_HOME "mode-switcher/transactions/$($result.TransactionId).json") -Raw
        (($result | ConvertTo-Json -Depth 8) + $journal) | Should -Not -Match 'SYNTHETIC_PRIVATE_VALUE'
    }
    It 'redacts suspicious model labels in diagnostics' {
        [IO.File]::WriteAllText($script:Config, 'model = "synthetic-secret-value"')
        (Invoke-CodexMode Status).Diagnostics.Model | Should -Be '(redacted)'
    }
    It 'blocks Desktop launch with an active profile override' {
        [IO.File]::WriteAllText($script:Config, "profile = 'other'`n" + $script:Fixture)
        (Invoke-CodexMode GPT -Launch -TasksStopped).Code | Should -Be 'OverrideConflict'
    }
    It 'blocks quoted root profile overrides as well' {
        [IO.File]::WriteAllText($script:Config, "'profile' = 'other'`n" + $script:Fixture)
        (Invoke-CodexMode GPT -Launch -TasksStopped).Code | Should -Be 'OverrideConflict'
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher') | Should -BeFalse
    }
    It 'uses conservative MSIX home binding for custom CODEX_HOME' {
        Mock Get-DesktopIdentity -ModuleName CodexMode {
            [pscustomobject]@{ State = 'Installed'; Reliable = $true; Kind = 'Msix'; ActivationMethod = 'IApplicationActivationManager' }
        }
        (Invoke-CodexMode GPT -Launch -TasksStopped).Code | Should -Be 'DesktopHomeUnverified'
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher') | Should -BeFalse
    }
    It 'refuses launch flags on non-switching commands' {
        (Invoke-CodexMode Init -Launch).Code | Should -Be 'ArgumentsInvalid'
    }
    It 'recovers a prepared transaction from validated backups' {
        $first = Invoke-CodexMode GPT
        $journalPath = Join-Path $env:CODEX_HOME "mode-switcher/transactions/$($first.TransactionId).json"
        $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        $journal.status = 'Prepared' # Simulated process loss before commit acknowledgement.
        [IO.File]::WriteAllText($journalPath, ($journal | ConvertTo-Json -Depth 8))
        $result = Invoke-CodexMode Recover -TransactionId $first.TransactionId -NonInteractive
        $result.Code | Should -Be 'Recovered'
        $result.Rollback | Should -Be 'Restored'
        [IO.File]::ReadAllText($script:Config) | Should -BeExactly $script:Fixture
        Test-Path (Join-Path $env:CODEX_HOME 'mode-switcher/deepseek-state.json') | Should -BeFalse
        (Invoke-CodexMode Diagnose).Diagnostics.RecoveryStatus | Should -Be 'Clear'
    }
    It 'refuses recovery across a committed transaction boundary' {
        $first = Invoke-CodexMode GPT
        (Invoke-CodexMode Recover -TransactionId $first.TransactionId).Code | Should -Be 'RecoveryInvalid'
        [IO.File]::ReadAllText($script:Config) | Should -Match 'model_provider = "openai"'
    }
    It 'refuses traversal in recovery transaction IDs' {
        (Invoke-CodexMode Recover -TransactionId '../private').Code | Should -Be 'RecoveryInvalid'
    }
    It 'rejects a tampered recovery backup before restoring anything' {
        $first = Invoke-CodexMode GPT
        $journalPath = Join-Path $env:CODEX_HOME "mode-switcher/transactions/$($first.TransactionId).json"
        $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        $journal.status = 'Prepared'
        [IO.File]::WriteAllText($journalPath, ($journal | ConvertTo-Json -Depth 8))
        [IO.File]::WriteAllText((Join-Path $env:CODEX_HOME "mode-switcher/backups/config.$($first.TransactionId).toml"), '# tampered')
        (Invoke-CodexMode Recover -TransactionId $first.TransactionId).Code | Should -Be 'RecoveryInvalid'
        [IO.File]::ReadAllText($script:Config) | Should -Match 'model_provider = "openai"'
    }
    It 'does not remove case-distinct unrelated TOML keys' {
        [IO.File]::WriteAllText($script:Config, "MODEL = 'case-sensitive-unrelated'`n" + $script:Fixture)
        (Invoke-CodexMode GPT).Committed | Should -BeTrue
        [IO.File]::ReadAllText($script:Config) | Should -Match "MODEL = 'case-sensitive-unrelated'"
    }
}

Describe 'Explicit profile shortcuts' {
    BeforeEach { $script:ProfilePath = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '/profile.ps1') }
    It 'previews install without creating a profile directory' {
        $result = Invoke-DesktopShortcut -ProfilePath $script:ProfilePath -DryRun
        $result.Preview | Should -Match 'GPT -Launch'
        Test-Path (Split-Path $script:ProfilePath) | Should -BeFalse
    }
    It 'installs idempotently and uninstalls without removing unrelated functions' {
        [IO.Directory]::CreateDirectory((Split-Path $script:ProfilePath)) | Out-Null
        [IO.File]::WriteAllText($script:ProfilePath, 'function existing-command { "keep" }')
        $install = Invoke-DesktopShortcut -ProfilePath $script:ProfilePath
        Test-Path $install.BackupPath | Should -BeTrue
        (Invoke-DesktopShortcut -ProfilePath $script:ProfilePath).Changed | Should -BeFalse
        [void](Invoke-DesktopShortcut -Action Uninstall -ProfilePath $script:ProfilePath)
        $text = [IO.File]::ReadAllText($script:ProfilePath)
        $text | Should -Match 'function existing-command'
        $text | Should -Not -Match 'function global:cdx'
    }
    It 'refuses existing user shortcut functions' {
        [IO.Directory]::CreateDirectory((Split-Path $script:ProfilePath)) | Out-Null
        $original = 'function cdx-gpt { "mine" }'
        [IO.File]::WriteAllText($script:ProfilePath, $original)
        { Invoke-DesktopShortcut -ProfilePath $script:ProfilePath } | Should -Throw '*conflict*'
        [IO.File]::ReadAllText($script:ProfilePath) | Should -BeExactly $original
    }
    It 'refuses edited owned blocks instead of overwriting user changes' {
        [void](Invoke-DesktopShortcut -ProfilePath $script:ProfilePath)
        $edited = [IO.File]::ReadAllText($script:ProfilePath).Replace('GPT -Launch', 'GPT -Launch -TasksStopped')
        [IO.File]::WriteAllText($script:ProfilePath, $edited)
        { Invoke-DesktopShortcut -Action Uninstall -ProfilePath $script:ProfilePath } | Should -Throw '*edited*'
        [IO.File]::ReadAllText($script:ProfilePath) | Should -BeExactly $edited
    }
}
