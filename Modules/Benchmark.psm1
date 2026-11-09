Set-StrictMode -Version Latest

function ConvertTo-ToolkitNumber {
    param([Parameter(Mandatory)]$Value,[double]$Minimum=0,[double]$Maximum=1e12)
    $number=0.0
    $text=if ($Value -is [string]) { $Value } else { [Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [bool] -or -not [double]::TryParse($text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or
        [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt $Minimum -or $number -gt $Maximum) { throw 'Invalid or out-of-range numeric measurement.' }
    $number
}

function ConvertTo-ToolkitBenchmark {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$InputObject)
    if ([string]$InputObject.schemaVersion -cne '1') { throw 'Unsupported benchmark summary schema.' }
    $record=[ordered]@{schemaVersion=1}
    foreach ($name in @('game','scenario','resolution','qualityPreset','tool','toolVersion')) {
        $property=$InputObject.PSObject.Properties[$name]
        if ($null -eq $property -or $property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($property.Value) -or $property.Value.Length -gt 160 -or $property.Value -match '[\x00-\x1F]') { throw "Invalid benchmark metadata: $name" }
        $record[$name]=$property.Value.Trim()
    }
    $record.durationSeconds=ConvertTo-ToolkitNumber -Value $InputObject.durationSeconds -Minimum 0.001 -Maximum 86400
    $runs=ConvertTo-ToolkitNumber -Value $InputObject.runCount -Minimum 1 -Maximum 1000
    if ($runs -ne [Math]::Floor($runs)) { throw 'runCount must be an integer.' }
    $record.runCount=[int]$runs
    $measured=0
    foreach ($name in @('averageFps','onePercentLowFps','meanFrameTimeMs')) {
        $record[$name]=$null
        $property=$InputObject.PSObject.Properties[$name]
        if ($null -ne $property -and $null -ne $property.Value -and [string]$property.Value -ne '') {
            $record[$name]=ConvertTo-ToolkitNumber -Value $property.Value -Minimum 0.000001 -Maximum 1e9
            $measured++
        }
    }
    if ($measured -eq 0) { throw 'A benchmark summary needs at least one measured FPS or frame-time metric.' }
    if ($null -ne $record.averageFps -and $null -ne $record.onePercentLowFps -and $record.onePercentLowFps -gt $record.averageFps) { throw '1% low FPS cannot exceed average FPS in this summary format.' }
    [pscustomobject]$record
}

function Import-ToolkitBenchmark {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Length -gt 1MB) { throw 'Benchmark summary exceeds 1 MiB.' }
    switch ($file.Extension.ToLowerInvariant()) {
        '.json' { $inputObject=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop }
        '.csv' {
            $rows=@(Import-Csv -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction Stop)
            if ($rows.Count -ne 1) { throw 'Use one normalized summary row, not raw per-frame or multi-run CSV.' }
            $inputObject=$rows[0]
        }
        default { throw 'Supported imports: normalized summary .json or single-row .csv. Files are data only.' }
    }
    ConvertTo-ToolkitBenchmark -InputObject $inputObject
}

Export-ModuleMember -Function ConvertTo-ToolkitNumber, ConvertTo-ToolkitBenchmark, Import-ToolkitBenchmark
