#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach ($name in @('SystemInfo','Detection','NativeSettings','Engine','Backup','Benchmark','Performance','Reports')) { Import-Module (Join-Path $root "Modules/$name.psm1") -Force }
$count=0
function Assert-That([bool]$Condition,[string]$Message) { if (-not $Condition) {throw "FAIL: $Message"};$script:count++;Write-Host "PASS: $Message" }
function Must-Reject([scriptblock]$Action,[string]$Message) { $failed=$false;try {$null=& $Action} catch {$failed=$true};Assert-That $failed $Message }
$context=[pscustomobject]@{Machine='Fixture machine';User='Fixture SID';Platform='Fixture'}
$hardware=[pscustomobject]@{OS='Windows fixture';Build=22631;CPU='Fixture CPU';GPU='Fixture GPU';RAM='16 GB';GPUDetails=@([pscustomobject]@{Name='Fixture GPU';DriverVersion='1.0'})}
$sampling=[pscustomobject]@{RequestedCount=3;CollectedCount=3;IntervalSeconds=1;StartedUtc=[DateTime]::UtcNow.AddSeconds(-2).ToString('o');FinishedUtc=[DateTime]::UtcNow.ToString('o');CpuMinimum=0;CpuMaximum=100}
$before=New-ToolkitPerformanceSnapshot -SystemInfo $hardware -Values @{CpuPercent=20;MemoryUsedPercent=50;AvailableMemoryMB=8192;TotalMemoryMB=16384;ProcessCount=100;StartupCommandCount=10;UptimeSeconds=3600} -Configuration @{'power-plan'=[pscustomobject]@{State='Known';Value='Balanced';Source='Fixture'};'unknown'=[pscustomobject]@{State='Missing';Value=$null;Source='Fixture'}} -Context $context -Sampling $sampling -Label Before
$after=New-ToolkitPerformanceSnapshot -SystemInfo $hardware -Values @{CpuPercent=10;MemoryUsedPercent=40;AvailableMemoryMB=9830.4;TotalMemoryMB=16384;ProcessCount=90;StartupCommandCount=8;UptimeSeconds=7200} -Configuration @{'power-plan'=[pscustomobject]@{State='Known';Value='Balanced';Source='Fixture'};'unknown'=[pscustomobject]@{State='Missing';Value=$null;Source='Fixture'};'advertising'=[pscustomobject]@{State='Known';Value=0;Source='Fixture'}} -Context $context -Sampling $sampling -Label After
$report=Compare-ToolkitPerformance -Before $before -After $after
$cpu=@($report.Metrics | Where-Object {$_.Metric -eq 'CpuPercent'})[0]
Assert-That ($cpu.Delta -eq -10 -and $cpu.PercentChange -eq -50) 'Resource delta uses After minus Before and correct relative percent'
Assert-That (@($report.Benchmarks | Where-Object {$null -ne $_.Delta -or $_.Status -ne 'NotMeasured'}).Count -eq 0) 'No invented gaming results when benchmarks are absent'
Assert-That (@($report.Configuration | Where-Object {$_.Metric -eq 'power-plan'})[0].Status -eq 'Unchanged') 'Known power plan compares independently from resource data'
Assert-That (@($report.Configuration | Where-Object {$_.Metric -eq 'unknown'})[0].Status -eq 'Unknown') 'Two missing configuration values are not falsely called unchanged'
Assert-That (@($report.Configuration | Where-Object {$_.Metric -eq 'advertising'})[0].Status -eq 'Unknown') 'A setting absent from one capture is not treated as an applied optimization'
Assert-That ($report.Interpretation.Contains('do not establish higher gaming FPS')) 'Report always includes evidence limits'
Assert-That ($null -eq $report.PSObject.Properties['Context']) 'Export model omits private SID/machine identity'
$zero=$before | ConvertTo-Json -Depth 20 | ConvertFrom-Json
($zero.Metrics | Where-Object {$_.Id -eq 'CpuPercent'}).Value=0
$zeroReport=Compare-ToolkitPerformance -Before $zero -After $after
Assert-That ($null -eq @($zeroReport.Metrics | Where-Object {$_.Metric -eq 'CpuPercent'})[0].PercentChange) 'Zero baseline never divides by zero'
$missing=$after | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$memory=$missing.Metrics | Where-Object {$_.Id -eq 'MemoryUsedPercent'};$memory.Value=$null;$memory.Status='Unavailable'
$missingReport=Compare-ToolkitPerformance -Before $before -After $missing
Assert-That (@($missingReport.Metrics | Where-Object {$_.Metric -eq 'MemoryUsedPercent'})[0].Status -eq 'NotMeasured') 'Unavailable readings stay unmeasured rather than zero'
$foreign=$after | ConvertTo-Json -Depth 20 | ConvertFrom-Json;$foreign.Context.User='Other'
Must-Reject {Compare-ToolkitPerformance -Before $before -After $foreign} 'Cross-user/machine snapshots are rejected'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('toolkit-performance-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try {
    $saved=Save-ToolkitPerformanceSnapshot -Directory $temp -Snapshot $before
    $loaded=Read-ToolkitPerformanceSnapshot -Directory $temp -Id $saved.Id -Context $context
    Assert-That ($loaded.Id -eq $before.Id -and $loaded.Metrics.Count -eq 7) 'Measurement snapshot round-trips through checksummed storage'
    Must-Reject {Save-ToolkitPerformanceSnapshot -Directory $temp -Snapshot $before} 'Saved measurement IDs are immutable'
    Assert-That (@(Get-ToolkitPerformanceHistory -Directory $temp -Context $context).Count -eq 1) 'Measurement history finds saved captures'
    Must-Reject {Read-ToolkitPerformanceSnapshot -Directory $temp -Id '../escape' -Context $context} 'Measurement IDs cannot escape their store'
    $benchmark=[pscustomobject]@{schemaVersion=1;game='Fixture game';scenario='Fixed replay';resolution='1920x1080';qualityPreset='High';tool='External fixture';toolVersion='1';durationSeconds=60;runCount=3;averageFps=100;onePercentLowFps=75;meanFrameTimeMs=10}
    $json=Join-Path $temp 'benchmark.json';$csv=Join-Path $temp 'benchmark.csv'
    $benchmark | ConvertTo-Json | Set-Content -LiteralPath $json
    $benchmark | Export-Csv -LiteralPath $csv -NoTypeInformation
    Assert-That ((Import-ToolkitBenchmark -Path $json).averageFps -eq 100) 'Normalized JSON summary imports only supplied measurements'
    Assert-That ((Import-ToolkitBenchmark -Path $csv).onePercentLowFps -eq 75) 'Single-row normalized CSV summary is supported'
    $withBefore=Add-ToolkitBenchmarkToSnapshot -Snapshot $before -Path $json
    Assert-That ($withBefore.Id -ne $before.Id -and $withBefore.DerivedFrom -eq $before.Id -and $null -eq $before.Benchmark) 'Attaching benchmark creates a derived snapshot without changing the original'
    $benchmark.averageFps=110;$benchmark.onePercentLowFps=80;$benchmark.meanFrameTimeMs=9.1
    $benchmark | ConvertTo-Json | Set-Content -LiteralPath $json
    $withAfter=Add-ToolkitBenchmarkToSnapshot -Snapshot $after -Path $json
    $gaming=Compare-ToolkitPerformance -Before $withBefore -After $withAfter
    Assert-That ($gaming.Benchmarks[0].Delta -eq 10 -and $gaming.Benchmarks[0].Status -eq 'ImportedComparison') 'Matched benchmark conditions produce descriptive imported deltas'
    $withAfter.Benchmark.resolution='2560x1440'
    $different=Compare-ToolkitPerformance -Before $withBefore -After $withAfter
    Assert-That ($null -eq $different.Benchmarks[0].Delta -and $different.Benchmarks[0].Status -eq 'DifferentConditions') 'Changed resolution suppresses benchmark deltas'
    $withAfter.Benchmark.resolution='1920x1080'
    $withAfter.Hardware.GPUDrivers[0].DriverVersion='2.0'
    $driverChanged=Compare-ToolkitPerformance -Before $withBefore -After $withAfter
    Assert-That ($null -eq $driverChanged.Benchmarks[0].Delta) 'Changed GPU driver version suppresses benchmark deltas'
    $withAfter.Hardware.GPUDrivers[0].DriverVersion='1.0'
    $withAfter.Hardware.GPU='Other GPU'
    $different=Compare-ToolkitPerformance -Before $withBefore -After $withAfter
    Assert-That ($null -eq $different.Benchmarks[0].Delta) 'Changed hardware suppresses benchmark deltas'
    foreach ($badNumber in @('NaN','Infinity','-1','1e999','10,5')) {
        $benchmark.averageFps=$badNumber;$benchmark | ConvertTo-Json | Set-Content -LiteralPath $json
        Must-Reject {Import-ToolkitBenchmark -Path $json} "Reject invalid benchmark numeric value $badNumber"
    }
    $benchmark.averageFps=100;$benchmark.onePercentLowFps=101;$benchmark | ConvertTo-Json | Set-Content -LiteralPath $json
    Must-Reject {Import-ToolkitBenchmark -Path $json} 'Impossible 1% low summary is rejected'
    $benchmark.averageFps=$null;$benchmark.onePercentLowFps=$null;$benchmark.meanFrameTimeMs=$null;$benchmark | ConvertTo-Json | Set-Content -LiteralPath $json
    Must-Reject {Import-ToolkitBenchmark -Path $json} 'Empty benchmark template is not interpreted as measured results'
    @($benchmark,$benchmark) | Export-Csv -LiteralPath $csv -NoTypeInformation
    Must-Reject {Import-ToolkitBenchmark -Path $csv} 'Raw/multi-row benchmark CSV is not silently aggregated'
    $report.Before.Label='=SUM(1,2)';$report.After.Label='<script>alert(1)</script>| [link](x)'
    foreach ($format in @('JSON','Markdown','CSV')) {
        $path=Join-Path $temp ('report.'+$format.ToLowerInvariant())
        $null=Export-ToolkitPerformanceReport -Report $report -Path $path -Format $format
        Assert-That ((Get-Item -LiteralPath $path).Length -gt 0) "$format report exports successfully"
        Must-Reject {Export-ToolkitPerformanceReport -Report $report -Path $path -Format $format} "$format export never overwrites an existing file"
    }
    $exported=[IO.File]::ReadAllText((Join-Path $temp 'report.json')) | ConvertFrom-Json
    Assert-That ($exported.Metrics.Count -eq 7 -and $exported.Benchmarks.Count -eq 3) 'JSON report preserves measured and unmeasured rows'
    $csvRows=@(Import-Csv -LiteralPath (Join-Path $temp 'report.csv'))
    Assert-That ($csvRows[0].Before.StartsWith("'=")) 'CSV user-entered formula prefixes are neutralized'
    Assert-That (@($csvRows | Where-Object {$_.Metric -eq 'Hardware.GPU'}).Count -eq 1) 'CSV includes hardware/benchmark context'
    Assert-That (@($csvRows | Where-Object {$_.Metric -eq 'Hardware.GPUDrivers'})[0].Before.Contains('1.0')) 'CSV preserves driver context for benchmark review'
    $markdown=[IO.File]::ReadAllText((Join-Path $temp 'report.markdown'))
    Assert-That (-not $markdown.Contains('<script>') -and $markdown.Contains('\|')) 'Markdown escapes embedded markup and table delimiters'
    $culture=[Threading.Thread]::CurrentThread.CurrentCulture
    try {
        [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]'de-DE'
        Assert-That ((ConvertTo-ToolkitNumber -Value 10.5) -eq 10.5) 'Native decimal values work under a comma-decimal locale'
    } finally {[Threading.Thread]::CurrentThread.CurrentCulture=$culture}
    $bad=$before | ConvertTo-Json -Depth 20 | ConvertFrom-Json;$bad.Metrics[0].Value=101
    Must-Reject {Save-ToolkitPerformanceSnapshot -Directory $temp -Snapshot $bad} 'Out-of-range CPU metric rejected before persistence'
    [IO.File]::WriteAllText($saved.Path,'{"Payload":"{}","SHA256":"invalid"}')
    Must-Reject {Read-ToolkitPerformanceSnapshot -Directory $temp -Id $saved.Id -Context $context} 'Corrupt saved measurement rejected'
    # End-to-end CLI capture/read/compare/export uses the actual current host.
    # On Linux this produces honest preview/unknown Windows metrics.
    $whatIfDir=Join-Path $temp 'measurement whatif'
    $null=& (Join-Path $root 'Start.ps1') -CaptureMeasurement Before -DataDirectory $whatIfDir -WhatIf
    Assert-That (-not (Test-Path -LiteralPath $whatIfDir)) 'Measurement entry point respects WhatIf without saving a capture'
    $cliDir=Join-Path $temp 'cli'
    $cliBefore=& (Join-Path $root 'Start.ps1') -CaptureMeasurement Before -SampleCount 1 -DataDirectory $cliDir
    $cliAfter=& (Join-Path $root 'Start.ps1') -CaptureMeasurement After -SampleCount 1 -DataDirectory $cliDir
    Assert-That ($cliBefore.Id -ne $cliAfter.Id) 'CLI capture creates distinct Before and After measurements'
    $history=@(& (Join-Path $root 'Start.ps1') -MeasurementHistory -DataDirectory $cliDir)
    Assert-That ($history.Count -eq 2) 'CLI measurement history lists both captures'
    $cliPath=Join-Path $cliDir 'comparison.md'
    $null=& (Join-Path $root 'Start.ps1') -CompareMeasurements -BeforeId $cliBefore.Id -AfterId $cliAfter.Id -ReportPath $cliPath -DataDirectory $cliDir
    Assert-That (Test-Path -LiteralPath $cliPath) 'CLI comparison exports a standalone report'
    # Read-only collector tests replace OS queries, never native setters.
    $script:cpuRead=0;$script:partial=$false
    function global:Get-ToolkitSystemInfo {[pscustomobject]@{IsWindows=$true;OS='Windows fixture';Build=22631;CPU='Fixture';GPU='Fixture';RAM='16 GB';PowerPlan='Balanced'}}
    function global:Get-ToolkitPerformanceContext {[pscustomobject]@{Machine='Fixture';User='Fixture';Platform='Windows'}}
    function global:Get-CimInstance {
        [CmdletBinding()]param([string]$ClassName,[string]$Filter,[int]$OperationTimeoutSec)
        switch ($ClassName) {
            'Win32_PerfFormattedData_PerfOS_Processor' {$script:cpuRead++;if ($script:partial -and $script:cpuRead -eq 1) {throw 'Fixture counter failure'};[pscustomobject]@{PercentProcessorTime=10*$script:cpuRead}}
            'Win32_OperatingSystem' {[pscustomobject]@{TotalVisibleMemorySize=16777216;FreePhysicalMemory=8388608;LastBootUpTime=[DateTime]::UtcNow.AddHours(-2)}}
            'Win32_StartupCommand' {[pscustomobject]@{Name='A'};[pscustomobject]@{Name='B'}}
        }
    }
    function global:Get-Process {[CmdletBinding()]param();1;2;3}
    function global:Start-Sleep {param([int]$Seconds)}
    function global:Get-ToolkitObservations {param($SystemInfo);@{}}
    function global:Get-ToolkitNativeState {param([string]$OperationId);[pscustomobject]@{State='Error';Value=$null;Source='Fixture native failure'}}
    try {
        $capture=Get-ToolkitPerformanceSnapshot -Label Before
        Assert-That (@($capture.Metrics | Where-Object {$_.Id -eq 'CpuPercent'})[0].Value -eq 20) 'Collector computes CPU mean from actual supplied counter samples'
        Assert-That ($capture.Sampling.CpuMinimum -eq 10 -and $capture.Sampling.CpuMaximum -eq 30) 'CPU sample minimum/maximum are retained'
        Assert-That (@($capture.Metrics | Where-Object {$_.Id -eq 'MemoryUsedPercent'})[0].Value -eq 50) 'Physical memory percentage uses OS total/free values'
        Assert-That (@($capture.Metrics | Where-Object {$_.Id -eq 'StartupCommandCount'})[0].Value -eq 2) 'Startup inventory is counted without retaining command lines'
        Assert-That (@($capture.Configuration | Where-Object {$_.Id -eq 'native.mouse'})[0].State -eq 'Error') 'Native read failure remains unknown configuration'
        $script:cpuRead=0;$script:partial=$true
        $partial=Get-ToolkitPerformanceSnapshot
        Assert-That ($partial.Sampling.CollectedCount -eq 2 -and @($partial.Metrics | Where-Object {$_.Id -eq 'CpuPercent'})[0].Value -eq 25) 'Partial CPU queries average only successful readings and retain sample count'
        Must-Reject {Get-ToolkitPerformanceSnapshot -SampleCount 15 -SampleInterval 5} 'Unbounded sampling wait rejected'
    } finally {
        foreach ($name in @('Get-ToolkitSystemInfo','Get-ToolkitPerformanceContext','Get-CimInstance','Get-Process','Start-Sleep','Get-ToolkitObservations','Get-ToolkitNativeState')) {Remove-Item ('Function:/'+$name)}
        foreach ($name in @('SystemInfo','Detection','NativeSettings','Performance')) {Import-Module (Join-Path $root "Modules/$name.psm1") -Force}
    }
} finally {if (Test-Path $temp) {Remove-Item -LiteralPath $temp -Recurse -Force}}
Write-Host "`n$count performance assertions passed. Fixture results are not real benchmark evidence."
