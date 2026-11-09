#Requires -Version 5.1
[CmdletBinding()]
param([string]$SourceRoot,[string]$OutputDirectory,[string]$SourceCommit,[switch]$AllowDirty)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {$SourceRoot=Split-Path $PSScriptRoot -Parent}
$SourceRoot=[IO.Path]::GetFullPath($SourceRoot)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {$OutputDirectory=Join-Path $SourceRoot 'artifacts'}
Import-Module (Join-Path $SourceRoot 'Modules/Distribution.psm1') -Force
Initialize-ToolkitZip
Assert-ToolkitNoReparsePoint $SourceRoot
$settings=Get-Content -LiteralPath (Join-Path $SourceRoot 'Config/Settings.json') -Raw | ConvertFrom-Json
Assert-ToolkitReleaseVersion $settings.version
if ($settings.phase -ne 6 -or $settings.defaultMode -ne 'DryRun') {throw 'Only Phase 6 dry-run-default packages are supported.'}
$dirty=$false
if (Test-Path -LiteralPath (Join-Path $SourceRoot '.git')) {
    $head=(& git -C $SourceRoot rev-parse HEAD | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {throw 'Could not determine source commit.'}
    if (-not [string]::IsNullOrWhiteSpace($SourceCommit) -and $SourceCommit -cne $head) {throw 'Supplied commit does not match checkout.'}
    $SourceCommit=$head
    $changes=@(& git -C $SourceRoot status --porcelain)
    if ($LASTEXITCODE -ne 0) {throw 'Could not inspect working tree.'}
    $dirty=$changes.Count -gt 0
} elseif ([string]::IsNullOrWhiteSpace($SourceCommit)) {throw 'Supply -SourceCommit for a source tree without Git metadata.'}
if ($SourceCommit -notmatch '^[a-f0-9]{40}$') {throw 'SourceCommit must be a full lowercase Git SHA.'}
if ($dirty -and -not $AllowDirty) {throw 'Commit changes before building a release, or use -AllowDirty for a local candidate only.'}
$paths=@('Start.ps1','Install.ps1','Launch.cmd','README.md','LICENSE','CHANGELOG.md')
foreach ($folder in @('Modules','Config','Profiles','Docs')) {
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $SourceRoot $folder) -File -Recurse)) {
        $relative=$file.FullName.Substring($SourceRoot.TrimEnd([IO.Path]::DirectorySeparatorChar).Length+1).Replace('\','/')
        if ($relative -notlike 'Docs/Requirements/*') {$paths+=$relative}
    }
}
$paths=@($paths | Sort-Object -Unique)
$files=@(foreach ($path in $paths) {
    Assert-ToolkitPackagePath $path
    Assert-ToolkitNoReparsePoint (Join-Path $SourceRoot $path)
    $file=Get-Item -LiteralPath (Join-Path $SourceRoot $path) -ErrorAction Stop
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {throw 'Release inputs cannot be links.'}
    [pscustomobject]@{Path=$path;Length=$file.Length;SHA256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$manifest=[pscustomobject]@{SchemaVersion=1;Application='WindowsPerformanceToolkit';Version=$settings.version;SourceCommit=$SourceCommit;SourceDirty=$dirty;CreatedUtc=[DateTime]::UtcNow.ToString('o');Files=$files}
$manifestJson=$manifest | ConvertTo-Json -Depth 8
$null=ConvertTo-ToolkitPackageManifest $manifestJson
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$name=Get-ToolkitPackageName $settings.version
$package=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) $name
$manifestPath=$package+'.manifest.json';$checksumPath=$package+'.sha256'
foreach ($path in @($package,$manifestPath,$checksumPath)) {if (Test-Path -LiteralPath $path) {throw 'Release output already exists; use a fresh output directory.'}}
$stream=$null;$archive=$null
try {
    $stream=[IO.File]::Open($package,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    foreach ($file in $files) {
        $entry=$archive.CreateEntry($file.Path,[IO.Compression.CompressionLevel]::Optimal);$entry.ExternalAttributes=0
        $target=$entry.Open();$inputStream=[IO.File]::OpenRead((Join-Path $SourceRoot $file.Path))
        try {$inputStream.CopyTo($target)} finally {$inputStream.Dispose();$target.Dispose()}
    }
    $entry=$archive.CreateEntry('PackageManifest.json');$entry.ExternalAttributes=0
    $target=$entry.Open()
    try {$bytes=[Text.Encoding]::UTF8.GetBytes($manifestJson);$target.Write($bytes,0,$bytes.Length)} finally {$target.Dispose()}
    $archive.Dispose();$archive=$null;$stream.Flush($true);$stream.Dispose();$stream=$null
    [IO.File]::WriteAllText($manifestPath,$manifestJson,(New-Object Text.UTF8Encoding($false)))
    $hash=(Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText($checksumPath,($hash+'  '+$name+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
    $null=Test-ToolkitPackage -PackagePath $package -ChecksumPath $checksumPath
    [pscustomobject]@{Version=$settings.version;PackagePath=$package;ChecksumPath=$checksumPath;ManifestPath=$manifestPath;SHA256=$hash;SourceCommit=$SourceCommit;SourceDirty=$dirty}
} finally {if ($null -ne $archive) {$archive.Dispose()};if ($null -ne $stream) {$stream.Dispose()}}
