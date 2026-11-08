Set-StrictMode -Version Latest

function Get-ToolkitExecutionPolicy {
    [CmdletBinding()]
    param()
    # A code-level capability gate. JSON, -Confirm, -Force, elevation and
    # caller-supplied plans cannot enable writes. Phase 4 must implement rollback.
    [pscustomobject]@{
        LiveChangesEnabled=$false; RollbackAvailable=$false
        Reason='Live execution is locked until persistent backups and verified rollback are implemented in Phase 4.'
    }
}

function Get-ToolkitOperationDefinitions {
    [CmdletBinding()]
    param()
    # Reviewed operations only. No executable commands or target values in JSON.
    [pscustomobject]@{ Id='mouse'; Title='Disable mouse acceleration'; API='SPI_GETMOUSE / SPI_SETMOUSE'; Scope='Current user'; RequiresAdministrator=$false; RestartRequired=$false; Risk='Low'; Drawbacks='Changes pointer feel; games using raw input may ignore it. Thresholds and pointer speed are preserved.' }
    [pscustomobject]@{ Id='animations'; Title='Disable minimize/restore animations'; API='SPI_GETANIMATION / SPI_SETANIMATION'; Scope='Current user'; RequiresAdministrator=$false; RestartRequired=$false; Risk='Low'; Drawbacks='Changes desktop appearance, not every Windows animation; no guaranteed FPS benefit.' }
}

function Get-ToolkitOperationPermission {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$SystemInfo)
    if (-not $SystemInfo.IsWindows -or $SystemInfo.Build -lt 10240 -or $SystemInfo.Build -ge 30000 -or
        $null -eq $SystemInfo.PSObject.Properties['ProductType'] -or $SystemInfo.ProductType -ne 1) {
        return [pscustomobject]@{ Allowed=$false; Reason='A detected Windows 10/11 client build is required.' }
    }
    if ($null -eq $SystemInfo.PSObject.Properties['InteractiveSession'] -or -not $SystemInfo.InteractiveSession) {
        return [pscustomobject]@{ Allowed=$false; Reason='An interactive user desktop is required; service/session-zero execution is not supported.' }
    }
    [pscustomobject]@{ Allowed=$true; Reason='Current-user preference. Administrator elevation is not needed; native reads can still fail.' }
}

function ConvertTo-ToolkitOperationValue {
    param([Parameter(Mandatory)][ValidateSet('mouse','animations')][string]$OperationId,
          [Parameter(Mandatory)]$Value)
    $fields = if ($OperationId -eq 'mouse') { @('Threshold1','Threshold2','Acceleration') } else { @('MinAnimate') }
    $copy = [ordered]@{}
    foreach ($field in $fields) {
        if ($null -eq $Value.PSObject.Properties[$field]) { throw "Missing state field: $field" }
        $raw = "$($Value.$field)"
        if ($raw -notmatch '^\d{1,10}$') { throw "Invalid state field: $field" }
        $number = [long]$raw
        if ($number -gt [int]::MaxValue -or ($field -eq 'Acceleration' -and $number -gt 2) -or ($field -eq 'MinAnimate' -and $number -gt 1)) { throw "Out-of-range state field: $field" }
        $copy[$field] = [int]$number
    }
    [pscustomobject]$copy
}

function Test-ToolkitOperationState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('mouse','animations')][string]$OperationId,
          [Parameter(Mandatory)]$ExpectedValue, $ObservedState)
    if ($null -eq $ObservedState) { $ObservedState=Get-ToolkitNativeState -OperationId $OperationId }
    try {
        if ($ObservedState.State -ne 'Known') { throw 'Current native state could not be read.' }
        $expected=ConvertTo-ToolkitOperationValue -OperationId $OperationId -Value $ExpectedValue
        $actual=ConvertTo-ToolkitOperationValue -OperationId $OperationId -Value $ObservedState.Value
        foreach ($field in $expected.PSObject.Properties.Name) {
            if ($expected.$field -ne $actual.$field) {
                return [pscustomobject]@{ Matches=$false; Status='MISMATCH'; Reason="State differs: $field" }
            }
        }
        [pscustomobject]@{ Matches=$true; Status='MATCH'; Reason='All modeled values match the expected state. This is a state check, not a performance benchmark.' }
    } catch {
        [pscustomobject]@{ Matches=$false; Status='UNVERIFIED'; Reason='State missing, invalid, or unreadable. Verification cannot be claimed.' }
    }
}

function New-ToolkitExecutionPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$OptimizationId,
          [Parameter(Mandatory)]$SystemInfo,
          [hashtable]$StateSnapshot)
    $definitions=@{}; foreach ($definition in Get-ToolkitOperationDefinitions) { $definitions[$definition.Id]=$definition }
    $permission=Get-ToolkitOperationPermission -SystemInfo $SystemInfo
    $seen=@{}
    foreach ($rawId in $OptimizationId) {
        if ([string]::IsNullOrWhiteSpace($rawId)) { continue }
        $id=$rawId.Trim().ToLowerInvariant()
        if ($seen.ContainsKey($id)) { continue }
        $seen[$id]=$true
        $plan=[pscustomobject]@{
            Id=$id; Title=$id; Status='UNSUPPORTED'; Reason='No reviewed engine operation for this ID; comparison-only.'
            Original=$null; Target=$null; Source=''; API=''; Scope='Current user'
            RequiresAdministrator=$false; Permission=$permission.Reason; RestartRequired=$false
            Risk='Unknown'; Drawbacks=''; RollbackAvailable=$false; ChangedWindows=$false
            PlanCreatedUtc=[DateTime]::UtcNow.ToString('o'); SnapshotUtc=$null; Evidence='No native read performed'
        }
        if (-not $definitions.ContainsKey($id)) { $plan; continue }
        $definition=$definitions[$id]
        $plan.Title=$definition.Title; $plan.API=$definition.API
        $plan.Risk=$definition.Risk; $plan.Drawbacks=$definition.Drawbacks
        if (-not $permission.Allowed) { $plan.Status='BLOCKED'; $plan.Reason=$permission.Reason; $plan; continue }
        if ($PSBoundParameters.ContainsKey('StateSnapshot')) {
            $plan.Evidence='Caller-supplied fixture snapshot (not a live Windows read)'
            if ($null -eq $StateSnapshot -or -not $StateSnapshot.ContainsKey($id)) {
                $plan.Status='WARN'; $plan.Reason='No supplied snapshot for this operation; no default assumed.'; $plan; continue
            }
            $state=$StateSnapshot[$id]
        } else { $plan.Evidence='Live API read attempted'; $state=Get-ToolkitNativeState -OperationId $id }
        try {
            $plan.Source=$state.Source
            if ($state.State -ne 'Known') { throw 'Native state unavailable.' }
            $plan.Original=ConvertTo-ToolkitOperationValue -OperationId $id -Value $state.Value
            $plan.SnapshotUtc=[DateTime]::UtcNow.ToString('o')
            if (-not $PSBoundParameters.ContainsKey('StateSnapshot')) { $plan.Evidence='Live API snapshot' }
            if ($id -eq 'mouse') {
                $plan.Target=[pscustomobject]@{Threshold1=$plan.Original.Threshold1;Threshold2=$plan.Original.Threshold2;Acceleration=0}
            } else { $plan.Target=[pscustomobject]@{MinAnimate=0} }
            $check=Test-ToolkitOperationState -OperationId $id -ExpectedValue $plan.Target -ObservedState $state
            if ($check.Status -eq 'MATCH') { $plan.Status='SKIP'; $plan.Reason='Already configured; no duplicate change is needed.' }
            else { $plan.Status='READY'; $plan.Reason='Dry-run target prepared. Original values captured in memory only; live execution remains locked.' }
        } catch { $plan.Status='WARN'; $plan.Reason='Could not establish valid original native values. No change is planned.'; $plan.Original=$null; $plan.Target=$null }
        $plan
    }
}

function Invoke-ToolkitEngine {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Plan,
          [ValidateSet('DryRun','Apply')][string]$Mode='DryRun')
    # Fail before reading any caller-supplied plan or reaching native code.
    # Even -WhatIf cannot make an Apply request appear to succeed.
    if ($Mode -eq 'Apply') { throw (Get-ToolkitExecutionPolicy).Reason }
    foreach ($entry in $Plan) {
        [pscustomobject]@{
            Id=$entry.Id; Status=$(if ($entry.Status -eq 'READY') { 'DRYRUN' } else { $entry.Status })
            Original=$entry.Original; Target=$entry.Target; Reason=$entry.Reason
            Scope=$entry.Scope; Permission=$entry.Permission; RequiresAdministrator=$entry.RequiresAdministrator
            RestartRequired=$entry.RestartRequired; API=$entry.API; Risk=$entry.Risk; Drawbacks=$entry.Drawbacks
            Evidence=$entry.Evidence; ChangedWindows=$false; LiveExecutionLocked=$true
            Verification='Not performed: no write occurred.'; RollbackAvailable=$false
        }
    }
}

Export-ModuleMember -Function Get-ToolkitExecutionPolicy, Get-ToolkitOperationDefinitions, Get-ToolkitOperationPermission, Test-ToolkitOperationState, New-ToolkitExecutionPlan, Invoke-ToolkitEngine
