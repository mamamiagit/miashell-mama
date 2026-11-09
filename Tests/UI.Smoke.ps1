#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($name in @('SystemInfo','Detection','Recommendation','NativeSettings','Engine','Optimization','Logging','Backup','Transactions','Restore','Interface')) {
    Import-Module (Join-Path $root "Modules/$name.psm1") -Force
}
$catalog = Get-ToolkitCatalog -Root $root
$catalog.Profiles = @($catalog.Profiles | Sort-Object @{Expression = { if ($_.id -eq 'balanced') { 0 } else { 1 } }}, title)
$settings = Get-Content -LiteralPath (Join-Path $root 'Config/Settings.json') -Raw | ConvertFrom-Json
# Fixture only: this does not claim to test real Windows hardware discovery.
$fixture = [pscustomobject]@{
    IsWindows=$true; Build=22631; OS='Windows 11 fixture'; CPU='Fixture CPU'
    GPU='Fixture GPU'; RAM='16 GB'; Storage='Fixture disk'; PowerPlan='Balanced'
    Administrator=$false; GamingSettings='Fixture preferences'; Warnings=@()
}
$observations = @{ 'game-mode' = [pscustomobject]@{State='Known';Value=0;Source='Fixture';Detail='Test fixture'} }
$script:answers = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($answer in @('1','A','NO','I','1','','999','','A','SIMULATE','Y','','1','R','D','','V','S','2','I','1','','N','B','O','S','6','V','B','D','','H','','R','','C','','S','','INVALID','','0')) {
    $script:answers.Enqueue($answer)
}
function global:Read-Host {
    param([string]$Prompt)
    if ($script:answers.Count -eq 0) { throw "UI requested unexpected input: $Prompt" }
    $script:answers.Dequeue()
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('toolkit-ui-' + [guid]::NewGuid().ToString('N'))
try {
    $output = (& { Start-ToolkitInterface -Catalog $catalog -SystemInfo $fixture -Settings $settings -HistoryDirectory $temp -Observations $observations } 6>&1 | Out-String)
    if ($script:answers.Count -ne 0) { throw 'UI exited before consuming the expected navigation sequence.' }
    foreach ($expected in @('SIMULATION PREVIEW','[SIMULATED]','Invalid selection.','Invalid selection','SIMULATION HISTORY','RESTORATION','SETTINGS / ROADMAP','SYSTEM INFORMATION','OPTIMIZATION COMPARISON','Sort: Risk','Sort: Unsupported','ENGINE DRY RUN / NO CHANGES')) {
        if (-not $output.Contains($expected)) { throw "Missing UI output: $expected" }
    }
    $records = @(Get-ToolkitSimulationHistory -Directory $temp)
    if ($records.Count -ne 1 -or -not $records[0].SimulationOnly) { throw 'Expected exactly one saved simulation after cancellation and confirmation.' }
    if (@($records[0].Results).Count -eq 0) { throw 'Saved simulation unexpectedly empty.' }
    Write-Host 'PASS: UI navigation, cancellation, details, invalid input, reset, simulation confirmation, history, restore status and settings.'
} finally {
    Remove-Item Function:/Read-Host -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
