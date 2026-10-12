#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
if (-not [IO.Path]::IsPathFullyQualified($OutputDirectory)) { throw 'OutputDirectory must be absolute.' }
$version=(Import-PowerShellDataFile (Join-Path $root 'CodexModeSwitcher.psd1')).ModuleVersion
if (@(git -C $root status --porcelain).Count) { throw 'Release packaging requires a clean checkout.' }
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$archive=Join-Path $OutputDirectory "CodexModeSwitcher-$version.zip"
if (Test-Path -LiteralPath $archive) { throw 'Archive already exists; choose a fresh output directory.' }
# git archive includes tracked source only, never local-originals or ignored credentials.
git -C $root archive --format=zip --prefix=CodexModeSwitcher/ --output=$archive HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'), "$hash  $([IO.Path]::GetFileName($archive))`n", [Text.UTF8Encoding]::new($false))
Get-Item -LiteralPath $archive
