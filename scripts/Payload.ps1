#requires -Version 7.4
Set-StrictMode -Version Latest

$script:CodexModeOwner = 'styayur.codex-mode-switcher'
$script:CodexModeProduct = 'CodexModeSwitcher'
$script:CodexModeRequiredFiles = @(
    'codex-mode.ps1'
    'codex-mode.cmd'
    'CodexModeSwitcher.psd1'
    'scripts/Invoke-Command.ps1'
    'scripts/Install-CodexMode.ps1'
    'scripts/Payload.ps1'
)
$script:CodexModeRequiredSourceFiles = @(
    'CodexMode.psm1'
    'Config.ps1'
    'Controller.ps1'
    'DesktopDiscovery.ps1'
    'DesktopLifecycle.ps1'
    'Diagnostics.ps1'
    'Get-WindowsInventory.ps1'
    'Integration.ps1'
    'NativeShortcut.cs'
    'Notification.ps1'
    'Public.ps1'
    'Shortcut.ps1'
    'Show-Notification.ps1'
    'State.ps1'
    'Transaction.ps1'
    'WindowsActivation.cs'
)
$script:CodexModeOptionalFiles = @(
    'install.ps1'
    'README.md'
    'CHANGELOG.md'
    'LICENSE'
    'SECURITY.md'
    'release-manifest.json'
    'docs/USAGE.md'
    'docs/TROUBLESHOOTING.md'
    'docs/WINDOWS-INTEGRATION.md'
    'docs/VALIDATION.md'
    'docs/DESKTOP-VALIDATION.md'
    'docs/README.zh-CN.md'
)

function ConvertTo-CodexModeRelativePath {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
    $rootFull = [IO.Path]::GetFullPath($Root)
    $pathFull = [IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the payload root: $Path"
    }
    return [IO.Path]::GetRelativePath($rootFull, $pathFull).Replace('\', '/')
}

function Get-CodexModePayloadFile {
    param([Parameter(Mandatory)][string]$Root)
    $rootFull = [IO.Path]::GetFullPath($Root)
    if (-not [IO.Directory]::Exists($rootFull)) { throw "Payload root does not exist: $rootFull" }
    $files = [Collections.Generic.List[string]]::new()
    foreach ($relative in @($script:CodexModeRequiredFiles + $script:CodexModeOptionalFiles)) {
        $full = Join-Path $rootFull $relative
        if (Test-Path -LiteralPath $full -PathType Leaf) { $files.Add($relative.Replace('\', '/')) }
    }
    $sourceDirectory = Join-Path $rootFull 'src'
    if (Test-Path -LiteralPath $sourceDirectory -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse) {
            $files.Add((ConvertTo-CodexModeRelativePath -Root $rootFull -Path $file.FullName))
        }
    }
    return @($files | Sort-Object -Unique)
}

function Assert-CodexModePayload {
    param([Parameter(Mandatory)][string]$Root)
    $rootFull = [IO.Path]::GetFullPath($Root)
    $missing = [Collections.Generic.List[string]]::new()
    foreach ($relative in $script:CodexModeRequiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $rootFull $relative) -PathType Leaf)) { $missing.Add($relative) }
    }
    foreach ($relative in $script:CodexModeRequiredSourceFiles) {
        $path = Join-Path (Join-Path $rootFull 'src') $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $missing.Add("src/$relative") }
    }
    if ($missing.Count) {
        throw ("Incomplete Codex Mode Switcher distribution. Missing: " + ($missing -join ', ') +
            ". Download the complete CodexModeSwitcher-*.zip release archive; do not copy only codex-mode.ps1.")
    }
    $manifestPath = Join-Path $rootFull 'CodexModeSwitcher.psd1'
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    if (-not $manifest.ModuleVersion) { throw 'CodexModeSwitcher.psd1 has no ModuleVersion.' }
    [pscustomobject]@{
        Root = $rootFull
        Version = [string]$manifest.ModuleVersion
        Files = @(Get-CodexModePayloadFile -Root $rootFull)
    }
}

function Get-CodexModeFileHash {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-CodexModePayloadManifest {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Version
    )
    $rootFull = [IO.Path]::GetFullPath($Root)
    $entries = foreach ($relative in @(Get-CodexModePayloadFile -Root $rootFull)) {
        $path = Join-Path $rootFull $relative
        [ordered]@{
            path = $relative
            sha256 = Get-CodexModeFileHash -Path $path
            size = ([IO.FileInfo]::new($path)).Length
        }
    }
    return [ordered]@{
        schema_version = 1
        owner = $script:CodexModeOwner
        product = $script:CodexModeProduct
        version = $Version
        generated_at = [DateTime]::UtcNow.ToString('o')
        entry = 'codex-mode.ps1'
        module = 'src/CodexMode.psm1'
        files = @($entries)
    }
}
