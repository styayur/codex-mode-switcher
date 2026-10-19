BeforeAll {
    $script:Root = Split-Path -Path $PSScriptRoot -Parent
    $script:Payload = Join-Path $script:Root 'scripts/Payload.ps1'
    $script:TestRelease = Join-Path $script:Root 'scripts/Test-Release.ps1'
    . $script:Payload
}

Describe 'Release payload validation' {
    It 'requires every entry-point and module file in the payload' {
        $payload = Assert-CodexModePayload -Root $script:Root
        $payload.Version | Should -Match '^\d+\.\d+\.\d+$'
        foreach ($required in @('codex-mode.ps1', 'codex-mode.cmd', 'CodexModeSwitcher.psd1',
            'src/CodexMode.psm1', 'scripts/Invoke-Command.ps1', 'scripts/Install-CodexMode.ps1')) {
            $payload.Files | Should -Contain $required
        }
        $manifest = Get-CodexModePayloadManifest -Root $script:Root -Version $payload.Version
        foreach ($required in @('codex-mode.ps1', 'src/CodexMode.psm1', 'scripts/Payload.ps1')) {
            @($manifest.files | Where-Object { $_.path -eq $required }).Count | Should -Be 1
        }
    }

    It 'accepts a complete archive and rejects a payload changed after manifest generation' {
        $buildRoot = Join-Path $TestDrive 'release-source'
        $payloadRoot = Join-Path $buildRoot 'CodexModeSwitcher'
        New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
        foreach ($relative in @(Get-CodexModePayloadFile -Root $script:Root)) {
            $source = Join-Path $script:Root $relative
            $destination = Join-Path $payloadRoot $relative
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination
        }
        $version = (Import-PowerShellDataFile (Join-Path $script:Root 'CodexModeSwitcher.psd1')).ModuleVersion
        $manifest = Get-CodexModePayloadManifest -Root $payloadRoot -Version $version
        $manifestPath = Join-Path $payloadRoot 'release-manifest.json'
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        $archive = Join-Path $TestDrive 'CodexModeSwitcher-test.zip'
        Compress-Archive -LiteralPath $payloadRoot -DestinationPath $archive
        $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        $checksums = Join-Path $TestDrive 'SHA256SUMS.txt'
        [IO.File]::WriteAllText($checksums, "$hash  $([IO.Path]::GetFileName($archive))`n", [Text.UTF8Encoding]::new($false))
        { & $script:TestRelease -Archive $archive -ChecksumFile $checksums -ManifestFile $manifestPath -ErrorAction Stop } | Should -Not -Throw

        $tampered = Join-Path $payloadRoot 'src/CodexMode.psm1'
        [IO.File]::AppendAllText($tampered, "`n# tampered`n")
        $tamperedArchive = Join-Path $TestDrive 'CodexModeSwitcher-tampered.zip'
        Compress-Archive -LiteralPath $payloadRoot -DestinationPath $tamperedArchive
        { & $script:TestRelease -Archive $tamperedArchive -ManifestFile $manifestPath -SkipModuleCheck -ErrorAction Stop } | Should -Throw '*hash mismatch*'
    }
}
