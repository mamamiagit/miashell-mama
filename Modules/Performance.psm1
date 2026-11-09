Set-StrictMode -Version Latest

function Get-ToolkitPerformanceContext {
    if ($env:OS -eq 'Windows_NT') {
        $identity=Get-ToolkitContext
        [pscustomobject]@{Machine=$identity.Machine;User=$identity.User;Platform='Windows'}
    } else { [pscustomobject]@{Machine=[Environment]::MachineName;User=[Environment]::UserName;Platform='Preview'} }
}

function Get-ToolkitMetricDefinitions {
    [pscustomobject]@{Id='CpuPercent';Unit='%';Maximum=100;Note='Mean of sampled formatted CPU counter readings; not an FPS benchmark.'}
    [pscustomobject]@{Id='MemoryUsedPercent';Unit='%';Maximum=100;Note='Physical memory usage at capture; lower idle usage does not establish faster games.'}
    [pscustomobject]@{Id='AvailableMemoryMB';Unit='MiB';Maximum=1e12;Note='Available physical memory snapshot.'}
    [pscustomobject]@{Id='TotalMemoryMB';Unit='MiB';Maximum=1e12;Note='OS-visible physical memory, not memory bandwidth.'}
    [pscustomobject]@{Id='ProcessCount';Unit='count';Maximum=2147483647;Note='Observed processes; fewer processes do not prove higher FPS.'}
    [pscustomobject]@{Id='StartupCommandCount';Unit='count';Maximum=2147483647;Note='CIM startup-command inventory; not a complete count of enabled startup apps or scheduled tasks.'}
    [pscustomobject]@{Id='UptimeSeconds';Unit='s';Maximum=1e12;Note='Time since last boot; not a performance score.'}
}

function New-ToolkitPerformanceSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$SystemInfo,[Parameter(Mandatory)][hashtable]$Values,
          [hashtable]$Configuration=@{},[Parameter(Mandatory)]$Context,[Parameter(Mandatory)]$Sampling,
          [ValidateLength(1,80)][string]$Label='Custom',[ValidateSet('Native','Preview','Fixture')][string]$Origin='Fixture')
    if ($Label -match '[\x00-\x1F]') { throw 'Measurement labels cannot contain control characters.' }
    $metrics=@(foreach ($definition in Get-ToolkitMetricDefinitions) {
        $value=$null;$status='Unavailable'
        if ($Values.ContainsKey($definition.Id) -and $null -ne $Values[$definition.Id]) {
            $value=ConvertTo-ToolkitNumber -Value $Values[$definition.Id] -Maximum $definition.Maximum
            if ($definition.Unit -eq 'count' -and $value -ne [Math]::Floor($value)) { throw 'Counts must be whole numbers.' }
            $status='Known'
        }
        [pscustomobject]@{Id=$definition.Id;Value=$value;Status=$status;Unit=$definition.Unit;Note=$definition.Note}
    })
    $configurationRows=@(foreach ($id in @($Configuration.Keys | Sort-Object)) {
        $observation=$Configuration[$id]
        $value=$null
        if ($observation.State -eq 'Known') { $value=[string]$observation.Value }
        [pscustomobject]@{Id=[string]$id;State=[string]$observation.State;Value=$value;Source=[string]$observation.Source}
    })
    $drivers=@()
    if ($null -ne $SystemInfo.PSObject.Properties['GPUDetails']) { $drivers=@($SystemInfo.GPUDetails | ForEach-Object { [pscustomobject]@{Name=[string]$_.Name;DriverVersion=[string]$_.DriverVersion} }) }
    $record=[pscustomobject]@{
        SchemaVersion=1;Kind='PerformanceSnapshot';Id=[guid]::NewGuid().ToString('N');DerivedFrom=''
        CapturedUtc=[DateTime]::UtcNow.ToString('o');Label=$Label;Origin=$Origin;Context=$Context
        Hardware=[pscustomobject]@{OS=$SystemInfo.OS;Build=$SystemInfo.Build;CPU=$SystemInfo.CPU;GPU=$SystemInfo.GPU;RAM=$SystemInfo.RAM;GPUDrivers=$drivers}
        Sampling=$Sampling;Metrics=$metrics;Configuration=$configurationRows;Benchmark=$null;BenchmarkImportedUtc=$null
        Caveat='Resource/configuration differences are descriptive snapshots, not proof of FPS improvement or causation.'
    }
    Assert-ToolkitPerformanceSnapshot -Snapshot $record
    $record
}

function Get-ToolkitPerformanceSnapshot {
    [CmdletBinding()]
    param([ValidateLength(1,80)][string]$Label='Custom',[ValidateRange(1,15)][int]$SampleCount=3,
          [ValidateRange(1,5)][int]$SampleInterval=1)
    if (($SampleCount-1)*$SampleInterval -gt 30) { throw 'Sampling wait must not exceed 30 seconds.' }
    $system=Get-ToolkitSystemInfo
    $started=[DateTime]::UtcNow
    $values=@{};$cpu=@();$configuration=@{}
    if ($system.IsWindows) {
        for ($i=0;$i -lt $SampleCount;$i++) {
            try {
                $reading=@(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -OperationTimeoutSec 5 -ErrorAction Stop)
                if ($reading.Count -eq 1) { $cpu+=ConvertTo-ToolkitNumber -Value $reading[0].PercentProcessorTime -Maximum 100 }
            } catch { }
            if ($i -lt $SampleCount-1) { Start-Sleep -Seconds $SampleInterval }
        }
        if ($cpu.Count -gt 0) { $values.CpuPercent=($cpu | Measure-Object -Average).Average }
        try {
            $os=Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop
            $total=ConvertTo-ToolkitNumber -Value $os.TotalVisibleMemorySize -Minimum 1
            $free=ConvertTo-ToolkitNumber -Value $os.FreePhysicalMemory -Maximum $total
            $values.TotalMemoryMB=$total/1024;$values.AvailableMemoryMB=$free/1024
            $values.MemoryUsedPercent=100*($total-$free)/$total
            $uptime=([DateTime]::UtcNow-([DateTime]$os.LastBootUpTime).ToUniversalTime()).TotalSeconds
            if ($uptime -ge 0) { $values.UptimeSeconds=$uptime }
        } catch { }
        try { $values.ProcessCount=@(Get-Process -ErrorAction Stop).Count } catch { }
        try { $values.StartupCommandCount=@(Get-CimInstance -ClassName Win32_StartupCommand -OperationTimeoutSec 5 -ErrorAction Stop).Count } catch { }
        $configuration=Get-ToolkitObservations -SystemInfo $system
        foreach ($id in @('mouse','animations')) {
            try {
                $native=Get-ToolkitNativeState -OperationId $id
                if ($native.State -eq 'Known') {
                    $nativeValue=ConvertTo-ToolkitOperationValue -OperationId $id -Value $native.Value
                    foreach ($property in $nativeValue.PSObject.Properties) {
                        $configuration['native.'+$id+'.'+$property.Name]=[pscustomobject]@{State='Known';Value=$property.Value;Source=$native.Source}
                    }
                } else { $configuration['native.'+$id]=[pscustomobject]@{State=$native.State;Value=$null;Source=$native.Source} }
            } catch { $configuration['native.'+$id]=[pscustomobject]@{State='Error';Value=$null;Source='Native API read/validation failed'} }
        }
    }
    $configuration['power-plan']=[pscustomobject]@{State=$(if ($system.PowerPlan -eq 'Unavailable') {'Missing'} else {'Known'});Value=$system.PowerPlan;Source='Win32_PowerPlan active plan'}
    $sampling=[pscustomobject]@{
        RequestedCount=$SampleCount;CollectedCount=$cpu.Count;IntervalSeconds=$SampleInterval
        StartedUtc=$started.ToString('o');FinishedUtc=[DateTime]::UtcNow.ToString('o')
        CpuMinimum=$(if ($cpu.Count -gt 0) {($cpu | Measure-Object -Minimum).Minimum} else {$null})
        CpuMaximum=$(if ($cpu.Count -gt 0) {($cpu | Measure-Object -Maximum).Maximum} else {$null})
    }
    $origin=if ($system.IsWindows) {'Native'} else {'Preview'}
    New-ToolkitPerformanceSnapshot -SystemInfo $system -Values $values -Configuration $configuration -Context (Get-ToolkitPerformanceContext) -Sampling $sampling -Label $Label -Origin $origin
}

function Assert-ToolkitPerformanceSnapshot {
    param([Parameter(Mandatory)]$Snapshot)
    if ($Snapshot.SchemaVersion -ne 1 -or $Snapshot.Kind -cne 'PerformanceSnapshot' -or $Snapshot.Id -notmatch '^[a-f0-9]{32}$' -or $Snapshot.Origin -notin @('Native','Preview','Fixture')) { throw 'Invalid performance snapshot schema.' }
    if ($Snapshot.Label -isnot [string] -or $Snapshot.Label.Length -lt 1 -or $Snapshot.Label.Length -gt 80 -or $Snapshot.Label -match '[\x00-\x1F]') { throw 'Invalid measurement label.' }
    $null=[DateTime]::Parse($Snapshot.CapturedUtc)
    foreach ($key in @('Machine','User','Platform')) { if ([string]::IsNullOrWhiteSpace([string]$Snapshot.Context.$key)) { throw 'Missing measurement context.' } }
    $build=ConvertTo-ToolkitNumber -Value $Snapshot.Hardware.Build -Maximum 999999
    if ($build -ne [Math]::Floor($build)) { throw 'Invalid OS build.' }
    foreach ($key in @('OS','CPU','GPU','RAM')) { if ($Snapshot.Hardware.$key -isnot [string] -or $Snapshot.Hardware.$key.Length -gt 1024) { throw 'Invalid hardware metadata.' } }
    if (@($Snapshot.Hardware.GPUDrivers).Count -gt 16) { throw 'Invalid GPU driver list.' }
    foreach ($driver in @($Snapshot.Hardware.GPUDrivers)) {
        if ($driver.Name -isnot [string] -or $driver.Name.Length -gt 512 -or $driver.DriverVersion -isnot [string] -or $driver.DriverVersion.Length -gt 128) { throw 'Invalid GPU driver metadata.' }
    }
    $seen=@{}
    foreach ($metric in @($Snapshot.Metrics)) {
        $definition=@(Get-ToolkitMetricDefinitions | Where-Object {$_.Id -eq $metric.Id})
        if ($definition.Count -ne 1 -or $seen.ContainsKey($metric.Id) -or $metric.Unit -cne $definition[0].Unit -or $metric.Status -notin @('Known','Unavailable')) { throw 'Invalid or duplicate measurement metric.' }
        $seen[$metric.Id]=$true
        if ($metric.Status -eq 'Known') {
            $value=ConvertTo-ToolkitNumber -Value $metric.Value -Maximum $definition[0].Maximum
            if ($metric.Unit -eq 'count' -and $value -ne [Math]::Floor($value)) { throw 'Fractional process/startup count rejected.' }
        } elseif ($null -ne $metric.Value) { throw 'Unavailable metric must not contain a numeric value.' }
    }
    if ($seen.Count -ne 7) { throw 'Incomplete metric set.' }
    $requested=ConvertTo-ToolkitNumber -Value $Snapshot.Sampling.RequestedCount -Minimum 1 -Maximum 15
    $collected=ConvertTo-ToolkitNumber -Value $Snapshot.Sampling.CollectedCount -Maximum $requested
    if ($requested -ne [Math]::Floor($requested) -or $collected -ne [Math]::Floor($collected)) { throw 'Invalid sample counts.' }
    $interval=ConvertTo-ToolkitNumber -Value $Snapshot.Sampling.IntervalSeconds -Minimum 1 -Maximum 5
    if ($interval -ne [Math]::Floor($interval) -or ($requested-1)*$interval -gt 30) { throw 'Invalid sampling interval/window.' }
    $start=[DateTime]::Parse($Snapshot.Sampling.StartedUtc);$end=[DateTime]::Parse($Snapshot.Sampling.FinishedUtc)
    if ($end -lt $start) { throw 'Invalid sampling timestamps.' }
    $cpuMetric=@($Snapshot.Metrics | Where-Object {$_.Id -eq 'CpuPercent'})[0]
    if (($cpuMetric.Status -eq 'Known') -ne ($collected -gt 0)) { throw 'CPU value and sample count disagree.' }
    if ($collected -gt 0) {
        $minimum=ConvertTo-ToolkitNumber -Value $Snapshot.Sampling.CpuMinimum -Maximum 100
        $maximum=ConvertTo-ToolkitNumber -Value $Snapshot.Sampling.CpuMaximum -Maximum 100
        if ($minimum -gt $maximum -or [double]$cpuMetric.Value -lt $minimum -or [double]$cpuMetric.Value -gt $maximum) { throw 'CPU sample range does not contain its mean.' }
    }

    $seen=@{}
    if (@($Snapshot.Configuration).Count -gt 128) { throw 'Too many configuration entries.' }
    foreach ($row in @($Snapshot.Configuration)) {
        if ($row.Id -isnot [string] -or $row.Id.Length -gt 128 -or $seen.ContainsKey($row.Id) -or $row.State -notin @('Known','Missing','Error','Unsupported')) { throw 'Invalid configuration observation.' }
        $seen[$row.Id]=$true
        if ($null -ne $row.Value -and ($row.Value -isnot [string] -or $row.Value.Length -gt 512)) { throw 'Invalid configuration value.' }
        if ($row.State -ne 'Known' -and $null -ne $row.Value) { throw 'Unknown configuration cannot contain a known value.' }
    }
    if ($null -ne $Snapshot.Benchmark) { $null=ConvertTo-ToolkitBenchmark -InputObject $Snapshot.Benchmark }
}

function Save-ToolkitPerformanceSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)]$Snapshot)
    Assert-ToolkitPerformanceSnapshot -Snapshot $Snapshot
    $path=Join-Path (Join-Path $Directory 'Measurements') ($Snapshot.Id+'.json')
    if (Test-Path -LiteralPath $path) { throw 'Measurement IDs are immutable; choose a new snapshot ID.' }
    Write-ToolkitDocument -Path $path -Value $Snapshot
    [pscustomobject]@{Id=$Snapshot.Id;Label=$Snapshot.Label;CapturedUtc=$Snapshot.CapturedUtc;Path=$path}
}

function Read-ToolkitPerformanceSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$Id,$Context)
    if ($Id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid measurement ID.' }
    if ($null -eq $Context) { $Context=Get-ToolkitPerformanceContext }
    $record=Read-ToolkitDocument -Path (Join-Path (Join-Path $Directory 'Measurements') ($Id+'.json'))
    Assert-ToolkitPerformanceSnapshot -Snapshot $record
    if ($record.Id -cne $Id) { throw 'Measurement filename/ID mismatch.' }
    foreach ($key in @('Machine','User','Platform')) { if ($record.Context.$key -cne $Context.$key) { throw 'Measurement belongs to a different machine, user, or platform.' } }
    $record
}

function Get-ToolkitPerformanceHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,$Context)
    $folder=Join-Path $Directory 'Measurements'
    if (-not (Test-Path -LiteralPath $folder)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.json' | Sort-Object LastWriteTime -Descending)) {
        try { Read-ToolkitPerformanceSnapshot -Directory $Directory -Id $file.BaseName -Context $Context }
        catch { Write-Warning "Skipped invalid/incompatible measurement $($file.BaseName)." }
    }
}

function Add-ToolkitBenchmarkToSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Snapshot,[Parameter(Mandatory)][string]$Path)
    Assert-ToolkitPerformanceSnapshot -Snapshot $Snapshot
    $copy=$Snapshot | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $copy.DerivedFrom=$Snapshot.Id;$copy.Id=[guid]::NewGuid().ToString('N')
    $copy.Benchmark=Import-ToolkitBenchmark -Path $Path
    $copy.BenchmarkImportedUtc=[DateTime]::UtcNow.ToString('o')
    Assert-ToolkitPerformanceSnapshot -Snapshot $copy
    $copy
}

Export-ModuleMember -Function Get-ToolkitPerformanceContext, Get-ToolkitMetricDefinitions, New-ToolkitPerformanceSnapshot, Get-ToolkitPerformanceSnapshot, Assert-ToolkitPerformanceSnapshot, Save-ToolkitPerformanceSnapshot, Read-ToolkitPerformanceSnapshot, Get-ToolkitPerformanceHistory, Add-ToolkitBenchmarkToSnapshot
