#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach ($name in @('Detection','Recommendation','Optimization')) { Import-Module (Join-Path $root "Modules/$name.psm1") -Force }
$count=0
function Assert-That([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:count++; Write-Host "PASS: $Message"
}
function Observation($Value,[string]$State='Known') { [pscustomobject]@{State=$State;Value=$Value;Source='Fixture';Detail='Fixture observation'} }
$catalog=Get-ToolkitCatalog -Root $root
$items=@{}; foreach ($item in $catalog.Items) { $items[$item.id]=$item }
$win=[pscustomobject]@{IsWindows=$true;Build=22631;ProductType=1;PowerPlan='Balanced';IsPortable=$true;GPUDetails=@([pscustomobject]@{Name='Fixture GPU';DriverVersion='1.2.3.4'})}
$old=[pscustomobject]@{IsWindows=$true;Build=19045;ProductType=1}
$server=[pscustomobject]@{IsWindows=$true;Build=22631;ProductType=3}
$off=Get-ToolkitRecommendation -Definition $items['game-mode'] -SystemInfo $win -Observations @{'game-mode'=(Observation 0)}
Assert-That ($off.Selected -and $off.RecommendedChange -and $off.CanSelect) 'Known disabled Game Mode is recommended for simulation'
$on=Get-ToolkitRecommendation -Definition $items['game-mode'] -SystemInfo $win -Observations @{'game-mode'=(Observation 1)}
Assert-That ($on.AlreadyApplied -and -not $on.Selected -and -not $on.CanSelect) 'Already configured Game Mode is skipped'
foreach ($state in @('Missing','Error')) {
    $entry=Get-ToolkitRecommendation -Definition $items['game-mode'] -SystemInfo $win -Observations @{'game-mode'=(Observation $null $state)}
    Assert-That (-not $entry.Selected -and -not $entry.CanSelect -and $entry.Availability -eq 'Unknown') "$state preference never becomes an assumed default"
}
$entry=Get-ToolkitRecommendation -Definition $items['game-mode'] -SystemInfo $win -Observations @{'game-mode'=(Observation 99)}
Assert-That (-not $entry.Selected -and $entry.Availability -eq 'Unknown') 'Unrecognized stored value is not recommended'
$entry=Get-ToolkitRecommendation -Definition $items['game-mode'] -SystemInfo $server -Observations @{'game-mode'=(Observation 0)}
Assert-That ($entry.Availability -eq 'Unsupported' -and -not $entry.Selected) 'Windows Server excluded'
$entry=Get-ToolkitRecommendation -Definition $items['widgets'] -SystemInfo $old
Assert-That ($entry.Availability -eq 'Unsupported') 'Widgets excluded on Windows 10'
$entry=Get-ToolkitRecommendation -Definition $items['game-mode'] -SystemInfo ([pscustomobject]@{IsWindows=$true;Build=0})
Assert-That ($entry.Availability -eq 'Unsupported') 'Unknown build cannot pass compatibility gate'
$entry=Get-ToolkitRecommendation -Definition $items['power'] -SystemInfo $win
Assert-That ($entry.CurrentState -eq 'Balanced' -and $entry.Reason.Contains('battery') -and -not $entry.Selected) 'Portable system preserves power plan and explains battery tradeoff'
foreach ($state in @('Known','Error')) {
    $entry=Get-ToolkitRecommendation -Definition $items['game-dvr'] -SystemInfo $win -Observations @{'game-dvr'=(Observation 1);'dvr-policy'=(Observation 0 $state)}
    Assert-That ($entry.Recommendation -eq 'Review policy' -and -not $entry.CanSelect) "$state administrative policy prevents conflicting recommendations"
}
$entry=Get-ToolkitRecommendation -Definition $items['game-dvr'] -SystemInfo $win -Observations @{'game-dvr'=(Observation 1);'dvr-policy'=(Observation $null 'Missing');'dvr-mdm'=(Observation 0)}
Assert-That ($entry.Recommendation -eq 'Review policy') 'MDM capture policy is checked separately'
$entry=Get-ToolkitRecommendation -Definition $items['game-dvr'] -SystemInfo $win -Observations @{'game-dvr'=(Observation 1);'dvr-background'=(Observation 0)}
Assert-That ($entry.CurrentState.Contains('background recording: 0') -and -not $entry.Selected) 'App capture is not confused with background recording'
$entry=Get-ToolkitRecommendation -Definition $items['active-hours'] -SystemInfo $win -Observations @{'active-start'=(Observation 8);'active-end'=(Observation 20)}
Assert-That ($entry.CurrentState.Contains('08:00 - 20:00') -and -not $entry.Selected) 'Active hours are read without disabling updates'
$entry=Get-ToolkitRecommendation -Definition $items['advertising'] -SystemInfo $win -Observations @{'advertising'=(Observation 1)}
Assert-That (-not $entry.Selected -and $entry.Reason.Contains('Privacy preference')) 'Privacy preference does not become an automatic performance tweak'
Assert-That ($entry.CanSelect -and -not $entry.RecommendedChange) 'Known optional preference can be chosen manually without automatic recommendation'
$entry.Selected=$true
$manual=@(Invoke-ToolkitSimulation -Selection @($entry))
Assert-That ($manual.Count -eq 1 -and $manual[0].Proposed -eq 'Advertising ID disabled' -and -not $manual[0].ChangedWindows) 'Manual preference simulation has an explicit target and changes nothing'
$selection=@($off,$on,(Get-ToolkitRecommendation -Definition $items['cpu-priority'] -SystemInfo $win), (Get-ToolkitRecommendation -Definition $items['hags'] -SystemInfo $win))
Assert-That (@(Get-ToolkitComparison -Selection $selection -SortBy Recommended)[0].RecommendedChange) 'Recommended sort places actionable suggestions first'
Assert-That (@(Get-ToolkitComparison -Selection $selection -SortBy Applied)[0].AlreadyApplied) 'Already configured sort uses observed state'
Assert-That (@(Get-ToolkitComparison -Selection $selection -SortBy Unsupported)[0].Availability -eq 'Unsupported') 'Unsupported sort places blocked settings first'
foreach ($sort in @('Recommended','Risk','Category','Restart','Applied','Unsupported')) {
    $sorted=@(Get-ToolkitComparison -Selection $selection -SortBy $sort)
    Assert-That ($sorted.Count -eq $selection.Count) "$sort sort preserves every setting"
}
$off.Selected=$false
Assert-That (@(Get-ToolkitComparison -Selection @($off) -SortBy Risk)[0].Selected -eq $false) 'Sorting preserves user selections'
# Test read outcomes without touching real registry settings, on Linux and Windows.
$script:readMode='Known'; $script:readCount=0
function global:Get-ItemProperty {
    [CmdletBinding()]
    param([string]$LiteralPath,[string]$Name)
    $script:readCount++
    switch ($script:readMode) {
        'Missing' { throw (New-Object System.Management.Automation.ItemNotFoundException 'Fixture missing') }
        'Denied' { throw (New-Object System.UnauthorizedAccessException 'Fixture denied') }
        default { $result=@{}; $result[$Name]=0; [pscustomobject]$result }
    }
}
try {
    foreach ($pair in @(@('Known','Known'),@('Missing','Missing'),@('Denied','Error'))) {
        $script:readMode=$pair[0]
        $read=Get-ToolkitRegistryValue -Path 'HKCU:\Fixture' -Name 'Flag'
        Assert-That ($read.State -eq $pair[1]) "Registry $($pair[0]) outcome represented honestly"
    }
    $script:readMode='Known'; $script:readCount=0
    $snapshot=Get-ToolkitObservations -SystemInfo $win
    Assert-That ($snapshot.Count -eq 18 -and $script:readCount -eq 18) 'All fixed registry reads run exactly once'
    $script:readCount=0
    $snapshot=Get-ToolkitObservations -SystemInfo ([pscustomobject]@{IsWindows=$false})
    Assert-That ($snapshot.Count -eq 0 -and $script:readCount -eq 0) 'Non-Windows snapshot never queries registry'
} finally { Remove-Item Function:/Get-ItemProperty }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('toolkit-capability-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $temp
try {
    $path=Join-Path $temp 'dxdiag.xml'
    $xml='<DxDiag><DisplayDevices><DisplayDevice><CardName>Fixture GPU</CardName><DriverVersion>1.2.3.4</DriverVersion><DriverModel>WDDM 3.1</DriverModel><HardwareScheduling>DriverSupportState:Stable Enabled:False</HardwareScheduling></DisplayDevice></DisplayDevices></DxDiag>'
    $xml | Set-Content -LiteralPath $path
    $support=Get-ToolkitHagsSupport -SystemInfo $win -DxDiagPath $path
    Assert-That ($support.State -eq 'Supported') 'Matching stable HAGS report is recognized'
    $win | Add-Member -NotePropertyName HagsSupport -NotePropertyValue $support
    $entry=Get-ToolkitRecommendation -Definition $items['hags'] -SystemInfo $win -Observations @{'hags'=(Observation 2)}
    Assert-That ($entry.Availability -eq 'Supported' -and -not $entry.Selected -and -not $entry.CanSelect) 'Even supported HAGS is experimental and never selected'
    $xml.Replace('1.2.3.4','9.9.9.9') | Set-Content -LiteralPath $path
    Assert-That ((Get-ToolkitHagsSupport -SystemInfo $win -DxDiagPath $path).State -eq 'Unknown') 'Stale driver report is rejected'
    $xml.Replace('DriverSupportState:Stable','DriverSupportState:NotSupported') | Set-Content -LiteralPath $path
    Assert-That ((Get-ToolkitHagsSupport -SystemInfo $win -DxDiagPath $path).State -eq 'Unsupported') 'Explicit unsupported HAGS report is respected'
    $xml.Replace('WDDM 3.1','WDDM 2.6') | Set-Content -LiteralPath $path
    Assert-That ((Get-ToolkitHagsSupport -SystemInfo $win -DxDiagPath $path).State -eq 'Unsupported') 'Pre-2.7 driver model is not HAGS capable'
    '<!DOCTYPE DxDiag [<!ENTITY x SYSTEM "file:///etc/passwd">]><DxDiag>&x;</DxDiag>' | Set-Content -LiteralPath $path
    Assert-That ((Get-ToolkitHagsSupport -SystemInfo $win -DxDiagPath $path).State -eq 'Unknown') 'XML external entities prohibited'
    'not XML' | Set-Content -LiteralPath $path
    Assert-That ((Get-ToolkitHagsSupport -SystemInfo $win -DxDiagPath $path).State -eq 'Unknown') 'Malformed XML safely degrades to unknown'
    Assert-That ((Get-ToolkitHagsSupport -SystemInfo $win).State -eq 'Unknown') 'GPU name alone cannot establish scheduling support'
    $multi=$win.PSObject.Copy()
    $multi.GPUDetails=@($win.GPUDetails[0], [pscustomobject]@{Name='Second GPU';DriverVersion='2.0'})
    $xml | Set-Content -LiteralPath $path
    Assert-That ((Get-ToolkitHagsSupport -SystemInfo $multi -DxDiagPath $path).State -eq 'Unknown') 'Unmatched second adapter prevents blanket support claim'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
Write-Host "`n$count recommendation assertions passed. Fixtures do not establish real Windows behavior."
