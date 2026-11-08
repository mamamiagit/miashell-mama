#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Preview,
    [switch]$SystemInfoOnly,
    [switch]$Compare,
    [ValidateSet('Recommended','Risk','Category','Restart','Applied','Unsupported')][string]$SortBy = 'Recommended',
    [string]$DxDiagPath,
    [string]$DataDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 can evaluate parameter defaults before PSScriptRoot
# is available. Resolve the default only after parameter binding completes.
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $DataDirectory = Join-Path $PSScriptRoot 'Data'
}
foreach ($name in @('SystemInfo','Detection','Recommendation','Optimization','Logging','Backup','Restore','Interface')) {
    Import-Module (Join-Path $PSScriptRoot "Modules/$name.psm1") -Force -ErrorAction Stop
}
$settings = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Config/Settings.json') -Raw | ConvertFrom-Json
if ($settings.phase -ne 2 -or $settings.simulationOnly -ne $true) {
    throw 'This build only supports Phase 2 simulation. Real operations are not implemented.'
}
$catalog = Get-ToolkitCatalog -Root $PSScriptRoot
# Keep the default profile first, with stable ordering for remaining profiles.
$catalog.Profiles = @($catalog.Profiles | Sort-Object @{Expression = { if ($_.id -eq $settings.defaultProfile) { 0 } else { 1 } }}, title)
$system = Get-ToolkitSystemInfo
$system | Add-Member -NotePropertyName HagsSupport -NotePropertyValue (Get-ToolkitHagsSupport -SystemInfo $system -DxDiagPath $DxDiagPath)
$observations = Get-ToolkitObservations -SystemInfo $system
if ($SystemInfoOnly) { $system; return }
if ($Compare) {
    $custom = $catalog.Profiles | Where-Object { $_.id -eq 'custom' } | Select-Object -First 1
    $selection = @(New-ToolkitSelection -Profile $custom -Items $catalog.Items -SystemInfo $system -Observations $observations)
    Get-ToolkitComparison -Selection $selection -SortBy $SortBy | Select-Object @{Name='Optimization';Expression={$_.Definition.title}}, CurrentState, Recommendation, Availability, ReadState, @{Name='Risk';Expression={$_.Definition.risk}}, @{Name='Restart';Expression={$_.Definition.restartRequired}}, RecommendedChange, AlreadyApplied, Reason, Source
    return
}
if ($Preview) {
    Show-ToolkitDashboard -Catalog $catalog -SystemInfo $system -Version $settings.version -NoClear
    return
}
try {
    $oldBackground = $Host.UI.RawUI.BackgroundColor
    $Host.UI.RawUI.BackgroundColor = 'Black'
} catch { $oldBackground = $null }
try {
    Start-ToolkitInterface -Catalog $catalog -SystemInfo $system -Settings $settings -HistoryDirectory $DataDirectory -Observations $observations
} finally {
    if ($null -ne $oldBackground) { $Host.UI.RawUI.BackgroundColor = $oldBackground }
}
