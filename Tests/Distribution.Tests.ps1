#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'Modules/Distribution.psm1') -Force
$count=0
function Assert-That([bool]$Condition,[string]$Message) {if (-not $Condition) {throw "FAIL: $Message"};$script:count++;Write-Host "PASS: $Message"}
function Must-Reject([scriptblock]$Action,[string]$Message) {$failed=$false;try {$null=& $Action} catch {$failed=$true};Assert-That $failed $Message}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('toolkit-distribution-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
$script:built=$null;$script:sentinel=Join-Path $temp 'never-executed.txt'
function New-TestPackage([string]$Mutation) {
    $folder=Join-Path $temp $Mutation;$null=New-Item -ItemType Directory -Path $folder
    $entries=New-Object 'System.Collections.Generic.Dictionary[string,object]' -ArgumentList ([StringComparer]::Ordinal)
    $zip=[IO.Compression.ZipFile]::OpenRead($script:built.PackagePath)
    try {
        foreach ($entry in $zip.Entries) {
            $stream=$entry.Open();$memory=New-Object IO.MemoryStream
            try {$stream.CopyTo($memory);$entries[$entry.FullName]=$memory.ToArray()} finally {$stream.Dispose();$memory.Dispose()}
        }
    } finally {$zip.Dispose()}
    $manifest=[Text.Encoding]::UTF8.GetString($entries['PackageManifest.json']) | ConvertFrom-Json
    switch ($Mutation) {
        'Traversal' {$entries['../escape.ps1']=[Text.Encoding]::UTF8.GetBytes('not executed')}
        'Absolute' {$entries['C:/escape.ps1']=[Text.Encoding]::UTF8.GetBytes('not executed')}
        'Backslash' {$entries['Modules\escape.ps1']=[Text.Encoding]::UTF8.GetBytes('not executed')}
        'Reserved' {$entries['AUX.ps1']=[Text.Encoding]::UTF8.GetBytes('not executed')}
        'Extra' {$entries['extra.ps1']=[Text.Encoding]::UTF8.GetBytes('not executed')}
        'Duplicate' {$entries['start.PS1']=$entries['Start.ps1']}
        'Missing' {$null=$entries.Remove('Start.ps1')}
        'Symlink' {$entries['link']=[Text.Encoding]::UTF8.GetBytes('Start.ps1')}
        'CorruptContent' {$entries['Start.ps1'][0]=$entries['Start.ps1'][0] -bxor 1}
        'WrongFileHash' {$manifest.Files[0].SHA256=('0'*64)}
        'Oversize' {$manifest.Files[0].Length=9MB}
        'BadSettings' {
            $settings=[Text.Encoding]::UTF8.GetString($entries['Config/Settings.json']) | ConvertFrom-Json
            $settings.defaultMode='Apply'
            $entries['Config/Settings.json']=[Text.Encoding]::UTF8.GetBytes(($settings | ConvertTo-Json))
        }
        'Canary' {$entries['Start.ps1']=[Text.Encoding]::UTF8.GetBytes("[IO.File]::WriteAllText('"+$script:sentinel.Replace("'","''")+"','unsafe auto execution')")}
    }
    if ($Mutation -in @('BadSettings','Canary')) {
        $path=if ($Mutation -eq 'BadSettings') {'Config/Settings.json'} else {'Start.ps1'}
        $file=$manifest.Files | Where-Object {$_.Path -ceq $path}
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$file.SHA256=([BitConverter]::ToString($sha.ComputeHash($entries[$path]))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
        $file.Length=$entries[$path].Length
    }
    $entries['PackageManifest.json']=[Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 8))
    $path=Join-Path $folder 'WindowsPerformanceToolkit-0.6.0.zip'
    $archive=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $entries.Keys) {
            $entry=$archive.CreateEntry($name);$entry.ExternalAttributes=0
            if ($Mutation -eq 'Symlink' -and $name -eq 'link') {$entry.ExternalAttributes=-1577123840}
            $stream=$entry.Open();try {$stream.Write($entries[$name],0,$entries[$name].Length)} finally {$stream.Dispose()}
        }
    } finally {$archive.Dispose()}
    $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($path+'.sha256'),($hash+'  WindowsPerformanceToolkit-0.6.0.zip'))
    $path
}
try {
    $script:built=& (Join-Path $root 'Tools/Build-Release.ps1') -SourceRoot $root -OutputDirectory (Join-Path $temp 'build') -AllowDirty
    Assert-That (Test-Path -LiteralPath $built.PackagePath) 'Release builder creates the versioned ZIP'
    $verified=Test-ToolkitPackage -PackagePath $built.PackagePath
    Assert-That ($verified.Verified -and $verified.Version -eq '0.6.0') 'Published-style checksum and per-file manifest validate'
    Assert-That (@($verified.Manifest.Files | Where-Object {$_.Path -match '^(Data|Tests|Tools|artifacts|\.git|\.github|Docs/Requirements)/'}).Count -eq 0) 'Packages exclude local data, tests, repository internals and private project notes'
    $data=Join-Path $temp 'data';$versions=Join-Path $data 'Versions'
    $null=New-Item -ItemType Directory -Path (Join-Path $data 'Sessions') -Force
    [IO.File]::WriteAllText((Join-Path $data 'Sessions/keep.txt'),'Existing recovery data')
    $null=New-Item -ItemType Directory -Path (Join-Path $versions '0.5.0') -Force
    [IO.File]::WriteAllText((Join-Path $versions '0.5.0/keep.txt'),'Existing old version')
    $installed=Install-ToolkitPackage -PackagePath $built.PackagePath -DestinationRoot $versions
    Assert-That ($installed.Status -eq 'Installed' -and -not $installed.Executed) 'Offline install copies verified files without starting code'
    Assert-That ((Get-Content -LiteralPath (Join-Path $data 'Sessions/keep.txt') -Raw) -eq 'Existing recovery data') 'Shared recovery data survives installation'
    Assert-That (Test-Path -LiteralPath (Join-Path $versions '0.5.0/keep.txt')) 'Previous versions remain untouched'
    Assert-That (Test-Path -LiteralPath $installed.LaunchPath) 'Installed package includes the Windows launcher'
    Must-Reject {Install-ToolkitPackage -PackagePath $built.PackagePath -DestinationRoot $versions} 'Installer never replaces an existing version'
    $what=Join-Path $temp 'whatif'
    $result=Install-ToolkitPackage -PackagePath $built.PackagePath -DestinationRoot $what -WhatIf
    Assert-That ($result.Status -eq 'Cancelled' -and -not (Test-Path -LiteralPath $what)) 'WhatIf does not create an installation directory'
    $wrapperRoot=Join-Path $temp 'wrapper whatif'
    $wrapper=& (Join-Path $root 'Install.ps1') -PackagePath $built.PackagePath -DestinationRoot $wrapperRoot -WhatIf
    Assert-That ($wrapper.Status -eq 'Cancelled' -and -not (Test-Path -LiteralPath $wrapperRoot)) 'Installer entry point preserves WhatIf behavior'
    Must-Reject {Assert-ToolkitReleaseVersion "0.6.0`n"} 'Trailing control characters cannot enter release URLs'
    Must-Reject {Test-ToolkitPackage -PackagePath $built.PackagePath -ExpectedSHA256 ('0'*64)} 'Wrong archive checksum is rejected'
    Must-Reject {Test-ToolkitPackage -PackagePath $built.PackagePath -ExpectedSHA256 'invalid'} 'Malformed expected hash is rejected'
    $renamed=Join-Path $temp 'Downloaded package (1).zip';Copy-Item -LiteralPath $built.PackagePath -Destination $renamed
    Assert-That ((Test-ToolkitPackage -PackagePath $renamed -ChecksumPath $built.ChecksumPath).Verified) 'Browser-renamed archives still verify against the canonical checksum'
    foreach ($mutation in @('Traversal','Absolute','Backslash','Reserved','Extra','Duplicate','Missing','Symlink','CorruptContent','WrongFileHash','Oversize')) {
        $bad=New-TestPackage $mutation
        Must-Reject {Test-ToolkitPackage -PackagePath $bad} "Reject unsafe or tampered package: $mutation"
    }
    $bad=New-TestPackage BadSettings;$badRoot=Join-Path $temp 'bad settings destination'
    Must-Reject {Install-ToolkitPackage -PackagePath $bad -DestinationRoot $badRoot} 'A package cannot replace the dry-run default with Apply'
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $badRoot '0.6.0'))) 'Failed staging never publishes a half-installed version'
    Assert-That (@(Get-ChildItem -LiteralPath $badRoot -Force).Count -eq 0) 'Failed installation cleans only its temporary staging directory'
    $canary=New-TestPackage Canary
    $null=Install-ToolkitPackage -PackagePath $canary -DestinationRoot (Join-Path $temp 'canary install')
    Assert-That (-not (Test-Path -LiteralPath $sentinel)) 'Even correctly hashed scripts are not executed by installation'
    # The installed code must support a non-interactive preview from outside its folder.
    $preview=(& (Join-Path $installed.Path 'Start.ps1') -Preview 6>&1 | Out-String)
    Assert-That ($preview.Contains('DASHBOARD / v0.6.0')) 'Installed payload starts in preview mode without source checkout dependencies'
    $script:requests=0;$script:releaseVersion='0.7.0';$script:unavailable=$false
    function global:Invoke-RestMethod {
        [CmdletBinding()]param([string]$Uri,$Headers,[int]$TimeoutSec)
        $script:requests++
        if ($Uri -cne 'https://api.github.com/repos/mamamiagit/miashell-mama/releases/latest') {throw 'Untrusted update endpoint'}
        if ($script:unavailable) {throw 'Fixture offline'}
        [pscustomobject]@{draft=$false;prerelease=$false;tag_name=('v'+$script:releaseVersion);assets=@([pscustomobject]@{name=('WindowsPerformanceToolkit-'+$script:releaseVersion+'.zip')},[pscustomobject]@{name=('WindowsPerformanceToolkit-'+$script:releaseVersion+'.zip.sha256')})}
    }
    function global:Invoke-WebRequest {
        [CmdletBinding()]param([switch]$UseBasicParsing,[string]$Uri,[string]$OutFile,[int]$TimeoutSec)
        $script:requests++
        $base='https://github.com/mamamiagit/miashell-mama/releases/download/v0.6.0/WindowsPerformanceToolkit-0.6.0.zip'
        if ($Uri -ceq $base) {Copy-Item -LiteralPath $script:built.PackagePath -Destination $OutFile}
        elseif ($Uri -ceq ($base+'.sha256')) {Copy-Item -LiteralPath $script:built.ChecksumPath -Destination $OutFile}
        else {throw 'Untrusted release endpoint'}
    }
    try {
        $script:requests=0
        $null=& (Join-Path $root 'Start.ps1') -Preview
        Assert-That ($script:requests -eq 0) 'Ordinary startup never contacts the update service'
        $update=Get-ToolkitUpdate -CurrentVersion '0.6.0'
        Assert-That ($update.Status -eq 'UpdateAvailable' -and -not $update.Downloaded) 'Optional update check reports a newer version without downloading it'
        $script:releaseVersion='0.6.0'
        Assert-That ((Get-ToolkitUpdate -CurrentVersion '0.6.0').Status -eq 'Current') 'Equal release version is not treated as an update'
        $script:unavailable=$true
        Assert-That ((Get-ToolkitUpdate -CurrentVersion '0.6.0').Status -eq 'Unavailable') 'Offline update check is graceful and makes no false current-version claim'
        $script:unavailable=$false;$script:requests=0
        Must-Reject {Install-ToolkitRelease -Version 'https://example.com/script.ps1' -DestinationRoot $temp} 'Installer does not accept arbitrary GitHub URLs or commands as versions'
        Assert-That ($script:requests -eq 0) 'Invalid version performs no network request'
        $null=Install-ToolkitRelease -Version '0.6.0' -DestinationRoot (Join-Path $temp 'network whatif') -WhatIf
        Assert-That ($script:requests -eq 0) 'Online WhatIf never downloads files'
        $null=& (Join-Path $root 'Install.ps1') -Version '0.6.0' -DestinationRoot (Join-Path $temp 'wrapper online whatif') -WhatIf
        Assert-That ($script:requests -eq 0) 'Online installer entry point performs no download under WhatIf'
        $online=Install-ToolkitRelease -Version '0.6.0' -DestinationRoot (Join-Path $temp 'network install')
        Assert-That ($script:requests -eq 2 -and $online.Status -eq 'Installed' -and -not $online.Executed) 'Explicit download verifies both fixed-repository assets before side-by-side install'
    } finally {Remove-Item Function:/Invoke-RestMethod;Remove-Item Function:/Invoke-WebRequest}
} finally {if (Test-Path -LiteralPath $temp) {Remove-Item -LiteralPath $temp -Recurse -Force}}
Write-Host "`n$count distribution assertions passed. Network behavior was mocked; no published release or Windows signing is claimed."
