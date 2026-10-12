BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot) 'src/CodexMode.psm1')
}

Describe 'Isolated Windows integrations' {
    BeforeEach {
        $script:Area=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:Context=[pscustomobject]@{
            State=(Join-Path $script:Area 'state'); Ledger=(Join-Path $script:Area 'state/ownership.json')
            Lock=(Join-Path $script:Area 'state/.lock'); Backups=(Join-Path $script:Area 'state/backups')
            Terminal=(Join-Path $script:Area 'Terminal/Fragments/owner/profiles.json')
            Programs=(Join-Path $script:Area 'Programs/Owner'); Entry=(Join-Path $script:Area 'tool with spaces/codex-mode.ps1')
            PowerShell=(Join-Path $PSHOME 'pwsh.exe')
        }
        Mock Get-IntegrationContext -ModuleName CodexMode { $script:Context }
        Mock Test-TerminalAvailable -ModuleName CodexMode { $true }
        Mock Request-WindowsNotification -ModuleName CodexMode { 'Requested' }
    }
    It 'lists disabled integrations without creating directories' {
        $list=@(Get-CodexIntegration)
        $list.Count | Should -Be 3
        @($list | Where-Object Status -NE 'NotInstalled').Count | Should -Be 0
        Test-Path $script:Area | Should -BeFalse
    }
    It 'uninstalls an absent integration without creating state' {
        (codex-mode integration uninstall-all -Apply).State | Should -Be 'Unchanged'
        Test-Path $script:Area | Should -BeFalse
    }
    It 'previews installation by default, including with explicit DryRun and Apply' {
        (codex-mode install terminal).State | Should -Be 'Preview'
        (codex-mode install startmenu -Apply -DryRun).State | Should -Be 'Preview'
        Test-Path $script:Area | Should -BeFalse
    }
    It 'reports missing Terminal without writing anything' {
        Mock Test-TerminalAvailable -ModuleName CodexMode { $false }
        (codex-mode install terminal -Apply).State | Should -Be 'Unavailable'
        Test-Path $script:Area | Should -BeFalse
    }
    It 'installs three unique Terminal profiles without reading or editing settings.json' {
        [IO.Directory]::CreateDirectory($script:Area) | Out-Null
        $settings=Join-Path $script:Area 'settings.json'
        [IO.File]::WriteAllText($settings,'// user JSONC must remain byte-identical')
        $before=(Get-FileHash $settings).Hash
        (codex-mode install terminal -Apply).State | Should -Be 'Applied'
        $fragment=Get-Content $script:Context.Terminal -Raw | ConvertFrom-Json
        $fragment.profiles.Count | Should -Be 3
        @($fragment.profiles.guid | Sort-Object -Unique).Count | Should -Be 3
        $fragment.profiles.name | Should -Contain 'Codex GPT'
        $fragment.profiles[0].commandline | Should -Match '\-Launch -WaitForExit'
        $fragment.profiles[2].commandline | Should -Not -Match '\-Launch'
        (Get-FileHash $settings).Hash | Should -Be $before
        (codex-mode integration list | Where-Object Kind -EQ terminal).CanUninstall | Should -BeTrue
    }
    It 'does not rewrite an installed Terminal fragment or ledger on repetition' {
        [void](codex-mode install terminal -Apply)
        $before=(Get-Item $script:Context.Terminal).LastWriteTimeUtc
        $ledger=(Get-Item $script:Context.Ledger).LastWriteTimeUtc
        (codex-mode install terminal -Apply).State | Should -Be 'Unchanged'
        (Get-Item $script:Context.Terminal).LastWriteTimeUtc | Should -Be $before
        (Get-Item $script:Context.Ledger).LastWriteTimeUtc | Should -Be $ledger
    }
    It 'previews uninstall then removes only its fragment with a retained backup' {
        [void](codex-mode install terminal -Apply)
        $hash=(Get-FileHash $script:Context.Terminal).Hash
        (codex-mode uninstall terminal).State | Should -Be 'Preview'
        Test-Path $script:Context.Terminal | Should -BeTrue
        [void](codex-mode uninstall terminal -Apply)
        Test-Path $script:Context.Terminal | Should -BeFalse
        $backup=@(Get-ChildItem $script:Context.Backups -Filter 'terminal.*.bak')
        (Get-FileHash $backup[0].FullName).Hash | Should -Be $hash
        (codex-mode uninstall terminal -Apply).Changed | Should -BeFalse
    }
    It 'never adopts or overwrites an unowned file even when it looks like a fragment' {
        [IO.Directory]::CreateDirectory((Split-Path $script:Context.Terminal)) | Out-Null
        [IO.File]::WriteAllText($script:Context.Terminal,'{"profiles":[]}')
        { codex-mode install terminal -Apply } | Should -Throw '*unowned*'
        [void](codex-mode integration uninstall-all -Apply)
        [IO.File]::ReadAllText($script:Context.Terminal) | Should -BeExactly '{"profiles":[]}'
    }
    It 'preserves user-modified owned files and reports non-uninstallable conflict' {
        [void](codex-mode install terminal -Apply)
        [IO.File]::AppendAllText($script:Context.Terminal,' ')
        $before=(Get-FileHash $script:Context.Terminal).Hash
        $status=Get-CodexIntegration | Where-Object Kind -EQ terminal
        $status.Status | Should -Be 'Conflict'
        $status.CanUninstall | Should -BeFalse
        { codex-mode integration uninstall-all -Apply } | Should -Throw '*modified*'
        (Get-FileHash $script:Context.Terminal).Hash | Should -Be $before
    }
    It 'repairs an absent owned fragment without touching unrelated files' {
        [void](codex-mode install terminal -Apply)
        Remove-Item -LiteralPath $script:Context.Terminal
        (Get-CodexIntegration | Where-Object Kind -EQ terminal).Status | Should -Be 'Partial'
        [void](codex-mode install terminal -Apply)
        (Get-CodexIntegration | Where-Object Kind -EQ terminal).Status | Should -Be 'Installed'
    }
    It 'creates and removes actual native shortcuts only inside TestDrive' {
        [void](codex-mode install startmenu -Apply)
        $links=@(Get-ChildItem $script:Context.Programs -Filter '*.lnk')
        $links.Count | Should -Be 3
        [CodexMode.NativeShortcut]::GetAppId($links[0].FullName) | Should -BeExactly 'styayur.CodexModeSwitcher'
        $shell=New-Object -ComObject WScript.Shell
        try {
            $link=$shell.CreateShortcut((Join-Path $script:Context.Programs 'Codex GPT.lnk'))
            try {
                $link.TargetPath | Should -Be $script:Context.PowerShell
                $link.Arguments | Should -Match '-Launch -WaitForExit'
                $link.Arguments | Should -Match 'tool with spaces'
            } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($link) }
        } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
        (codex-mode install startmenu -Apply).Changed | Should -BeFalse
        [void](codex-mode uninstall startmenu -Apply)
        @(Get-ChildItem $script:Context.Programs -Filter '*.lnk').Count | Should -Be 0
    }
    It 'uninstall-all preserves files not in the ownership ledger' {
        [void](codex-mode install startmenu -Apply)
        [void](codex-mode install terminal -Apply)
        $other=Join-Path $script:Context.Programs 'my-notes.txt'
        [IO.File]::WriteAllText($other,'keep')
        [void](codex-mode integration uninstall-all -Apply)
        [IO.File]::ReadAllText($other) | Should -Be 'keep'
        @((Get-CodexIntegration) | Where-Object Status -NE NotInstalled).Count | Should -Be 0
    }
    It 'rejects corrupt ownership data before deleting files' {
        [void](codex-mode install terminal -Apply)
        [IO.File]::WriteAllText($script:Context.Ledger,'{ malformed')
        { codex-mode integration uninstall-all -Apply } | Should -Throw '*ownership data is invalid*'
        Test-Path $script:Context.Terminal | Should -BeTrue
    }
    It 'rejects injected ownership IDs instead of treating them as paths' {
        [void](codex-mode install terminal -Apply)
        $ledger=Get-Content $script:Context.Ledger -Raw | ConvertFrom-Json
        $ledger.entries[0].id='../unrelated'
        [IO.File]::WriteAllText($script:Context.Ledger,($ledger | ConvertTo-Json -Depth 6))
        { codex-mode integration uninstall-all -Apply } | Should -Throw '*ownership data is invalid*'
        Test-Path $script:Context.Terminal | Should -BeTrue
    }
    It 'rolls back a created fragment when ownership persistence fails' {
        Mock Write-IntegrationLedger -ModuleName CodexMode { throw 'synthetic failure' }
        { codex-mode install terminal -Apply } | Should -Throw '*Integration update stopped*'
        Test-Path $script:Context.Terminal | Should -BeFalse
    }
    It 'restores removed bytes when uninstall ownership persistence fails' {
        [void](codex-mode install terminal -Apply)
        $before=(Get-FileHash $script:Context.Terminal).Hash
        Mock Write-IntegrationLedger -ModuleName CodexMode { throw 'synthetic failure' }
        { codex-mode uninstall terminal -Apply } | Should -Throw '*Integration update stopped*'
        (Get-FileHash $script:Context.Terminal).Hash | Should -Be $before
        (Get-CodexIntegration | Where-Object Kind -EQ terminal).Status | Should -Be 'Installed'
    }
    It 'does not erase a newer external file during install rollback' {
        Mock Write-IntegrationLedger -ModuleName CodexMode {
            [IO.File]::WriteAllText($script:Context.Terminal,'external change')
            throw 'synthetic failure'
        }
        { codex-mode install terminal -Apply } | Should -Throw '*Integration update stopped*'
        [IO.File]::ReadAllText($script:Context.Terminal) | Should -Be 'external change'
    }
    It 'restores ownership when persistence writes successfully then loses acknowledgement' {
        [void](codex-mode install terminal -Apply)
        $before=(Get-FileHash $script:Context.Ledger).Hash
        Mock Write-IntegrationLedger -ModuleName CodexMode {
            Write-AtomicFile $Context.Ledger ([Text.UTF8Encoding]::new($false).GetBytes(($Ledger | ConvertTo-Json -Depth 6)))
            throw 'synthetic acknowledgement failure'
        }
        { codex-mode uninstall terminal -Apply } | Should -Throw '*Integration update stopped*'
        (Get-FileHash $script:Context.Ledger).Hash | Should -Be $before
        (Get-CodexIntegration | Where-Object Kind -EQ terminal).Status | Should -Be 'Installed'
    }
    It 'configures notifications explicitly and removes their owned identity shortcut' {
        [void](codex-mode install notifications -Apply)
        (Get-CodexIntegration | Where-Object Kind -EQ notifications).Status | Should -Be 'Installed'
        @(Get-ChildItem $script:Context.Programs -Filter '*.lnk').Count | Should -Be 1
        [void](codex-mode uninstall notifications -Apply)
        (Get-CodexIntegration | Where-Object Kind -EQ notifications).Status | Should -Be 'NotInstalled'
    }
    It 'does not send notifications without explicit configuration' {
        InModuleScope CodexMode {
            Send-ModeNotification ([pscustomobject]@{State='Failed';Committed=$false;Code='DesktopRunning'}) | Should -Be 'NotConfigured'
        }
        Should -Invoke Request-WindowsNotification -ModuleName CodexMode -Times 0
    }
    It 'never forwards sensitive error text to notifications' {
        [void](codex-mode install notifications -Apply)
        InModuleScope CodexMode {
            Send-ModeNotification ([pscustomobject]@{State='Failed';Committed=$false;Code='DesktopRunning';Message='SYNTHETIC_PRIVATE_VALUE'}) | Should -Be 'Requested'
        }
        Should -Invoke Request-WindowsNotification -ModuleName CodexMode -Times 1 -ParameterFilter { $Outcome -eq 'DesktopRunning' }
    }
    It 'isolates notification exceptions from the core result' {
        [void](codex-mode install notifications -Apply)
        Mock Invoke-CodexMode -ModuleName CodexMode { [pscustomobject]@{State='SwitchCommitted';Committed=$true;Action='GPT'} }
        Mock Request-WindowsNotification -ModuleName CodexMode { throw 'synthetic notification failure' }
        (Start-CodexMode GPT -ConfigurationOnly -Notify).State | Should -Be 'SwitchCommitted'
    }
    It 'does not send notifications for DryRun' {
        Mock Invoke-CodexMode -ModuleName CodexMode { [pscustomobject]@{State='Ready';Committed=$false;Action='GPT'} }
        Mock Send-ModeNotification -ModuleName CodexMode { throw 'must not call' }
        [void](Start-CodexMode GPT -Notify -DryRun)
        Should -Invoke Send-ModeNotification -ModuleName CodexMode -Times 0
    }
}

Describe 'Public PowerShell module API' {
    BeforeEach { Import-Module (Join-Path (Split-Path $PSScriptRoot) 'src/CodexMode.psm1') }
    It 'validates the named manifest and imports by name from an isolated module path' {
        $root=Split-Path $PSScriptRoot
        (Test-ModuleManifest (Join-Path $root 'CodexModeSwitcher.psd1')).Version | Should -Be '0.2.1'
        $destination=Join-Path $TestDrive 'modules/CodexModeSwitcher'
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        Copy-Item (Join-Path $root 'CodexModeSwitcher.psd1') $destination
        Copy-Item (Join-Path $root 'src') $destination -Recurse
        $previous=$env:PSModulePath
        try {
            $env:PSModulePath=(Split-Path $destination) + [IO.Path]::PathSeparator + $previous
            $module=Import-Module CodexModeSwitcher -PassThru
            $module.ExportedFunctions.Keys | Should -Contain 'Start-CodexMode'
            $module.ExportedFunctions.Keys | Should -Contain 'Get-CodexStatus'
            $module.ExportedFunctions.Keys | Should -Contain 'Test-CodexEnvironment'
            $module.ExportedAliases.Keys | Should -Contain 'codex-mode'
        } finally { Remove-Module CodexModeSwitcher; $env:PSModulePath=$previous }
    }
    It 'routes Start to Desktop launch, with explicit configuration-only opt out' {
        Mock Invoke-CodexMode -ModuleName CodexMode { [pscustomobject]@{Mode=$Mode;Launch=[bool]$Launch} }
        (Start-CodexMode GPT).Launch | Should -BeTrue
        (Start-CodexMode DeepSeek -ConfigurationOnly).Launch | Should -BeFalse
        (Start-CodexMode).Mode | Should -Be 'GPT'
    }
    It 'routes status and environment checks to read-only controller modes' {
        Mock Invoke-CodexMode -ModuleName CodexMode { $Mode }
        Get-CodexStatus | Should -Be 'Status'
        Test-CodexEnvironment | Should -Be 'Diagnose'
    }
}
