@{
    RootModule = 'src/CodexMode.psm1'
    ModuleVersion = '0.2.1'
    GUID = 'db72bd9c-e7a8-44be-9a4f-58c16d53e047'
    Author = 'styayur'
    Copyright = '(c) styayur. MIT License.'
    Description = 'Safe Windows Codex Desktop provider selection and optional native integrations.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Start-CodexMode', 'Get-CodexStatus', 'Test-CodexEnvironment',
        'Invoke-CodexCommand', 'Get-CodexIntegration', 'Invoke-CodexIntegration',
        'Invoke-CodexMode', 'Invoke-DesktopShortcut')
    AliasesToExport = @('codex-mode')
    CmdletsToExport = @()
    VariablesToExport = @()
    PrivateData = @{ PSData = @{
        Tags = @('Codex', 'Windows', 'PowerShell', 'Desktop')
        LicenseUri = 'https://github.com/styayur/codex-mode-switcher/blob/main/LICENSE'
        ProjectUri = 'https://github.com/styayur/codex-mode-switcher'
    } }
}
