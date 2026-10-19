#requires -Version 7.4
Set-StrictMode -Version Latest
$script:ModeVersion = '0.2.2'
$script:ManagedComment = '# Managed provider/auth selection: codex-mode.ps1'
$script:NativeKeys = @('model', 'model_reasoning_effort', 'model_reasoning_summary', 'model_verbosity')
$script:SwitchKeys = @('model', 'model_provider', 'model_catalog_json', 'openai_base_url',
    'chatgpt_base_url', 'forced_login_method', 'model_reasoning_effort', 'model_reasoning_summary', 'model_verbosity')
foreach ($file in @('Config', 'State', 'Transaction', 'DesktopDiscovery', 'DesktopLifecycle', 'Diagnostics', 'Controller', 'Shortcut', 'Integration', 'Notification', 'Public')) {
    . (Join-Path $PSScriptRoot "$file.ps1")
}
Set-Alias -Name codex-mode -Value Invoke-CodexCommand
Export-ModuleMember -Function Invoke-CodexMode, Invoke-DesktopShortcut, Start-CodexMode, Get-CodexStatus, Test-CodexEnvironment, Invoke-CodexCommand, Get-CodexIntegration, Invoke-CodexIntegration -Alias codex-mode
