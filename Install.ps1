#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName='Help')]
param(
    [Parameter(Mandatory,ParameterSetName='Package')][string]$PackagePath,
    [Parameter(ParameterSetName='Package')][string]$ChecksumPath,
    [Parameter(ParameterSetName='Package')][string]$ExpectedSHA256,
    [Parameter(Mandatory,ParameterSetName='Online')][string]$Version,
    [Parameter(Mandatory,ParameterSetName='Preview')][switch]$Preview,
    [Parameter(ParameterSetName='Package')][Parameter(ParameterSetName='Online')][string]$DestinationRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($Preview) {& (Join-Path $PSScriptRoot 'Start.ps1') -Preview;return}
if ($PSCmdlet.ParameterSetName -eq 'Help') {
    Write-Host 'Offline: .\Install.ps1 -PackagePath PATH.zip -ChecksumPath PATH.zip.sha256'
    Write-Host 'Online (explicit download): .\Install.ps1 -Version 0.6.0'
    Write-Host 'Installation verifies files but never starts the toolkit or changes execution policy.'
    return
}
if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $local=[Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($local)) {throw 'Supply a writable -DestinationRoot.'}
    $DestinationRoot=Join-Path (Join-Path $local 'WindowsPerformanceToolkit') 'Versions'
}
Import-Module (Join-Path $PSScriptRoot 'Modules/Distribution.psm1') -Force
$options=@{}
foreach ($common in @('WhatIf','Confirm')) { if ($PSBoundParameters.ContainsKey($common)) {$options[$common]=$PSBoundParameters[$common]} }
if ($PSCmdlet.ParameterSetName -eq 'Online') {Install-ToolkitRelease -Version $Version -DestinationRoot $DestinationRoot @options}
else {Install-ToolkitPackage -PackagePath $PackagePath -ChecksumPath $ChecksumPath -ExpectedSHA256 $ExpectedSHA256 -DestinationRoot $DestinationRoot @options}
