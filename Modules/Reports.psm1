Set-StrictMode -Version Latest

function Compare-ToolkitPerformance {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Before,[Parameter(Mandatory)]$After)
    Assert-ToolkitPerformanceSnapshot -Snapshot $Before
    Assert-ToolkitPerformanceSnapshot -Snapshot $After
    foreach ($key in @('Machine','User','Platform')) { if ($Before.Context.$key -cne $After.Context.$key) { throw 'Compare measurements from the same machine, Windows user, and platform.' } }
    $warnings=@('Resource snapshots are not controlled benchmarks. Deltas do not establish causation or FPS improvement.')
    if ($Before.Id -eq $After.Id) { $warnings+='The same measurement was selected for both sides.' }
    if ([DateTime]::Parse($After.CapturedUtc) -lt [DateTime]::Parse($Before.CapturedUtc)) { $warnings+='After capture predates Before; check selected IDs.' }
    if ($Before.Origin -ne 'Native' -or $After.Origin -ne 'Native') { $warnings+='Fixture/preview data is present; this is not evidence of native Windows performance.' }
    $hardwareChanged=$false;$hardwareComplete=$true
    foreach ($key in @('OS','Build','CPU','GPU','RAM')) {
        if ([string]$Before.Hardware.$key -cne [string]$After.Hardware.$key) { $warnings+="Hardware/OS metadata differs: $key"; $hardwareChanged=$true }
        if ([string]$Before.Hardware.$key -eq 'Unavailable' -or [string]$After.Hardware.$key -eq 'Unavailable') { $warnings+="Hardware metadata unavailable: $key";$hardwareComplete=$false }
    }
    $beforeDrivers=(@($Before.Hardware.GPUDrivers | Sort-Object Name,DriverVersion | ForEach-Object { $_.Name+' / '+$_.DriverVersion }) -join '; ')
    $afterDrivers=(@($After.Hardware.GPUDrivers | Sort-Object Name,DriverVersion | ForEach-Object { $_.Name+' / '+$_.DriverVersion }) -join '; ')
    if ($beforeDrivers -cne $afterDrivers) {$hardwareChanged=$true;$warnings+='GPU driver versions differ.'}
    if (@($Before.Hardware.GPUDrivers).Count -eq 0 -or @($After.Hardware.GPUDrivers).Count -eq 0 -or @(@($Before.Hardware.GPUDrivers)+@($After.Hardware.GPUDrivers) | Where-Object {[string]::IsNullOrWhiteSpace($_.DriverVersion)}).Count -gt 0) {$hardwareComplete=$false;$warnings+='GPU driver metadata is incomplete.'}
    if ([int]$Before.Hardware.Build -le 0 -or [int]$After.Hardware.Build -le 0) {$hardwareComplete=$false}
    if ($Before.Sampling.CollectedCount -lt $Before.Sampling.RequestedCount -or $After.Sampling.CollectedCount -lt $After.Sampling.RequestedCount) { $warnings+='CPU sampling is incomplete; mean values use successful samples only.' }
    if ($Before.Sampling.RequestedCount -ne $After.Sampling.RequestedCount -or $Before.Sampling.IntervalSeconds -ne $After.Sampling.IntervalSeconds) { $warnings+='Sampling settings differ between captures.' }
    $metrics=@(foreach ($definition in Get-ToolkitMetricDefinitions) {
        $b=@($Before.Metrics | Where-Object {$_.Id -eq $definition.Id})[0]
        $a=@($After.Metrics | Where-Object {$_.Id -eq $definition.Id})[0]
        $known=$b.Status -eq 'Known' -and $a.Status -eq 'Known'
        $delta=$null;$percent=$null
        if ($known) {
            $delta=[double]$a.Value-[double]$b.Value
            if ([double]$b.Value -ne 0) { $percent=100*$delta/[double]$b.Value }
        }
        [pscustomobject]@{Category='Resources';Metric=$definition.Id;Before=$b.Value;After=$a.Value;Delta=$delta;PercentChange=$percent;Unit=$definition.Unit;Status=$(if ($known) {'Observed'} else {'NotMeasured'});Notes=$definition.Note}
    })
    $beforeConfig=@{};$afterConfig=@{}
    foreach ($row in @($Before.Configuration)) { $beforeConfig[$row.Id]=$row }
    foreach ($row in @($After.Configuration)) { $afterConfig[$row.Id]=$row }
    $configuration=@(foreach ($id in @(@($beforeConfig.Keys)+@($afterConfig.Keys) | Sort-Object -Unique)) {
        $b=$null;$a=$null
        if ($beforeConfig.ContainsKey($id)) { $b=$beforeConfig[$id] }
        if ($afterConfig.ContainsKey($id)) { $a=$afterConfig[$id] }
        $known=$null -ne $b -and $null -ne $a -and $b.State -eq 'Known' -and $a.State -eq 'Known'
        [pscustomobject]@{Category='Configuration';Metric=$id;Before=$(if ($null -ne $b) {$b.Value} else {$null});After=$(if ($null -ne $a) {$a.Value} else {$null});Delta=$null;PercentChange=$null;Unit='setting';Status=$(if (-not $known) {'Unknown'} elseif ($b.Value -ceq $a.Value) {'Unchanged'} else {'Changed'});Notes='Stored/native configuration observation only. A change is not a measured performance gain.'}
    })
    $conditionsMatch=$null -ne $Before.Benchmark -and $null -ne $After.Benchmark -and -not $hardwareChanged -and $hardwareComplete
    $benchmarkReason='User-supplied external benchmark results; matching declared conditions do not prove the toolkit caused a difference.'
    if ($conditionsMatch) {
        foreach ($key in @('game','scenario','resolution','qualityPreset','tool','toolVersion','durationSeconds','runCount')) {
            if ([string]$Before.Benchmark.$key -cne [string]$After.Benchmark.$key) { $conditionsMatch=$false }
        }
        if (-not $conditionsMatch) { $benchmarkReason='Declared benchmark conditions differ; deltas suppressed.' }
    } elseif ($hardwareChanged) { $benchmarkReason='Hardware/OS metadata differs; benchmark deltas suppressed.' }
    elseif (-not $hardwareComplete) { $benchmarkReason='Hardware/driver metadata is incomplete; benchmark deltas suppressed.' }
    else { $benchmarkReason='Both sides require real imported measurements; absent metrics are not zero.' }
    $benchmarks=@(foreach ($key in @('averageFps','onePercentLowFps','meanFrameTimeMs')) {
        $b=$null;$a=$null;$delta=$null;$percent=$null
        if ($null -ne $Before.Benchmark) { $b=$Before.Benchmark.$key }
        if ($null -ne $After.Benchmark) { $a=$After.Benchmark.$key }
        $status='NotMeasured'
        if ($null -ne $b -and $null -ne $a) {
            $status='DifferentConditions'
            if ($conditionsMatch) { $status='ImportedComparison';$delta=[double]$a-[double]$b;$percent=100*$delta/[double]$b }
        }
        [pscustomobject]@{Category='ExternalBenchmark';Metric=$key;Before=$b;After=$a;Delta=$delta;PercentChange=$percent;Unit=$(if ($key -eq 'meanFrameTimeMs') {'ms'} else {'FPS'});Status=$status;Notes=$benchmarkReason}
    })
    # Reports intentionally omit SID/machine name and raw source paths. Hardware,
    # user-entered labels and benchmark conditions remain visible for review.
    [pscustomobject]@{
        SchemaVersion=1;Kind='PerformanceComparison';CreatedUtc=[DateTime]::UtcNow.ToString('o')
        Before=[pscustomobject]@{Id=$Before.Id;Label=$Before.Label;CapturedUtc=$Before.CapturedUtc;Origin=$Before.Origin;Hardware=$Before.Hardware;Sampling=$Before.Sampling;Benchmark=$Before.Benchmark}
        After=[pscustomobject]@{Id=$After.Id;Label=$After.Label;CapturedUtc=$After.CapturedUtc;Origin=$After.Origin;Hardware=$After.Hardware;Sampling=$After.Sampling;Benchmark=$After.Benchmark}
        Warnings=$warnings;Metrics=$metrics;Configuration=$configuration;Benchmarks=$benchmarks
        Interpretation='Descriptive comparison only. Fewer processes or lower idle RAM do not establish higher gaming FPS. Repeat controlled benchmarks; no significance or causation is inferred.'
    }
}

function ConvertTo-ToolkitMarkdownCell {
    param($Value)
    if ($null -eq $Value) { return 'Not measured' }
    $text=if ($Value -is [double] -or $Value -is [decimal]) { $Value.ToString('0.###',[Globalization.CultureInfo]::InvariantCulture) } else { [string]$Value }
    $text=$text -replace '[\r\n]',' '
    [regex]::Replace($text,'([\\`*_{}\[\]<>|])','\$1')
}

function ConvertTo-ToolkitCsvCell {
    param($Value)
    if ($Value -is [ValueType] -and $Value -isnot [bool]) { return [Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [string] -and $Value -match '^[\s\uFEFF]*[=+\-@]') { return "'"+$Value }
    $Value
}

function Export-ToolkitPerformanceReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Report,[Parameter(Mandatory)][string]$Path,
          [ValidateSet('JSON','Markdown','CSV')][string]$Format='Markdown')
    if ($Report.Kind -ne 'PerformanceComparison' -or $Report.SchemaVersion -ne 1) { throw 'Invalid comparison report.' }
    $rows=@($Report.Metrics)+@($Report.Configuration)+@($Report.Benchmarks)
    switch ($Format) {
        'JSON' { $content=$Report | ConvertTo-Json -Depth 20 }
        'CSV' {
            $csvRows=@([pscustomobject]@{Category='Context';Metric='Before capture';Before=$Report.Before.Label;After=$Report.Before.CapturedUtc;Delta=$null;PercentChange=$null;Unit='UTC';Status=$Report.Before.Origin;Notes=$Report.Before.Id},
                [pscustomobject]@{Category='Context';Metric='After capture';Before=$Report.After.Label;After=$Report.After.CapturedUtc;Delta=$null;PercentChange=$null;Unit='UTC';Status=$Report.After.Origin;Notes=$Report.After.Id})
            foreach ($group in @('Hardware','Sampling','Benchmark')) {
                $keys=switch ($group) { 'Hardware' {@('OS','Build','CPU','GPU','RAM')} 'Sampling' {@('RequestedCount','CollectedCount','IntervalSeconds','CpuMinimum','CpuMaximum')} 'Benchmark' {@('game','scenario','resolution','qualityPreset','tool','toolVersion','durationSeconds','runCount')} }
                foreach ($key in $keys) {
                    $beforeValue=$null;$afterValue=$null
                    if ($null -ne $Report.Before.$group) {$beforeValue=$Report.Before.$group.$key}
                    if ($null -ne $Report.After.$group) {$afterValue=$Report.After.$group.$key}
                    $csvRows+=[pscustomobject]@{Category='Context';Metric=$group+'.'+$key;Before=$beforeValue;After=$afterValue;Delta=$null;PercentChange=$null;Unit='metadata';Status='Context';Notes='Declared capture/benchmark context.'}
                }
            }
            $csvRows+=[pscustomobject]@{Category='Context';Metric='Hardware.GPUDrivers';Before=(@($Report.Before.Hardware.GPUDrivers | ForEach-Object {$_.Name+' / '+$_.DriverVersion}) -join '; ');After=(@($Report.After.Hardware.GPUDrivers | ForEach-Object {$_.Name+' / '+$_.DriverVersion}) -join '; ');Delta=$null;PercentChange=$null;Unit='metadata';Status='Context';Notes='Captured GPU driver versions.'}
            foreach ($row in $rows) { $csvRows+=$row }
            foreach ($warning in @($Report.Warnings)+@($Report.Interpretation)) { $csvRows+=[pscustomobject]@{Category='Caveat';Metric='Interpretation';Before=$null;After=$null;Delta=$null;PercentChange=$null;Unit='';Status='Note';Notes=$warning} }
            $safeRows=@(foreach ($row in $csvRows) {
                $safe=[ordered]@{}
                foreach ($key in @('Category','Metric','Before','After','Delta','PercentChange','Unit','Status','Notes')) { $safe[$key]=ConvertTo-ToolkitCsvCell $row.$key }
                [pscustomobject]$safe
            })
            $content=($safeRows | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
        }
        'Markdown' {
            $lines=@('# Performance comparison','',('Before: '+(ConvertTo-ToolkitMarkdownCell $Report.Before.Label)+' / '+$Report.Before.CapturedUtc),('After: '+(ConvertTo-ToolkitMarkdownCell $Report.After.Label)+' / '+$Report.After.CapturedUtc),'', $Report.Interpretation,'','| Category | Metric | Before | After | Delta | Unit | Status |','| --- | --- | --- | --- | --- | --- | --- |')
            foreach ($row in $rows) { $cells=@($row.Category,$row.Metric,$row.Before,$row.After,$row.Delta,$row.Unit,$row.Status);$lines+=('| '+(@($cells | ForEach-Object {ConvertTo-ToolkitMarkdownCell $_}) -join ' | ')+' |') }
            $lines+=@('','Delta is After minus Before. Percent-valued resource deltas are percentage points, not relative percentages.','')
            foreach ($warning in $Report.Warnings) { $lines+='- '+(ConvertTo-ToolkitMarkdownCell $warning) }
            foreach ($side in @('Before','After')) {
                $lines+=@('',('## '+$side+' context'),'')
                foreach ($key in @('OS','Build','CPU','GPU','RAM')) { $lines+=('- '+$key+': '+(ConvertTo-ToolkitMarkdownCell $Report.$side.Hardware.$key)) }
                foreach ($key in @('RequestedCount','CollectedCount','IntervalSeconds','CpuMinimum','CpuMaximum')) { $lines+=('- Sampling '+$key+': '+(ConvertTo-ToolkitMarkdownCell $Report.$side.Sampling.$key)) }
                foreach ($driver in @($Report.$side.Hardware.GPUDrivers)) { $lines+=('- GPU driver: '+(ConvertTo-ToolkitMarkdownCell ($driver.Name+' / '+$driver.DriverVersion))) }
                if ($null -ne $Report.$side.Benchmark) {
                    foreach ($key in @('game','scenario','resolution','qualityPreset','tool','toolVersion','durationSeconds','runCount')) { $lines+=('- '+$key+': '+(ConvertTo-ToolkitMarkdownCell $Report.$side.Benchmark.$key)) }
                }
            }
            $content=$lines -join [Environment]::NewLine
        }
    }
    $full=[IO.Path]::GetFullPath($Path)
    if ([IO.File]::Exists($full)) { throw 'Report path already exists; choose a new filename.' }
    $null=New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force -ErrorAction Stop
    $stream=$null
    try {
        $stream=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $bytes=[Text.Encoding]::UTF8.GetBytes($content);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    $full
}

Export-ModuleMember -Function Compare-ToolkitPerformance, Export-ToolkitPerformanceReport
