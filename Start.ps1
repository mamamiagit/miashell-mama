#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Preview,
    [switch]$SystemInfoOnly,
    [switch]$Compare,
    [switch]$DryRun,
    [switch]$Apply,
    [switch]$ValidateNative,
    [switch]$ListSessions,
    [string]$RestoreSession,
    [ValidateSet('mouse','animations')][string[]]$RestoreId,
    [switch]$CreateRestorePoint,
    [string[]]$OptimizationId = @('mouse','animations'),
    [ValidateSet('Recommended','Risk','Category','Restart','Applied','Unsupported')][string]$SortBy = 'Recommended',
    [string]$DxDiagPath,
    [string]$DataDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 can evaluate parameter defaults before PSScriptRoot
# is available. Resolve the default only after parameter binding completes.
if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
    $localData=[Environment]::GetFolderPath('LocalApplicationData')
    if ($env:OS -eq 'Windows_NT' -and -not [string]::IsNullOrWhiteSpace($localData)) {
        $DataDirectory = Join-Path $localData 'WindowsPerformanceToolkit'
    } else { $DataDirectory = Join-Path $PSScriptRoot 'Data' }
}
foreach ($name in @('SystemInfo','Detection','Recommendation','NativeSettings','Engine','Optimization','Logging','Backup','Transactions','Restore','Interface')) {
    Import-Module (Join-Path $PSScriptRoot "Modules/$name.psm1") -Force -ErrorAction Stop
}
$settings = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Config/Settings.json') -Raw | ConvertFrom-Json
if ($settings.phase -ne 4 -or $settings.defaultMode -ne 'DryRun') {
    throw 'This build only supports Phase 4 transaction. Default mode must remain DryRun.'
}
$catalog = Get-ToolkitCatalog -Root $PSScriptRoot
# Keep the default profile first, with stable ordering for remaining profiles.
$catalog.Profiles = @($catalog.Profiles | Sort-Object @{Expression = { if ($_.id -eq $settings.defaultProfile) { 0 } else { 1 } }}, title)
$system = Get-ToolkitSystemInfo
$system | Add-Member -NotePropertyName HagsSupport -NotePropertyValue (Get-ToolkitHagsSupport -SystemInfo $system -DxDiagPath $DxDiagPath)
$observations = Get-ToolkitObservations -SystemInfo $system
$modes=@($Preview,$SystemInfoOnly,$Compare,$DryRun,$Apply,$ValidateNative,$ListSessions,(-not [string]::IsNullOrWhiteSpace($RestoreSession)))
if (@($modes | Where-Object { $_ }).Count -gt 1) { throw 'Choose one output/action mode at a time.' }
if ($CreateRestorePoint -and -not $Apply) { throw '-CreateRestorePoint is optional for -Apply only.' }
if ($Apply) { Invoke-ToolkitSession -Directory $DataDirectory -OptimizationId $OptimizationId -CreateRestorePoint:$CreateRestorePoint; return }
if ($ValidateNative) { Invoke-ToolkitSession -Directory $DataDirectory -ValidateNative; return }
if ($ListSessions) { Get-ToolkitSessionHistory -Directory $DataDirectory -Context (Get-ToolkitContext); return }
if (-not [string]::IsNullOrWhiteSpace($RestoreSession)) { Restore-ToolkitSession -Directory $DataDirectory -SessionId $RestoreSession -OptimizationId $RestoreId; return }
if ($SystemInfoOnly) { $system; return }
if ($DryRun) {
    $plan=@(New-ToolkitExecutionPlan -OptimizationId $OptimizationId -SystemInfo $system)
    Invoke-ToolkitEngine -Plan $plan -Mode DryRun
    return
}
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
