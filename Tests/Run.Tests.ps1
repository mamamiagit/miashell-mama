#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$count = 0
function Assert-That([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:count++
    Write-Host "PASS: $Message"
}
# Parse every PowerShell source, including entry points, before executing it.
foreach ($file in Get-ChildItem $root -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.psm1') }) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    Assert-That (@($errors).Count -eq 0) "PowerShell parses: $($file.Name)"
}
foreach ($module in @('SystemInfo','Optimization','Logging','Backup','Restore')) {
    Import-Module (Join-Path $root "Modules/$module.psm1") -Force
}
$catalog = Get-ToolkitCatalog -Root $root
Assert-That ($catalog.Profiles.Count -eq 7) 'All seven profiles load'
Assert-That ($catalog.Items.Count -eq 18) 'Catalog contains 18 individual optimization objects'
# Reproduce Windows PowerShell 5.1's non-enumerated JSON-array output even on 7.
function global:ConvertFrom-Json {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline=$true)][string]$InputObject)
    process {
        $parsed = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $InputObject
        Write-Output -NoEnumerate $parsed
    }
}
try {
    $legacyCatalog = Get-ToolkitCatalog -Root $root
    Assert-That ($legacyCatalog.Items.Count -eq 18) 'Legacy JSON-array output is flattened correctly'
    Assert-That ($legacyCatalog.Items[0].id -is [string] -and $legacyCatalog.Items[0].id -eq 'game-mode') 'Legacy catalog entries have scalar IDs'
    Assert-That ($legacyCatalog.Profiles.Count -eq 7) 'Legacy JSON output preserves all profiles'
} finally { Remove-Item Function:/ConvertFrom-Json }

$profile = $catalog.Profiles | Where-Object { $_.id -eq 'custom' }
$windows11 = [pscustomobject]@{ IsWindows=$true; Build=22631 }
$windows10 = [pscustomobject]@{ IsWindows=$true; Build=19045 }
$linux = [pscustomobject]@{ IsWindows=$false; Build=0 }
$selection = @(New-ToolkitSelection -Profile $profile -Items $catalog.Items -SystemInfo $windows11)
Assert-That (@($selection | Where-Object { $_.Definition.experimental -and ($_.Selected -or $_.CanSelect) }).Count -eq 0) 'Experimental settings cannot be selected'
$old = @(New-ToolkitSelection -Profile $profile -Items $catalog.Items -SystemInfo $windows10)
$widgets = $old | Where-Object { $_.Definition.id -eq 'widgets' }
Assert-That (-not $widgets.CanSelect -and -not $widgets.Selected) 'Windows 11-only setting blocked on Windows 10'
$preview = @(New-ToolkitSelection -Profile $profile -Items $catalog.Items -SystemInfo $linux)
Assert-That (@($preview | Where-Object { $_.Selected -or $_.CanSelect }).Count -eq 0) 'Non-Windows host cannot select Windows actions'
$results = @(Invoke-ToolkitSimulation -Selection $selection)
Assert-That ($results.Count -gt 0) 'Simulation produces selected-item results'
Assert-That (@($results | Where-Object { $_.ChangedWindows -or $_.Status -ne 'SIMULATED' }).Count -eq 0) 'Simulation never claims real changes'
Assert-That (@(Invoke-ToolkitSimulation -Selection @()).Count -eq 0) 'Empty selection is harmless'
$blocked = $selection | Where-Object { $_.Definition.id -eq 'cpu-priority' }
$blocked.Selected = $true
$rejected = $false
try { $null = Invoke-ToolkitSimulation -Selection @($blocked) } catch { $rejected = $true }
Assert-That $rejected 'Forged experimental selection rejected by engine'
Assert-That (-not (Get-ToolkitBackupStatus).Available -and -not (Get-ToolkitRestoreStatus).Available) 'Backup and restore do not imply real functionality'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('toolkit-tests-' + [guid]::NewGuid().ToString('N'))
try {
    $path = Save-ToolkitSimulation -Directory $temp -ProfileId 'custom' -Results $results
    Assert-That (Test-Path -LiteralPath $path) 'Optional simulation log saved'
    $history = @(Get-ToolkitSimulationHistory -Directory $temp)
    Assert-That ($history.Count -eq 1 -and $history[0].SimulationOnly) 'Simulation history round-trips'
    $rejected = $false
    try { $null = Save-ToolkitSimulation -Directory $temp -ProfileId 'bad' -Results @([pscustomobject]@{ ChangedWindows=$true; Status='OK' }) } catch { $rejected=$true }
    Assert-That $rejected 'History rejects real-change records'
} finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
# Exercise the real entry point from a different working directory. This also
# runs under Windows PowerShell 5.1 in CI, where parameter defaults differ.
$startupTemp = Join-Path ([IO.Path]::GetTempPath()) ('toolkit-startup-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $startupTemp
Push-Location $startupTemp
try {
    $dashboard = (& (Join-Path $root 'Start.ps1') -Preview 6>&1 | Out-String)
    Assert-That ($dashboard.Contains('DASHBOARD / v0.1.0')) 'Entry point resolves default data directory after parameter binding'
    $dashboard = (& (Join-Path $root 'Start.ps1') -Preview -DataDirectory (Join-Path $startupTemp 'custom') 6>&1 | Out-String)
    Assert-That ($dashboard.Contains('SIMULATION ONLY')) 'Entry point accepts explicit data directory'
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $startupTemp 'custom'))) 'Preview does not create a data directory'
} finally {
    Pop-Location
    Remove-Item -LiteralPath $startupTemp -Recurse -Force
}
$system = Get-ToolkitSystemInfo
Assert-That ($null -ne $system.OS -and $null -ne $system.Warnings) 'System detection returns a complete result'
# Prevent accidental introduction of actual Windows mutations or command dispatch.
$forbidden = @('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Remove-AppxPackage','Remove-AppxProvisionedPackage','Set-Service','Stop-Service','Disable-ScheduledTask','Invoke-Expression','Start-Process','reg.exe','powercfg.exe')
foreach ($file in Get-ChildItem (Join-Path $root 'Modules') -Filter '*.psm1') {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
    $commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true))
    $violations = @($commands | Where-Object {
        $name = $_.GetCommandName()
        $null -eq $name -or $name -in $forbidden
    })
    Assert-That ($violations.Count -eq 0) "No listed Windows mutations or dynamic dispatch: $($file.Name)"
}
Write-Host "`n$count assertions passed. Windows-specific hardware queries still require testing on Windows."
