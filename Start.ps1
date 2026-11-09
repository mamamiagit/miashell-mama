#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Preview,
    [switch]$CheckUpdates,
    [switch]$SystemInfoOnly,
    [switch]$Compare,
    [switch]$DryRun,
    [switch]$Apply,
    [switch]$ValidateNative,
    [switch]$ListSessions,
    [string]$RestoreSession,
    [ValidateSet('mouse','animations')][string[]]$RestoreId,
    [switch]$CreateRestorePoint,
    [ValidateSet('Before','After','Custom')][string]$CaptureMeasurement,
    [switch]$MeasurementHistory,
    [switch]$CompareMeasurements,
    [string]$BeforeId,
    [string]$AfterId,
    [string]$ImportBenchmark,
    [string]$MeasurementId,
    [ValidateRange(1,15)][int]$SampleCount=3,
    [ValidateRange(1,5)][int]$SampleInterval=1,
    [string]$ReportPath,
    [ValidateSet('JSON','Markdown','CSV')][string]$ReportFormat='Markdown',
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
foreach ($name in @('SystemInfo','Detection','Recommendation','NativeSettings','Engine','Optimization','Logging','Backup','Transactions','Restore','Benchmark','Performance','Reports','Distribution','Interface')) {
    Import-Module (Join-Path $PSScriptRoot "Modules/$name.psm1") -Force -ErrorAction Stop
}
$settings = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Config/Settings.json') -Raw | ConvertFrom-Json
if ($settings.phase -ne 6 -or $settings.defaultMode -ne 'DryRun') {
    throw 'This build only supports Phase 6 distribution. Default mode must remain DryRun.'
}
$catalog = Get-ToolkitCatalog -Root $PSScriptRoot
# Keep the default profile first, with stable ordering for remaining profiles.
$catalog.Profiles = @($catalog.Profiles | Sort-Object @{Expression = { if ($_.id -eq $settings.defaultProfile) { 0 } else { 1 } }}, title)
$system = Get-ToolkitSystemInfo
$system | Add-Member -NotePropertyName HagsSupport -NotePropertyValue (Get-ToolkitHagsSupport -SystemInfo $system -DxDiagPath $DxDiagPath)
$observations = Get-ToolkitObservations -SystemInfo $system
$modes=@($CheckUpdates,$Preview,$SystemInfoOnly,$Compare,$DryRun,$Apply,$ValidateNative,$ListSessions,(-not [string]::IsNullOrWhiteSpace($RestoreSession)),(-not [string]::IsNullOrWhiteSpace($CaptureMeasurement)),$MeasurementHistory,$CompareMeasurements,(-not [string]::IsNullOrWhiteSpace($ImportBenchmark)))
if (@($modes | Where-Object { $_ }).Count -gt 1) { throw 'Choose one output/action mode at a time.' }
if ($CheckUpdates) { Get-ToolkitUpdate -CurrentVersion $settings.version; return }
if ($CreateRestorePoint -and -not $Apply) { throw '-CreateRestorePoint is optional for -Apply only.' }
if (-not [string]::IsNullOrWhiteSpace($ReportPath) -and -not $CompareMeasurements) { throw '-ReportPath requires -CompareMeasurements.' }
if (-not [string]::IsNullOrWhiteSpace($CaptureMeasurement)) {
    if (-not $PSCmdlet.ShouldProcess($DataDirectory,'Capture and save a resource/configuration measurement')) {return}
    $snapshot=Get-ToolkitPerformanceSnapshot -Label $CaptureMeasurement -SampleCount $SampleCount -SampleInterval $SampleInterval
    Save-ToolkitPerformanceSnapshot -Directory $DataDirectory -Snapshot $snapshot
    return
}
if ($MeasurementHistory) {
    Get-ToolkitPerformanceHistory -Directory $DataDirectory | Select-Object Id,Label,CapturedUtc,Origin,DerivedFrom
    return
}
if (-not [string]::IsNullOrWhiteSpace($ImportBenchmark)) {
    if ([string]::IsNullOrWhiteSpace($MeasurementId)) { throw '-ImportBenchmark requires -MeasurementId.' }
    if (-not $PSCmdlet.ShouldProcess($MeasurementId,'Attach a benchmark summary as a new derived measurement')) {return}
    $original=Read-ToolkitPerformanceSnapshot -Directory $DataDirectory -Id $MeasurementId
    $updated=Add-ToolkitBenchmarkToSnapshot -Snapshot $original -Path $ImportBenchmark
    Save-ToolkitPerformanceSnapshot -Directory $DataDirectory -Snapshot $updated
    return
}
if ($CompareMeasurements) {
    if ([string]::IsNullOrWhiteSpace($BeforeId) -or [string]::IsNullOrWhiteSpace($AfterId)) { throw 'Supply -BeforeId and -AfterId from saved measurements.' }
    $before=Read-ToolkitPerformanceSnapshot -Directory $DataDirectory -Id $BeforeId
    $after=Read-ToolkitPerformanceSnapshot -Directory $DataDirectory -Id $AfterId
    $report=Compare-ToolkitPerformance -Before $before -After $after
    if (-not [string]::IsNullOrWhiteSpace($ReportPath)) { if ($PSCmdlet.ShouldProcess($ReportPath,'Export comparison report')) {Export-ToolkitPerformanceReport -Report $report -Path $ReportPath -Format $ReportFormat} }
    else { $report }
    return
}
$actionOptions=@{}
foreach ($common in @('WhatIf','Confirm')) {if ($PSBoundParameters.ContainsKey($common)) {$actionOptions[$common]=$PSBoundParameters[$common]}}
if ($Apply) { Invoke-ToolkitSession -Directory $DataDirectory -OptimizationId $OptimizationId -CreateRestorePoint:$CreateRestorePoint @actionOptions; return }
if ($ValidateNative) { Invoke-ToolkitSession -Directory $DataDirectory -ValidateNative @actionOptions; return }
if ($ListSessions) { Get-ToolkitSessionHistory -Directory $DataDirectory -Context (Get-ToolkitContext); return }
if (-not [string]::IsNullOrWhiteSpace($RestoreSession)) { Restore-ToolkitSession -Directory $DataDirectory -SessionId $RestoreSession -OptimizationId $RestoreId @actionOptions; return }
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
