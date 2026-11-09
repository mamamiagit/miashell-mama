Set-StrictMode -Version Latest

function Assert-ToolkitReleaseVersion {
    param([Parameter(Mandatory)][string]$Version)
    if ($Version -notmatch '^(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\z') { throw 'Use a stable three-part version such as 0.6.0.' }
}

function Get-ToolkitPackageName {
    param([Parameter(Mandatory)][string]$Version)
    Assert-ToolkitReleaseVersion $Version
    'WindowsPerformanceToolkit-'+$Version+'.zip'
}

function Assert-ToolkitPackagePath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path.Length -gt 220 -or $Path -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*\z' -or $Path.Contains('//')) { throw "Unsafe package path: $Path" }
    foreach ($segment in $Path.Split('/')) {
        if ($segment -in @('.','..','') -or $segment.EndsWith('.') -or $segment -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') { throw "Unsupported Windows package path: $Path" }
    }
}

function Initialize-ToolkitZip {
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
}

function Assert-ToolkitNoReparsePoint {
    param([Parameter(Mandatory)][string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Package/install paths must not use symbolic links or reparse points.' }
        }
        $parent=[IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current=$parent.FullName
    }
}

function ConvertTo-ToolkitPackageManifest {
    param([Parameter(Mandatory)][string]$Json)
    if ($Json.Length -gt 1MB) { throw 'Package manifest exceeds size limit.' }
    $manifest=$Json | ConvertFrom-Json -ErrorAction Stop
    if ($manifest.SchemaVersion -ne 1 -or $manifest.Application -cne 'WindowsPerformanceToolkit' -or $manifest.SourceCommit -notmatch '^[a-f0-9]{40}\z' -or $manifest.SourceDirty -isnot [bool]) { throw 'Invalid package manifest identity or provenance.' }
    Assert-ToolkitReleaseVersion $manifest.Version
    $files=@($manifest.Files)
    if ($files.Count -lt 5 -or $files.Count -gt 512) { throw 'Invalid package file count.' }
    $seen=@{};$total=0L
    foreach ($file in $files) {
        if ($file.Path -isnot [string] -or $file.SHA256 -isnot [string]) { throw 'Manifest paths/hashes must be strings.' }
        Assert-ToolkitPackagePath $file.Path
        if ($seen.ContainsKey($file.Path) -or $file.Path -ieq 'PackageManifest.json' -or $file.SHA256 -notmatch '^[a-f0-9]{64}\z') { throw 'Duplicate or invalid manifest file entry.' }
        $seen[$file.Path]=$true
        $length=0L
        if (-not [long]::TryParse([string]$file.Length,[ref]$length) -or $length -lt 0 -or $length -gt 8MB) { throw 'Invalid package file size.' }
        $total+=$length
    }
    if ($total -gt 64MB) { throw 'Expanded package exceeds size limit.' }
    foreach ($required in @('Start.ps1','Install.ps1','Launch.cmd','Config/Settings.json','Modules/Distribution.psm1','LICENSE')) {
        if (-not $seen.ContainsKey($required)) { throw "Required package file missing: $required" }
    }
    $manifest
}

function Read-ToolkitPackageManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackagePath)
    Initialize-ToolkitZip
    Assert-ToolkitNoReparsePoint $PackagePath
    $file=Get-Item -LiteralPath $PackagePath -ErrorAction Stop
    if ($file.Length -gt 32MB) { throw 'Compressed package exceeds size limit.' }
    $archive=[IO.Compression.ZipFile]::OpenRead($file.FullName)
    try {
        $seen=@{};$entries=@{};$total=0L
        if ($archive.Entries.Count -gt 1024) { throw 'ZIP contains too many entries.' }
        foreach ($entry in $archive.Entries) {
            $name=$entry.FullName
            $mode=($entry.ExternalAttributes -shr 16) -band 0xF000
            if (($entry.ExternalAttributes -band 0x400) -ne 0) {throw 'ZIP reparse entries are not supported.'}
            if ($name.EndsWith('/')) {
                Assert-ToolkitPackagePath $name.TrimEnd('/')
                if ($entry.Length -ne 0 -or $mode -notin @(0,0x4000)) { throw 'Invalid ZIP directory entry.' }
                continue
            }
            Assert-ToolkitPackagePath $name
            if ($seen.ContainsKey($name)) { throw 'ZIP contains duplicate case-insensitive paths.' }
            $seen[$name]=$true;$entries[$name]=$entry
            # Unix symlinks and other special file types are not accepted.
            $mode=($entry.ExternalAttributes -shr 16) -band 0xF000
            if ($mode -notin @(0,0x8000) -or $entry.Length -gt 8MB) { throw 'ZIP special files/oversized entries are not supported.' }
            $total+=$entry.Length
        }
        if ($total -gt 65MB -or -not $entries.ContainsKey('PackageManifest.json') -or $entries['PackageManifest.json'].Length -gt 1MB) { throw 'Missing/oversized package manifest or expanded archive.' }
        $reader=New-Object IO.StreamReader($entries['PackageManifest.json'].Open())
        try {
            $text=New-Object Text.StringBuilder;$buffer=New-Object char[] 4096
            while (($count=$reader.Read($buffer,0,$buffer.Length)) -gt 0) {
                if ($text.Length+$count -gt 1MB) { throw 'Expanded manifest exceeds size limit.' }
                $null=$text.Append($buffer,0,$count)
            }
            $manifest=ConvertTo-ToolkitPackageManifest $text.ToString()
        } finally { $reader.Dispose() }
        if ($entries.Count -ne @($manifest.Files).Count+1) { throw 'Archive has extra or missing files outside its manifest.' }
        foreach ($item in $manifest.Files) {
            if (-not $entries.ContainsKey($item.Path) -or $entries[$item.Path].Length -ne $item.Length) { throw 'Archive/manifest file list mismatch.' }
        }
        $manifest
    } finally { $archive.Dispose() }
}

function Test-ToolkitPackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackagePath,[string]$ChecksumPath,[string]$ExpectedSHA256)
    $package=Get-Item -LiteralPath $PackagePath -ErrorAction Stop
    if (-not [string]::IsNullOrWhiteSpace($ChecksumPath) -and -not [string]::IsNullOrWhiteSpace($ExpectedSHA256)) { throw 'Supply a checksum file OR an expected hash, not both.' }
    $checksumName=$null
    if ([string]::IsNullOrWhiteSpace($ExpectedSHA256)) {
        if ([string]::IsNullOrWhiteSpace($ChecksumPath)) { $ChecksumPath=$package.FullName+'.sha256' }
        $checksum=Get-Item -LiteralPath $ChecksumPath -ErrorAction Stop
        if ($checksum.Length -gt 4096) { throw 'Checksum file is too large.' }
        $line=[IO.File]::ReadAllText($checksum.FullName).Trim()
        if ($line -notmatch '^([a-fA-F0-9]{64})[ \t]+\*?([A-Za-z0-9._-]+)$') { throw 'Use the single-file SHA-256 checksum published with the release.' }
        $ExpectedSHA256=$Matches[1];$checksumName=$Matches[2]
    }
    if ($ExpectedSHA256 -notmatch '^[a-fA-F0-9]{64}\z') { throw 'Expected SHA-256 must contain 64 hexadecimal digits.' }
    if ($package.Length -gt 32MB) { throw 'Compressed package exceeds size limit.' }
    $actual=(Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($actual -ine $ExpectedSHA256) { throw 'Package SHA-256 mismatch. Nothing was installed or executed.' }
    $manifest=Read-ToolkitPackageManifest -PackagePath $package.FullName
    $archive=[IO.Compression.ZipFile]::OpenRead($package.FullName)
    try {
        foreach ($file in $manifest.Files) {
            $stream=$archive.GetEntry($file.Path).Open();$sha=[Security.Cryptography.SHA256]::Create()
            try {
                $buffer=New-Object byte[] 65536;$count=0L
                while (($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0) {
                    $count+=$read
                    if ($count -gt $file.Length) {throw 'Expanded file exceeds manifest size.'}
                    $null=$sha.TransformBlock($buffer,0,$read,$buffer,0)
                }
                $null=$sha.TransformFinalBlock((New-Object byte[] 0),0,0)
                $digest=([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()
                if ($count -ne $file.Length -or $digest -cne $file.SHA256) {throw ('ZIP file content hash mismatch: '+$file.Path)}
            } finally {$stream.Dispose();$sha.Dispose()}
        }
    } finally {$archive.Dispose()}
    if ($null -ne $checksumName -and $checksumName -cne (Get-ToolkitPackageName $manifest.Version)) { throw 'Checksum filename does not match the manifest version.' }
    [pscustomobject]@{Verified=$true;SHA256=$actual.ToLowerInvariant();Version=$manifest.Version;Manifest=$manifest;PackagePath=$package.FullName}
}

function Test-ToolkitExtractedFiles {
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)]$Manifest)
    Assert-ToolkitNoReparsePoint $Directory
    foreach ($file in $Manifest.Files) {
        $path=Join-Path $Directory $file.Path.Replace('/',[IO.Path]::DirectorySeparatorChar)
        Assert-ToolkitNoReparsePoint $path
        $actual=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($actual.PSIsContainer -or $actual.Length -ne $file.Length -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.SHA256) { throw "Package content hash mismatch: $($file.Path)" }
    }
    $settings=Get-Content -LiteralPath (Join-Path $Directory 'Config/Settings.json') -Raw | ConvertFrom-Json
    if ($settings.version -cne $Manifest.Version -or $settings.phase -ne 6 -or $settings.defaultMode -cne 'DryRun') { throw 'Package settings disagree with manifest or required dry-run default.' }
}

function Install-ToolkitPackage {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$PackagePath,[string]$ChecksumPath,[string]$ExpectedSHA256,
          [Parameter(Mandatory)][string]$DestinationRoot)
    $verified=Test-ToolkitPackage -PackagePath $PackagePath -ChecksumPath $ChecksumPath -ExpectedSHA256 $ExpectedSHA256
    $root=[IO.Path]::GetFullPath($DestinationRoot);$destination=Join-Path $root $verified.Version
    Assert-ToolkitNoReparsePoint $root
    if (Test-Path -LiteralPath $destination) { throw 'This version already exists. Choose a new install root; existing versions/data are never replaced.' }
    if (-not $PSCmdlet.ShouldProcess($destination,'Install verified toolkit files; do not execute them')) { return [pscustomobject]@{Status='Cancelled';Version=$verified.Version;Path=$destination} }
    $null=New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop
    $stage=Join-Path $root ('.install-'+[guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $stage -ErrorAction Stop
    $archive=$null
    try {
        $archive=[IO.Compression.ZipFile]::OpenRead($verified.PackagePath)
        $entries=@{};foreach ($entry in $archive.Entries) {if (-not $entry.FullName.EndsWith('/')) {$entries[$entry.FullName]=$entry}}
        foreach ($file in @($verified.Manifest.Files)) {
            $target=Join-Path $stage $file.Path.Replace('/',[IO.Path]::DirectorySeparatorChar)
            $null=New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
            $inputStream=$entries[$file.Path].Open();$output=$null
            try {
                $output=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                $buffer=New-Object byte[] 65536;$copied=0L
                while (($read=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
                    $copied+=$read
                    if ($copied -gt $file.Length) { throw 'Expanded file exceeds its declared size.' }
                    $output.Write($buffer,0,$read)
                }
                if ($copied -ne $file.Length) { throw 'Truncated package file.' }
                $output.Flush($true)
            } finally {if ($null -ne $output) {$output.Dispose()};$inputStream.Dispose()}
        }
        $archive.Dispose();$archive=$null
        # Reconstruct the already verified manifest; never trust a second-read manifest.
        [IO.File]::WriteAllText((Join-Path $stage 'PackageManifest.json'),($verified.Manifest | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
        Test-ToolkitExtractedFiles -Directory $stage -Manifest $verified.Manifest
        if ($env:OS -eq 'Windows_NT') {
            foreach ($file in $verified.Manifest.Files) {
                if ([IO.Path]::GetExtension($file.Path) -in @('.ps1','.psm1')) { Unblock-File -LiteralPath (Join-Path $stage $file.Path.Replace('/',[IO.Path]::DirectorySeparatorChar)) -ErrorAction Stop }
            }
        }
        # Publish the entire verified directory in one move; never merge into an existing version.
        [IO.Directory]::Move($stage,$destination)
        [pscustomobject]@{Status='Installed';Version=$verified.Version;SourceCommit=$verified.Manifest.SourceCommit;SourceDirty=$verified.Manifest.SourceDirty;Path=$destination;LaunchPath=(Join-Path $destination 'Launch.cmd');SHA256=$verified.SHA256;Executed=$false;DataPreserved=$true}
    } finally {
        if ($null -ne $archive) {$archive.Dispose()}
        if (Test-Path -LiteralPath $stage) {Remove-Item -LiteralPath $stage -Recurse -Force}
    }
}

function Install-ToolkitRelease {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][string]$DestinationRoot)
    Assert-ToolkitReleaseVersion $Version
    $destination=Join-Path ([IO.Path]::GetFullPath($DestinationRoot)) $Version
    Assert-ToolkitNoReparsePoint $DestinationRoot
    if (Test-Path -LiteralPath $destination) {throw 'This version already exists; no files were downloaded.'}
    if (-not $PSCmdlet.ShouldProcess($destination,'Download a fixed GitHub release, verify and install it without execution')) { return }
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('WindowsPerformanceToolkit-download-'+[guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Path $temporary -ErrorAction Stop
    try {
        $name=Get-ToolkitPackageName $Version
        $base='https://github.com/mamamiagit/miashell-mama/releases/download/v'+$Version+'/'
        $package=Join-Path $temporary $name;$checksum=$package+'.sha256'
        Invoke-WebRequest -UseBasicParsing -Uri ($base+$name) -OutFile $package -TimeoutSec 60 -ErrorAction Stop
        Invoke-WebRequest -UseBasicParsing -Uri ($base+$name+'.sha256') -OutFile $checksum -TimeoutSec 30 -ErrorAction Stop
        $verified=Test-ToolkitPackage -PackagePath $package -ChecksumPath $checksum
        if ($verified.Version -cne $Version) {throw 'Downloaded release version mismatch.'}
        Install-ToolkitPackage -PackagePath $package -ChecksumPath $checksum -DestinationRoot $DestinationRoot -Confirm:$false
    } finally {if (Test-Path -LiteralPath $temporary) {Remove-Item -LiteralPath $temporary -Recurse -Force}}
}

function Get-ToolkitUpdate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CurrentVersion)
    Assert-ToolkitReleaseVersion $CurrentVersion
    try {
        $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/mamamiagit/miashell-mama/releases/latest' -Headers @{'User-Agent'='WindowsPerformanceToolkit'} -TimeoutSec 15 -ErrorAction Stop
        if ($release.draft -ne $false -or $release.prerelease -ne $false -or $release.tag_name -notmatch '^v(.+)\z') {throw 'No supported stable release.'}
        $latest=$Matches[1];Assert-ToolkitReleaseVersion $latest
        $name=Get-ToolkitPackageName $latest
        if ($name -notin @($release.assets.name) -or ($name+'.sha256') -notin @($release.assets.name)) {throw 'Latest release is missing verified-install assets.'}
        [pscustomobject]@{Status=$(if ([version]$latest -gt [version]$CurrentVersion) {'UpdateAvailable'} else {'Current'});InstalledVersion=$CurrentVersion;LatestVersion=$latest;ReleaseUrl=('https://github.com/mamamiagit/miashell-mama/releases/tag/v'+$latest);Downloaded=$false;Message='Informational check only. Installation is explicit and side by side.'}
    } catch {[pscustomobject]@{Status='Unavailable';InstalledVersion=$CurrentVersion;LatestVersion=$null;ReleaseUrl='https://github.com/mamamiagit/miashell-mama/releases';Downloaded=$false;Message='Could not verify a published stable release (offline, rate limited, missing assets, or no release). No update was downloaded or executed.'}}
}

Export-ModuleMember -Function Assert-ToolkitReleaseVersion, Get-ToolkitPackageName, Assert-ToolkitPackagePath, Initialize-ToolkitZip, Assert-ToolkitNoReparsePoint, ConvertTo-ToolkitPackageManifest, Read-ToolkitPackageManifest, Test-ToolkitPackage, Test-ToolkitExtractedFiles, Install-ToolkitPackage, Install-ToolkitRelease, Get-ToolkitUpdate
