#requires -Version 7.4
<#
.SYNOPSIS
Build and validate the complete Codex Mode Switcher release archive.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [switch]$SkipCleanCheck,
    [switch]$Json,
    [switch]$PassThru
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Payload.ps1')

if (-not [IO.Path]::IsPathFullyQualified($OutputDirectory)) { throw 'OutputDirectory must be absolute.' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($output)
if (-not $SkipCleanCheck -and @(git -C $root status --porcelain).Count) {
    throw 'Release packaging requires a clean checkout. Commit or stash changes first.'
}
$payload = Assert-CodexModePayload -Root $root
$version = [string]$payload.Version
$archive = Join-Path $output "CodexModeSwitcher-$version.zip"
$manifestOutput = Join-Path $output 'release-manifest.json'
$checksumOutput = Join-Path $output 'SHA256SUMS.txt'
foreach ($path in @($archive, $manifestOutput, $checksumOutput)) {
    if ([IO.File]::Exists($path)) { throw "Release output already exists; choose a fresh directory: $path" }
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-mode-build-' + [guid]::NewGuid().ToString('N'))
$sourceArchive = Join-Path $temporaryRoot 'source.zip'
$extractRoot = Join-Path $temporaryRoot 'extract'
try {
    [void][IO.Directory]::CreateDirectory($temporaryRoot)
    git -C $root archive --format=zip --prefix=CodexModeSwitcher/ --output=$sourceArchive HEAD
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }
    Expand-Archive -LiteralPath $sourceArchive -DestinationPath $extractRoot -Force
    $payloadRoot = Join-Path $extractRoot 'CodexModeSwitcher'
    $extracted = Assert-CodexModePayload -Root $payloadRoot
    $manifest = Get-CodexModePayloadManifest -Root $payloadRoot -Version $extracted.Version
    $manifestPath = Join-Path $payloadRoot 'release-manifest.json'
    $manifestBytes = [Text.UTF8Encoding]::new($false).GetBytes(($manifest | ConvertTo-Json -Depth 12))
    [IO.File]::WriteAllBytes($manifestPath, $manifestBytes)
    Copy-Item -LiteralPath $manifestPath -Destination $manifestOutput

    Compress-Archive -LiteralPath $payloadRoot -DestinationPath $archive -CompressionLevel Optimal
    $archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestHash = (Get-FileHash -LiteralPath $manifestOutput -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksums = @(
        "$archiveHash  $([IO.Path]::GetFileName($archive))"
        "$manifestHash  release-manifest.json"
    ) -join "`n"
    [IO.File]::WriteAllText($checksumOutput, $checksums + "`n", [Text.UTF8Encoding]::new($false))

    & (Join-Path $PSScriptRoot 'Test-Release.ps1') -Archive $archive -ChecksumFile $checksumOutput -ManifestFile $manifestOutput -ErrorAction Stop

    $result = [pscustomobject]@{
        State = 'Built'
        Message = 'Complete release archive built and validated.'
        Version = $version
        Archive = $archive
        Manifest = $manifestOutput
        Checksums = $checksumOutput
        ArchiveSha256 = $archiveHash
        ManifestSha256 = $manifestHash
        FileCount = @($manifest.files).Count
    }
    if ($Json) { $result | ConvertTo-Json -Depth 6 }
    elseif ($PassThru) { $result }
    else { $result | Format-List }
}
finally {
    if ([IO.Directory]::Exists($temporaryRoot)) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
