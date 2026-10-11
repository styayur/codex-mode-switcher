function Get-WindowsDesktopInventory {
    if (-not $IsWindows) { return [pscustomobject]@{ Complete = $false; Packages = @(); Registry = @() } }
    $process = [Diagnostics.Process]::new()
    try {
        $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
        $process.StartInfo.FileName = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', (Join-Path $PSScriptRoot 'Get-WindowsInventory.ps1'))) {
            $process.StartInfo.ArgumentList.Add($argument)
        }
        [void]$process.Start()
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        # Cold Appx/Start-menu enumeration can exceed 15 seconds on a busy host.
        if (-not $process.WaitForExit(45000)) {
            # Only this controller-owned read-only probe may be stopped on timeout.
            $process.Kill()
            return [pscustomobject]@{ Complete = $false; Packages = @(); Registry = @() }
        }
        [void]$errors.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw 'Inventory failed' }
        return ($output.GetAwaiter().GetResult() | ConvertFrom-Json -ErrorAction Stop)
    } catch { return [pscustomobject]@{ Complete = $false; Packages = @(); Registry = @() } }
    finally { $process.Dispose() }
}

function Test-WindowsGuiExecutable([string]$Path) {
    if (-not [IO.File]::Exists($Path) -or [IO.Path]::GetExtension($Path) -ine '.exe') { return $false }
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $reader = [IO.BinaryReader]::new($stream)
        if ($reader.ReadUInt16() -ne 0x5a4d) { return $false }
        $stream.Position = 0x3c
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset + 94 -gt $stream.Length) { return $false }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { return $false }
        $stream.Position = $offset + 24 + 68
        return $reader.ReadUInt16() -eq 2 # IMAGE_SUBSYSTEM_WINDOWS_GUI; CLI is 3.
    } catch { return $false }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Test-DesktopExecutable([string]$Path) {
    if (-not (Test-WindowsGuiExecutable $Path)) { return $false }
    try {
        $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
        $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        return $signature.Status -eq 'Valid' -and
            $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -cin
                @('OpenAI', 'OpenAI, L.L.C.', 'OpenAI, Inc.', 'OpenAI Inc.') -and
            $info.ProductName -eq 'Codex'
    } catch { return $false }
}

function Get-DesktopIdentityRecord([string]$State, [string]$Reason) {
    [pscustomobject]@{
        State = $State; Reason = $Reason; Reliable = $State -ne 'Unknown'; Kind = $null
        Aumid = $null; ExecutablePath = $null; AllExecutablePaths = @(); PackageFamily = $null
        Version = $null; ActivationMethod = $null
    }
}

function Get-DesktopIdentity([string]$DesktopPath, [string]$DesktopAppId) {
    if (-not $IsWindows) { return Get-DesktopIdentityRecord 'Unknown' 'WindowsRequired' }
    if ($DesktopPath -and $DesktopAppId) { return Get-DesktopIdentityRecord 'Unknown' 'ConflictingDesktopSelectors' }
    $inventory = Get-WindowsDesktopInventory
    $candidates = [Collections.Generic.List[object]]::new()
    $incomplete = -not $inventory.Complete
    foreach ($package in $inventory.Packages) {
        try {
            $root = [IO.Path]::GetFullPath($package.InstallLocation).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            $path = [IO.Path]::GetFullPath((Join-Path $root $package.Executable))
            if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-WindowsGuiExecutable $path)) { $incomplete = $true; continue }
            $item = Get-DesktopIdentityRecord 'Installed' 'RegisteredMsixManifest'
            $item.Kind = 'Msix'; $item.Aumid = $package.Aumid; $item.ExecutablePath = $path
            $item.PackageFamily = $package.PackageFamily; $item.Version = $package.Version
            $item.ActivationMethod = 'IApplicationActivationManager'
            $candidates.Add($item)
        } catch { $incomplete = $true }
    }
    foreach ($entry in $inventory.Registry) {
        if ($entry.Publisher -notmatch '^OpenAI' -or $entry.Name -notmatch '^Codex(?:\s|$)') { continue }
        # DisplayIcon is data, never a shell command. Only an exact EXE + icon index.
        $match = [regex]::Match($entry.DisplayIcon, '^\s*(?:"([^"]+\.exe)"|([^",]+\.exe))(?:,\s*-?\d+)?\s*$', 'IgnoreCase')
        if (-not $match.Success) { $incomplete = $true; continue }
        $path = if ($match.Groups[1].Success) { $match.Groups[1].Value } else { $match.Groups[2].Value }
        if (-not [IO.Path]::IsPathFullyQualified($path) -or -not (Test-DesktopExecutable $path)) { $incomplete = $true; continue }
        $item = Get-DesktopIdentityRecord 'Installed' 'RegisteredSignedWin32'
        $item.Kind = 'Win32'; $item.ExecutablePath = [IO.Path]::GetFullPath($path)
        $item.ActivationMethod = 'CreateProcess'
        $candidates.Add($item)
    }
    if ($DesktopAppId) {
        if ($DesktopAppId -cnotmatch '^[A-Za-z0-9._-]+![A-Za-z0-9._-]+$') { return Get-DesktopIdentityRecord 'Unknown' 'InvalidAppUserModelId' }
        $selected = @($candidates | Where-Object { $_.Aumid -ceq $DesktopAppId })
    } elseif ($DesktopPath) {
        if (-not [IO.Path]::IsPathFullyQualified($DesktopPath)) { return Get-DesktopIdentityRecord 'Unknown' 'DesktopPathMustBeAbsolute' }
        $path = [IO.Path]::GetFullPath($DesktopPath)
        $selected = @($candidates | Where-Object { $_.ExecutablePath -ieq $path })
        if (-not $selected.Count) {
            if (-not (Test-DesktopExecutable $path)) { return Get-DesktopIdentityRecord 'Unknown' 'UnverifiedDesktopExecutable' }
            $item = Get-DesktopIdentityRecord 'Installed' 'ExplicitSignedWin32'
            $item.Kind = 'Win32'; $item.ExecutablePath = $path; $item.ActivationMethod = 'CreateProcess'
            $candidates.Add($item); $selected = @($item)
        }
    } else { $selected = @($candidates) }
    if ($incomplete) { return Get-DesktopIdentityRecord 'Unknown' 'InventoryIncomplete' }
    if (-not $selected.Count) {
        if ($DesktopPath -or $DesktopAppId) { return Get-DesktopIdentityRecord 'Unknown' 'RequestedIdentityNotRegistered' }
        return Get-DesktopIdentityRecord 'NotInstalled' 'NoSupportedRegistration'
    }
    if ($selected.Count -ne 1) { return Get-DesktopIdentityRecord 'Unknown' 'MultipleDesktopCandidates' }
    $selected[0].AllExecutablePaths = @($candidates.ExecutablePath | Sort-Object -Unique)
    return $selected[0]
}

function Get-DesktopProcessSnapshot {
    try {
        $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
        $processes = @(Get-CimInstance Win32_Process -Property ProcessId,Name,ExecutablePath,SessionId -ErrorAction Stop |
            Where-Object { $_.SessionId -eq $session } |
            Select-Object ProcessId,Name,ExecutablePath)
        [pscustomobject]@{ Complete = $true; Processes = $processes }
    } catch { [pscustomobject]@{ Complete = $false; Processes = @() } }
}

function Get-DesktopState($Identity) {
    if ($Identity.State -eq 'Unknown') { return [pscustomobject]@{ State = 'Unknown'; Reliable = $false; ProcessIds = @(); TaskActivity = 'Unknown' } }
    $snapshot = Get-DesktopProcessSnapshot
    $known = @($Identity.AllExecutablePaths)
    $matched = @($snapshot.Processes | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -iin $known })
    $names = @('Codex.exe', 'ChatGPT.exe') + @($known | ForEach-Object { [IO.Path]::GetFileName($_) })
    $unresolved = @($snapshot.Processes | Where-Object { $_.Name -iin $names -and -not $_.ExecutablePath })
    # A matching name only creates uncertainty; it never proves Desktop identity.
    if ($matched.Count) { $state = 'Running' }
    elseif (-not $snapshot.Complete -or $unresolved.Count) { $state = 'Unknown' }
    elseif ($Identity.State -eq 'NotInstalled') {
        $possible = @($snapshot.Processes | Where-Object { $_.Name -iin @('Codex.exe', 'ChatGPT.exe') })
        $state = if ($possible.Count) { 'Unknown' } else { 'NotInstalled' }
    } else { $state = 'Ready' }
    [pscustomobject]@{ State = $state; Reliable = $state -ne 'Unknown'; ProcessIds = @($matched | ForEach-Object { $_.ProcessId }); TaskActivity = 'Unknown' }
}
