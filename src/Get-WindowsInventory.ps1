# Windows PowerShell 5.1 bridge for the Windows inbox Appx/StartLayout modules.
# Only installation metadata is returned. This script never launches an app.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$packages = @()
$registry = @()
$complete = $true
try {
    $startApps = @(Get-StartApps)
    foreach ($package in @(Get-AppxPackage -Name 'OpenAI.Codex')) {
        if ($package.PackageFamilyName -ne 'OpenAI.Codex_2p2nqsd0c76g0' -or $package.Status -ne 'Ok') { $complete = $false; continue }
        [xml]$manifest = Get-Content -LiteralPath (Join-Path $package.InstallLocation 'AppxManifest.xml') -Raw
        $countBefore = $packages.Count
        foreach ($app in $manifest.Package.Applications.Application) {
            $aumid = $package.PackageFamilyName + '!' + $app.Id
            if ($aumid -notin $startApps.AppID) { continue }
            $packages += [pscustomobject]@{
                Aumid = $aumid; PackageFamily = [string]$package.PackageFamilyName
                InstallLocation = [string]$package.InstallLocation
                Executable = [string]$app.Executable
                Version = [string]$package.Version
                Publisher = [string]$package.Publisher
            }
        }
        if ($packages.Count -eq $countBefore) { $complete = $false }
    }
} catch { $complete = $false }
try {
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        foreach ($entry in @(Get-ItemProperty -Path "$key\*" -ErrorAction Stop)) {
            if ($entry.DisplayName -match '^(Codex|ChatGPT)(\s.*)?$') {
                $registry += [pscustomobject]@{
                    Name = [string]$entry.DisplayName; Publisher = [string]$entry.Publisher
                    DisplayIcon = [string]$entry.DisplayIcon; InstallLocation = [string]$entry.InstallLocation
                }
            }
        }
    }
} catch { $complete = $false }
[pscustomobject]@{ Complete = $complete; Packages = @($packages); Registry = @($registry) } | ConvertTo-Json -Depth 5 -Compress
