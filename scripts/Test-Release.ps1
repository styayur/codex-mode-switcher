#requires -Version 7.4
<#
.SYNOPSIS
Verify that a release archive contains the complete installable distribution.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Archive,
    [string]$ChecksumFile,
    [string]$ManifestFile,
    [switch]$SkipModuleCheck,
    [switch]$Json,
    [switch]$PassThru
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$archivePath = [IO.Path]::GetFullPath($Archive)
if (-not [IO.File]::Exists($archivePath)) { throw "Release archive does not exist: $archivePath" }
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-mode-release-check-' + [guid]::NewGuid().ToString('N'))
$extractRoot = Join-Path $temporaryRoot 'extract'
try {
    [void][IO.Directory]::CreateDirectory($extractRoot)
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
    $roots = @(Get-ChildItem -LiteralPath $extractRoot -Directory)
    if ($roots.Count -ne 1 -or $roots[0].Name -ne 'CodexModeSwitcher') {
        throw 'Release archive must contain exactly one CodexModeSwitcher/ root directory.'
    }
    $payloadRoot = $roots[0].FullName
    $payloadHelper = Join-Path $payloadRoot 'scripts/Payload.ps1'
    if (-not [IO.File]::Exists($payloadHelper)) { throw 'Release archive is missing scripts/Payload.ps1.' }
    . $payloadHelper
    $payload = Assert-CodexModePayload -Root $payloadRoot

    $manifestPath = if ($ManifestFile) { [IO.Path]::GetFullPath($ManifestFile) } else { Join-Path $payloadRoot 'release-manifest.json' }
    if (-not [IO.File]::Exists($manifestPath)) { throw "Release manifest is missing: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($manifest.owner -cne $script:CodexModeOwner -or $manifest.schema_version -ne 1) {
        throw 'Release manifest owner or schema is invalid.'
    }
    if ([string]$manifest.version -ne [string]$payload.Version) {
        throw "Release manifest version $($manifest.version) does not match module version $($payload.Version)."
    }
    $listed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($manifest.files)) {
        $relative = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
            $relative -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Release manifest contains an unsafe path: $relative"
        }
        [void]$listed.Add($relative)
        $path = Join-Path $payloadRoot $relative
        if (-not [IO.File]::Exists($path)) { throw "Release manifest lists a missing file: $relative" }
        if ((Get-CodexModeFileHash -Path $path) -cne [string]$entry.sha256) {
            throw "Release payload hash mismatch: $relative"
        }
        if (([IO.FileInfo]::new($path)).Length -ne [long]$entry.size) {
            throw "Release payload size mismatch: $relative"
        }
    }
    foreach ($required in @($script:CodexModeRequiredFiles + @('src/CodexMode.psm1'))) {
        if (-not $listed.Contains($required)) { throw "Release manifest does not cover required file: $required" }
    }

    $forbidden = @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -File -Force | Where-Object {
        $_.FullName -match '[\\/](\.git|local-originals|sessions|archived_sessions|mode-switcher)[\\/]' -or
        $_.Name -in @('auth.json', 'config.toml', 'deepseek-state.json', 'gpt-state.json', 'install.json') -or
        $_.Name -match '\.(key|pem|pfx|db|sqlite3?)$'
    })
    if ($forbidden.Count) {
        throw ("Release archive contains prohibited local state or credential files: " + (($forbidden | ForEach-Object { [IO.Path]::GetRelativePath($payloadRoot, $_.FullName) }) -join ', '))
    }

    if (-not $SkipModuleCheck) {
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if ([string]::IsNullOrWhiteSpace($pwsh)) {
            $candidate = Join-Path $PSHOME 'pwsh.exe'
            if (-not [IO.File]::Exists($candidate)) { $candidate = Join-Path $PSHOME 'pwsh' }
            $pwsh = $candidate
        }
        $moduleManifest = Join-Path $payloadRoot 'CodexModeSwitcher.psd1'
        $escaped = $moduleManifest.Replace("'", "''")
        $check = "`$ErrorActionPreference = 'Stop'; Import-Module '$escaped' -Force -ErrorAction Stop; if (-not (Get-Command Invoke-CodexCommand -Module CodexModeSwitcher -ErrorAction Stop)) { throw 'Invoke-CodexCommand missing' }"
        $null = & $pwsh -NoLogo -NoProfile -NonInteractive -Command $check 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Release module import check failed.' }
    }

    if ($ChecksumFile) {
        $checksumPath = [IO.Path]::GetFullPath($ChecksumFile)
        if (-not [IO.File]::Exists($checksumPath)) { throw "Checksum file is missing: $checksumPath" }
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $line = Get-Content -LiteralPath $checksumPath | Where-Object { $_ -match [regex]::Escape([IO.Path]::GetFileName($archivePath)) + '\s*$' } | Select-Object -First 1
        if (-not $line -or $line -notmatch ('^([a-fA-F0-9]{64})\s+')) { throw 'SHA256SUMS.txt does not contain the release archive hash.' }
        if ($Matches[1].ToLowerInvariant() -ne $actualHash) { throw 'Release archive SHA-256 does not match SHA256SUMS.txt.' }
    }

    $result = [pscustomobject]@{
        State = 'Verified'
        Message = 'Release archive contains the complete installable distribution; payload hashes and module import passed.'
        Version = [string]$payload.Version
        Archive = $archivePath
        FileCount = @($manifest.files).Count
    }
    if ($Json) { $result | ConvertTo-Json -Depth 6 }
    elseif ($PassThru) { $result }
    else { $result | Format-List }
}
finally {
    if ([IO.Directory]::Exists($temporaryRoot)) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
