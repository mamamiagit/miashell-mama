#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach ($name in @('NativeSettings','Engine')) { Import-Module (Join-Path $root "Modules/$name.psm1") -Force }
$count=0
function Assert-That([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:count++; Write-Host "PASS: $Message"
}
function State($Value,[string]$Status='Known') { [pscustomobject]@{State=$Status;Value=$Value;Source='Fixture API';Detail='Fixture only'} }
$win=[pscustomobject]@{IsWindows=$true;Build=22631;ProductType=1;InteractiveSession=$true;Administrator=$false}
$snapshot=@{
    mouse=(State ([pscustomobject]@{Threshold1=6;Threshold2=10;Acceleration=2}))
    animations=(State ([pscustomobject]@{MinAnimate=1}))
}
$policy=Get-ToolkitExecutionPolicy
Assert-That (-not $policy.LiveChangesEnabled -and -not $policy.RollbackAvailable) 'Execution policy locks real writes pending rollback'
Assert-That ((Get-ToolkitOperationPermission -SystemInfo $win).Allowed) 'Current-user operations do not require elevation'
$service=$win.PSObject.Copy(); $service.InteractiveSession=$false
Assert-That (-not (Get-ToolkitOperationPermission -SystemInfo $service).Allowed) 'Session-zero/service operations are blocked'
$server=$win.PSObject.Copy(); $server.ProductType=3
Assert-That (-not (Get-ToolkitOperationPermission -SystemInfo $server).Allowed) 'Server excluded from engine'
$unknown=$win.PSObject.Copy(); $unknown.ProductType=0
Assert-That (-not (Get-ToolkitOperationPermission -SystemInfo $unknown).Allowed) 'Unknown product type excluded'
$plans=@(New-ToolkitExecutionPlan -OptimizationId @('mouse','animations','MOUSE') -SystemInfo $win -StateSnapshot $snapshot)
Assert-That ($plans.Count -eq 2) 'Duplicate operation IDs are normalized and removed'
Assert-That (@($plans | Where-Object { $_.Status -ne 'READY' }).Count -eq 0) 'Valid known settings produce ready dry-run plans'
Assert-That ($plans[0].Target.Threshold1 -eq 6 -and $plans[0].Target.Threshold2 -eq 10 -and $plans[0].Target.Acceleration -eq 0) 'Mouse target preserves both thresholds and disables only acceleration'
Assert-That ($plans[1].Target.MinAnimate -eq 0) 'Animation target is explicitly minimize/restore only'
Assert-That ($plans[0].Original.Acceleration -eq 2 -and $plans[1].Original.MinAnimate -eq 1) 'Original values retained for future rollback'
Assert-That ($plans[0].Evidence.Contains('fixture')) 'Injected snapshots cannot masquerade as live observations'
$snapshot.mouse.Value.Acceleration=1
Assert-That ($plans[0].Original.Acceleration -eq 2) 'Plan captures an independent original-state copy'
$results=@(Invoke-ToolkitEngine -Plan $plans)
Assert-That ($results.Count -eq 2 -and $results[0].Status -eq 'DRYRUN') 'Default engine mode is dry-run'
Assert-That (@($results | Where-Object { $_.ChangedWindows -or -not $_.LiveExecutionLocked }).Count -eq 0) 'Dry-run never reports a Windows change or unlocked execution'
Assert-That ($results[0].Verification.Contains('no write occurred')) 'Dry-run does not pretend to verify a real modification'
$off=@{
    mouse=(State ([pscustomobject]@{Threshold1=6;Threshold2=10;Acceleration=0}))
    animations=(State ([pscustomobject]@{MinAnimate=0}))
}
$skip=@(New-ToolkitExecutionPlan -OptimizationId @('mouse','animations') -SystemInfo $win -StateSnapshot $off)
Assert-That (@($skip | Where-Object { $_.Status -ne 'SKIP' }).Count -eq 0) 'Already configured settings skip duplicate operations'
$check=Test-ToolkitOperationState -OperationId mouse -ExpectedValue $plans[0].Target -ObservedState $off.mouse
Assert-That ($check.Matches -and $check.Status -eq 'MATCH') 'Verification checks full target state'
$changed=State ([pscustomobject]@{Threshold1=7;Threshold2=10;Acceleration=0})
Assert-That ((Test-ToolkitOperationState -OperationId mouse -ExpectedValue $plans[0].Target -ObservedState $changed).Status -eq 'MISMATCH') 'Verification catches threshold changes instead of checking acceleration alone'
Assert-That ((Test-ToolkitOperationState -OperationId mouse -ExpectedValue $plans[0].Original -ObservedState $off.mouse).Status -eq 'MISMATCH') 'Original-state check detects stale plans'
$bad=State $null 'Error'
Assert-That ((Test-ToolkitOperationState -OperationId mouse -ExpectedValue $plans[0].Target -ObservedState $bad).Status -eq 'UNVERIFIED') 'Unreadable state cannot pass verification'
$invalid=State ([pscustomobject]@{MinAnimate=9})
Assert-That ((Test-ToolkitOperationState -OperationId animations -ExpectedValue $plans[1].Target -ObservedState $invalid).Status -eq 'UNVERIFIED') 'Invalid native data cannot pass verification'
$partial=@(New-ToolkitExecutionPlan -OptimizationId @('mouse','animations') -SystemInfo $win -StateSnapshot @{mouse=$bad;animations=$snapshot.animations})
Assert-That ($partial[0].Status -eq 'WARN' -and $partial[1].Status -eq 'READY') 'One failed read does not abort unrelated dry-run plans'
$missing=@(New-ToolkitExecutionPlan -OptimizationId mouse -SystemInfo $win -StateSnapshot @{})
Assert-That ($missing[0].Status -eq 'WARN' -and $null -eq $missing[0].Target) 'Missing snapshots never produce guessed targets'
$badShape=@(New-ToolkitExecutionPlan -OptimizationId mouse -SystemInfo $win -StateSnapshot @{mouse=(State ([pscustomobject]@{Threshold1=-1;Threshold2=10;Acceleration=1}))})
Assert-That ($badShape[0].Status -eq 'WARN') 'Out-of-range original values are rejected'
$unsupported=@(New-ToolkitExecutionPlan -OptimizationId @('game-mode','hags','anything;arbitrary') -SystemInfo $win -StateSnapshot $snapshot)
Assert-That (@($unsupported | Where-Object { $_.Status -ne 'UNSUPPORTED' }).Count -eq 0) 'No dynamic dispatch for unimplemented or arbitrary IDs'
Assert-That (@(New-ToolkitExecutionPlan -OptimizationId @() -SystemInfo $win).Count -eq 0) 'Empty request produces no operations'
$blocked=@(New-ToolkitExecutionPlan -OptimizationId mouse -SystemInfo $service -StateSnapshot $snapshot)
Assert-That ($blocked[0].Status -eq 'BLOCKED') 'Permission failure returns a reviewable blocked plan'
Assert-That ($blocked[0].Evidence -eq 'No native read performed' -and $null -eq $blocked[0].SnapshotUtc) 'Blocked plan does not claim a native read or captured snapshot'
# Exercise the actual entry point, from the current host, with no writes.
$cli=@(& (Join-Path $root 'Start.ps1') -DryRun)
Assert-That ($cli.Count -eq 2 -and @($cli | Where-Object { $_.ChangedWindows }).Count -eq 0) 'CLI dry-run returns the two engine operations without changes'
# Apply must reject before attempting even a native read or inspecting bad plans.
$script:reads=0
function global:Get-ToolkitNativeState {
    param([string]$OperationId)
    $script:reads++; throw 'Unexpected native call during locked execution'
}
try {
    foreach ($variant in @('Default','WhatIf','NoConfirm','EmptyPlan','ForgedPlan')) {
        $rejected=$false
        try {
            switch ($variant) {
                'WhatIf' { $null=Invoke-ToolkitEngine -Plan $plans -Mode Apply -WhatIf }
                'NoConfirm' { $null=Invoke-ToolkitEngine -Plan $plans -Mode Apply -Confirm:$false }
                'EmptyPlan' { $null=Invoke-ToolkitEngine -Plan @() -Mode Apply }
                'ForgedPlan' { $null=Invoke-ToolkitEngine -Plan @([pscustomobject]@{LiveChangesEnabled=$true}) -Mode Apply }
                default { $null=Invoke-ToolkitEngine -Plan $plans -Mode Apply }
            }
        } catch { $rejected=$_.Exception.Message.Contains('persistent backups') }
        Assert-That $rejected "Apply rejects $variant request with rollback requirement"
    }
    Assert-That ($script:reads -eq 0) 'Live execution gate runs before all native access'
} finally { Remove-Item Function:/Get-ToolkitNativeState; Import-Module (Join-Path $root 'Modules/NativeSettings.psm1') -Force }
# Compile the fixed bridge on every CI runtime; do not invoke any native setter.
& (Get-Module NativeSettings) { Initialize-ToolkitNativeSettings }
$type='WindowsPerformanceToolkit.NativePreferencesV3' -as [type]
$methods=@($type.GetMethods([Reflection.BindingFlags]'Public,Static,DeclaredOnly').Name)
Assert-That ($methods.Count -eq 2 -and 'GetMouse' -in $methods -and 'GetAnimation' -in $methods) 'Compiled bridge publicly exposes only native getters'
$internal=@($type.GetMethods([Reflection.BindingFlags]'NonPublic,Static,DeclaredOnly').Name)
Assert-That ('SetMouse' -in $internal -and 'SetAnimation' -in $internal) 'Reviewed setters exist internally without a public live-execution route'
# Round-trip typed snapshots through JSON for future persistence compatibility.
$roundTrip=$plans[0].Original | ConvertTo-Json | ConvertFrom-Json
Assert-That ((Test-ToolkitOperationState -OperationId mouse -ExpectedValue $plans[0].Original -ObservedState (State $roundTrip)).Matches) 'Original snapshot survives JSON serialization'
Write-Host "`n$count engine assertions passed. Native Windows reads/setters have not been validated on this host unless explicitly reported."
