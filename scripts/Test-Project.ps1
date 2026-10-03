#requires -Version 7.4
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
# Load Pester first: command discovery during lint can otherwise autoload a
# different installed Pester version, whose assembly cannot be unloaded.
Import-Module Pester -RequiredVersion 5.7.1
$files = @(Get-ChildItem $root -Recurse -File | Where-Object {
    $_.Extension -in '.ps1', '.psd1' -and $_.FullName -notmatch '[\\/]local-originals[\\/]'
})
foreach ($file in $files) {
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors)
    if ($parseErrors) { throw "Syntax errors in $($file.Name): $parseErrors" }
}
Import-Module PSScriptAnalyzer -RequiredVersion 1.25.0
$issues = @($files | ForEach-Object {
    Invoke-ScriptAnalyzer -Path $_.FullName -Settings (Join-Path $root 'PSScriptAnalyzerSettings.psd1')
})
if ($issues.Count) { $issues | Format-Table -AutoSize | Out-Host; throw 'Static analysis failed.' }
$result = Invoke-Pester -Path (Join-Path $root 'tests') -Output Detailed -PassThru
if ($result.FailedCount -or $result.PassedCount -eq 0) { throw 'Pester failed or discovered no passing tests.' }
Write-Host "PASS: syntax, lint, $($result.PassedCount) Pester tests."
