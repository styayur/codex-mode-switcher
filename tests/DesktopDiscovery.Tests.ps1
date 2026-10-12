BeforeAll { Import-Module (Join-Path (Split-Path $PSScriptRoot) 'src/CodexMode.psm1') }

Describe 'Windows identity discovery with synthetic inventory' {
    It 'resolves a registered MSIX AUMID through its manifest executable' {
        InModuleScope CodexMode {
            Mock Get-WindowsDesktopInventory {
                [pscustomobject]@{ Complete = $true; Registry = @(); Packages = @(
                    [pscustomobject]@{ Aumid = 'OpenAI.Codex_test!App'; PackageFamily = 'OpenAI.Codex_test'
                        InstallLocation = 'C:\synthetic\package'; Executable = 'app/ChatGPT.exe'; Version = 'test' }
                ) }
            }
            Mock Test-WindowsGuiExecutable { $true }
            $identity = Get-DesktopIdentity
            $identity.State | Should -Be 'Installed'
            $identity.Kind | Should -Be 'Msix'
            $identity.ExecutablePath | Should -Be 'C:\synthetic\package\app\ChatGPT.exe'
            $identity.ActivationMethod | Should -Be 'IApplicationActivationManager'
        }
    }
    It 'reports Unknown for incomplete inventory instead of NotInstalled' {
        InModuleScope CodexMode {
            Mock Get-WindowsDesktopInventory { [pscustomobject]@{ Complete = $false; Packages = @(); Registry = @() } }
            (Get-DesktopIdentity).State | Should -Be 'Unknown'
        }
    }
    It 'reports no supported installation only after a complete empty inventory' {
        InModuleScope CodexMode {
            Mock Get-WindowsDesktopInventory { [pscustomobject]@{ Complete = $true; Packages = @(); Registry = @() } }
            (Get-DesktopIdentity).State | Should -Be 'NotInstalled'
        }
    }
    It 'rejects a manifest executable escaping the registered package directory' {
        InModuleScope CodexMode {
            Mock Get-WindowsDesktopInventory {
                [pscustomobject]@{ Complete = $true; Registry = @(); Packages = @(
                    [pscustomobject]@{ Aumid = 'test!App'; PackageFamily = 'test'; InstallLocation = 'C:\synthetic\package'
                        Executable = '../../untrusted.exe'; Version = 'test' }) }
            }
            Mock Test-WindowsGuiExecutable { $true }
            (Get-DesktopIdentity).State | Should -Be 'Unknown'
        }
    }
    It 'refuses arbitrary or shell-like AppUserModelIDs' {
        InModuleScope CodexMode {
            Mock Get-WindowsDesktopInventory { [pscustomobject]@{ Complete = $true; Packages = @(); Registry = @() } }
            (Get-DesktopIdentity -DesktopAppId 'test!App;calc').Reason | Should -Be 'InvalidAppUserModelId'
            (Get-DesktopIdentity -DesktopAppId 'other!App').Reason | Should -Be 'RequestedIdentityNotRegistered'
        }
    }
    It 'supports an explicitly validated signed Win32 GUI path without assuming an install folder' {
        InModuleScope CodexMode {
            Mock Get-WindowsDesktopInventory { [pscustomobject]@{ Complete = $true; Packages = @(); Registry = @() } }
            Mock Test-DesktopExecutable { $true }
            $identity = Get-DesktopIdentity -DesktopPath 'C:\synthetic\custom-folder\Desktop.exe'
            $identity.Kind | Should -Be 'Win32'
            $identity.ActivationMethod | Should -Be 'CreateProcess'
        }
    }
    It 'rejects an unverified CLI or arbitrary executable path' {
        InModuleScope CodexMode {
            Mock Get-WindowsDesktopInventory { [pscustomobject]@{ Complete = $true; Packages = @(); Registry = @() } }
            Mock Test-DesktopExecutable { $false }
            (Get-DesktopIdentity -DesktopPath 'C:\synthetic\codex.exe').Reason | Should -Be 'UnverifiedDesktopExecutable'
        }
    }
    It 'does not infer Desktop is running from a separate codex CLI process' {
        InModuleScope CodexMode {
            $identity = Get-DesktopIdentityRecord 'Installed' 'Synthetic'
            $identity.AllExecutablePaths = @('C:\synthetic\package\app\ChatGPT.exe')
            Mock Get-DesktopProcessSnapshot {
                [pscustomobject]@{ Complete = $true; Processes = @(
                    [pscustomobject]@{ ProcessId = 7; Name = 'codex.exe'; ExecutablePath = 'C:\synthetic\cli\codex.exe' }) }
            }
            (Get-DesktopState $identity).State | Should -Be 'Ready'
        }
    }
    It 'recognizes Desktop running under ChatGPT.exe by exact registered path' {
        InModuleScope CodexMode {
            $identity = Get-DesktopIdentityRecord 'Installed' 'Synthetic'
            $identity.AllExecutablePaths = @('C:\synthetic\package\app\ChatGPT.exe')
            Mock Get-DesktopProcessSnapshot {
                [pscustomobject]@{ Complete = $true; Processes = @(
                    [pscustomobject]@{ ProcessId = 7; Name = 'ChatGPT.exe'; ExecutablePath = 'C:\synthetic\package\app\ChatGPT.exe' }) }
            }
            $result = Get-DesktopState $identity
            $result.State | Should -Be 'Running'
            $result.ProcessIds | Should -Contain 7
            $result.TaskActivity | Should -Be 'Unknown'
        }
    }
    It 'reports Unknown when a plausible process has an unreadable executable path' {
        InModuleScope CodexMode {
            $identity = Get-DesktopIdentityRecord 'Installed' 'Synthetic'
            $identity.AllExecutablePaths = @('C:\synthetic\package\app\ChatGPT.exe')
            Mock Get-DesktopProcessSnapshot {
                [pscustomobject]@{ Complete = $true; Processes = @(
                    [pscustomobject]@{ ProcessId = 7; Name = 'ChatGPT.exe'; ExecutablePath = $null }) }
            }
            (Get-DesktopState $identity).State | Should -Be 'Unknown'
        }
    }
    It 'reports Unknown if process enumeration fails' {
        InModuleScope CodexMode {
            $identity = Get-DesktopIdentityRecord 'Installed' 'Synthetic'
            Mock Get-DesktopProcessSnapshot { [pscustomobject]@{ Complete = $false; Processes = @() } }
            (Get-DesktopState $identity).State | Should -Be 'Unknown'
        }
    }
    It 'compiles the documented Windows activation binding without activating an application' {
        $source = Join-Path (Split-Path $PSScriptRoot) 'src/WindowsActivation.cs'
        if (-not ('CodexMode.WindowsActivation' -as [type])) { Add-Type -Path $source }
        ('CodexMode.WindowsActivation' -as [type]) | Should -Not -BeNullOrEmpty
    }
}
