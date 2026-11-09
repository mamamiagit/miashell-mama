Set-StrictMode -Version Latest

function Get-ToolkitBackendState {
    param([string]$Id,[System.Collections.IDictionary]$FixtureState)
    if ($null -ne $FixtureState) {
        if (-not $FixtureState.Contains($Id)) { return [pscustomobject]@{State='Missing';Value=$null;Source='Fixture'} }
        return [pscustomobject]@{State='Known';Value=$FixtureState[$Id];Source='Fixture'}
    }
    Get-ToolkitNativeState -OperationId $Id
}

function Set-ToolkitBackendState {
    param([string]$Directory,[string]$SessionId,[string]$Id,[switch]$Restore,
          [System.Collections.IDictionary]$FixtureState)
    $backend=if ($null -ne $FixtureState) { 'Fixture' } else { 'Native' }
    $record=Read-ToolkitSession -Directory $Directory -SessionId $SessionId -Context (Get-ToolkitContext -Backend $backend)
    $entry=@($record.Entries | Where-Object { $_.Id -eq $Id })
    if ($entry.Count -ne 1) { throw 'Missing journal operation.' }
    $expected=if ($Restore) { 'Restoring' } else { 'Applying' }
    if ($record.Status -ne $expected -or $entry[0].State -ne $expected) { throw 'Durable write intent is required before a write.' }
    $value=if ($Restore) { $entry[0].Original } else { $entry[0].Target }
    if ($backend -eq 'Fixture') {
        $FixtureState[$Id]=ConvertTo-ToolkitOperationValue -OperationId $Id -Value $value
    } else {
        Invoke-ToolkitNativeWrite -Directory $Directory -SessionId $SessionId -OperationId $Id -Restore:$Restore -Confirm:$false
    }
}

function Get-ToolkitNativeFingerprint {
    $context=Get-ToolkitContext
    $source=(@('NativeSettings','Engine','Backup','Restore','Transactions') | ForEach-Object { [IO.File]::ReadAllText((Join-Path $PSScriptRoot ($_.ToString()+'.psm1'))) }) -join '|'
    Get-ToolkitDigest ($context.Machine+'|'+$context.User+'|'+$context.Build+'|'+$source)
}

function Test-ToolkitNativeValidation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)
    if ($env:OS -ne 'Windows_NT') { return $false }
    try {
        $marker=Read-ToolkitDocument -Path (Join-Path $Directory 'native-validation.json')
        if ($marker.SchemaVersion -ne 1 -or $marker.Fingerprint -cne (Get-ToolkitNativeFingerprint)) { return $false }
        $when=[DateTime]::Parse($marker.ValidatedUtc).ToUniversalTime()
        if ($when -gt [DateTime]::UtcNow -or $when -lt [DateTime]::UtcNow.AddDays(-30)) { return $false }
        $record=Read-ToolkitSession -Directory $Directory -SessionId $marker.SessionId -Context (Get-ToolkitContext)
        $ids=@($record.Entries.Id | Sort-Object)
        $record.Validation -eq $true -and $record.Status -eq 'Restored' -and $ids.Count -eq 2 -and $ids[0] -eq 'animations' -and $ids[1] -eq 'mouse' -and @($record.Entries | Where-Object { $_.State -ne 'Restored' }).Count -eq 0
    } catch { $false }
}

function New-ToolkitOptionalRestorePoint {
    [CmdletBinding()]
    param()
    $result=[pscustomobject]@{Status='WARN';Verified=$false;Message='Restore point unavailable; durable toolkit backups are still required.'}
    if ($env:OS -ne 'Windows_NT') { return $result }
    try {
        $system=Get-ToolkitSystemInfo
        if (-not $system.Administrator -or $null -eq (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue) -or $null -eq (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue)) { return $result }
        $description='WindowsPerformanceToolkit-'+[guid]::NewGuid().ToString('N')
        $before=@(Get-ComputerRestorePoint -ErrorAction Stop | Select-Object -ExpandProperty SequenceNumber)
        Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        $after=@(Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { $_.Description -eq $description -and $_.SequenceNumber -notin $before })
        if ($after.Count -eq 1) { $result.Status='OK';$result.Verified=$true;$result.Message="Verified restore point sequence $($after[0].SequenceNumber)." }
    } catch { $result.Message='Restore point creation/query failed or was limited by Windows. No restore point is claimed.' }
    $result
}

function Invoke-ToolkitRecoveryCore {
    param([string]$Directory,$Record,[string[]]$OptimizationId,
          [System.Collections.IDictionary]$FixtureState)
    $OptimizationId=@($OptimizationId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $entries=@($Record.Entries); [array]::Reverse($entries)
    if (@($OptimizationId).Count -gt 0) {
        foreach ($id in $OptimizationId) { if ($id -notin @($Record.Entries.Id)) { throw "Operation is not in this session: $id" } }
        $entries=@($entries | Where-Object { $_.Id -in $OptimizationId })
    }
    $Record.Status='Restoring'; Save-ToolkitSession -Directory $Directory -Record $Record -Event 'Restore intent persisted.'
    foreach ($entry in $entries) {
        try {
            $observed=Get-ToolkitBackendState -Id $entry.Id -FixtureState $FixtureState
            $original=Test-ToolkitOperationState -OperationId $entry.Id -ExpectedValue $entry.Original -ObservedState $observed
            if ($original.Matches) {
                $entry.State='Restored'; Save-ToolkitSession -Directory $Directory -Record $Record -Event "$($entry.Id): original state already present and verified."
                continue
            }
            $target=Test-ToolkitOperationState -OperationId $entry.Id -ExpectedValue $entry.Target -ObservedState $observed
            if (-not $target.Matches) {
                $entry.State=if ($target.Status -eq 'UNVERIFIED') { 'Unverified' } else { 'Conflict' }
                Save-ToolkitSession -Directory $Directory -Record $Record -Event "$($entry.Id): external change or unreadable state; restore refused."
                continue
            }
            $entry.State='Restoring'; Save-ToolkitSession -Directory $Directory -Record $Record -Event "$($entry.Id): write-ahead restore intent."
            Set-ToolkitBackendState -Directory $Directory -SessionId $Record.SessionId -Id $entry.Id -Restore -FixtureState $FixtureState
            $check=Test-ToolkitOperationState -OperationId $entry.Id -ExpectedValue $entry.Original -ObservedState (Get-ToolkitBackendState -Id $entry.Id -FixtureState $FixtureState)
            $entry.State=if ($check.Matches) { 'Restored' } else { 'Unverified' }
            Save-ToolkitSession -Directory $Directory -Record $Record -Event "$($entry.Id): restore verification $($check.Status)."
        } catch {
            $entry.State='Unverified'
            # If persistence fails, stop: another write without a durable intent is forbidden.
            Save-ToolkitSession -Directory $Directory -Record $Record -Event "$($entry.Id): restore failed; manual recovery may be required."
        }
    }
    $Record.Status=if (@($Record.Entries | Where-Object { $_.State -ne 'Restored' }).Count -eq 0) { 'Restored' } else { 'PartialRestore' }
    Save-ToolkitSession -Directory $Directory -Record $Record -Event "Session restore result: $($Record.Status)."
    $Record
}

function Get-ToolkitSessionResult {
    param($Record,[string]$Directory,[string]$ErrorMessage='')
    [pscustomobject]@{
        SessionId=$Record.SessionId;Backend=$Record.Context.Backend;Status=$Record.Status
        Entries=@($Record.Entries);BackupPath=(Get-ToolkitSessionPath -Directory $Directory -SessionId $Record.SessionId)
        RestorationVerified=($Record.Status -eq 'Restored');Error=$ErrorMessage
        ChangedWindows=$(if ($Record.Context.Backend -eq 'Fixture' -or $Record.Status -eq 'Restored') { $false } elseif ($Record.Status -eq 'Completed') { $true } else { $null })
    }
}

function Invoke-ToolkitSession {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$Directory,[string[]]$OptimizationId=@('mouse','animations'),
          [System.Collections.IDictionary]$FixtureState,[switch]$ValidateNative,[switch]$CreateRestorePoint)
    $fixture=$PSBoundParameters.ContainsKey('FixtureState')
    if ($fixture -and $null -eq $FixtureState) { throw 'A fixture backend cannot fall through to native execution.' }
    if ($fixture -and ($ValidateNative -or $CreateRestorePoint)) { throw 'Fixtures cannot validate native settings or create restore points.' }
    $backend=if ($fixture) { 'Fixture' } else { 'Native' }
    $context=Get-ToolkitContext -Backend $backend
    if ($fixture) { $system=[pscustomobject]@{IsWindows=$true;Build=22631;ProductType=1;InteractiveSession=$true} }
    else {
        $system=Get-ToolkitSystemInfo
        if (-not (Get-ToolkitOperationPermission -SystemInfo $system).Allowed) { throw 'Interactive Windows client required.' }
        if (-not $ValidateNative -and -not (Test-ToolkitNativeValidation -Directory $Directory)) { throw 'Run -ValidateNative to verify a local backed-up apply/restore round trip first.' }
    }
    if ($ValidateNative) { $OptimizationId=@('mouse','animations') }
    $snapshots=@{}
    if ($fixture) {
        foreach ($id in @('mouse','animations')) { $snapshots[$id]=Get-ToolkitBackendState -Id $id -FixtureState $FixtureState }
        $plans=@(New-ToolkitExecutionPlan -OptimizationId $OptimizationId -SystemInfo $system -StateSnapshot $snapshots)
    } else { $plans=@(New-ToolkitExecutionPlan -OptimizationId $OptimizationId -SystemInfo $system) }
    $unready=@($plans | Where-Object { $_.Status -notin @('READY','SKIP') })
    if ($unready.Count -gt 0) { throw ('Unreadable or unimplemented engine operations: '+($unready.Id -join ', ')+'. Only mouse and animations support backed-up apply.') }
    $actionable=@($plans | Where-Object { $_.Status -eq 'READY' -or $ValidateNative })
    if ($actionable.Count -eq 0) { return [pscustomobject]@{SessionId='';Backend=$backend;Status='NoChanges';ChangedWindows=$false} }
    $preview=(@($actionable | ForEach-Object { $_.Id+': '+($_.Original | ConvertTo-Json -Compress)+' -> '+($_.Target | ConvertTo-Json -Compress) }) -join '; ')
    $action=if ($ValidateNative) { 'VALIDATE: temporarily set and restore both preferences, with a durable backup. ' } else { 'Apply current-user preferences after durable backup. ' }
    if (-not $PSCmdlet.ShouldProcess($context.Machine+' / '+$context.User,$action+$preview)) { return [pscustomobject]@{SessionId='';Backend=$backend;Status='Cancelled';ChangedWindows=$false} }
    $lock=Enter-ToolkitSessionLock -Directory $Directory -Context $context
    $record=$null
    try {
        # A crashed/unfinished session must be recovered before new mutations.
        $folder=Join-Path $Directory 'Sessions'
        if (Test-Path -LiteralPath $folder) {
            foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.json')) {
                # Fail closed on corrupt or foreign records; history display may skip
                # them, but a new mutation must not ignore unknown recovery state.
                $existing=Read-ToolkitSession -Directory $Directory -SessionId $file.BaseName -Context $context
                if ($existing.Status -in @('Prepared','Applying','Failed','RecoveryRequired','Restoring','PartialRestore')) { throw "Recover unfinished session $($existing.SessionId) before starting another." }
                if ($existing.Status -eq 'Completed' -and @($existing.Entries | Where-Object { $_.State -ne 'Restored' -and $_.Id -in @($actionable.Id) }).Count -gt 0) { throw "Restore overlapping session $($existing.SessionId) before reapplying the same setting." }
            }
        }
        if ($ValidateNative) {
            $marker=Join-Path $Directory 'native-validation.json'
            if ([IO.File]::Exists($marker)) { [IO.File]::Delete($marker) }
        }
        $entries=@($actionable | ForEach-Object { [pscustomobject]@{Id=$_.Id;Original=$_.Original;Target=$_.Target;State='Prepared'} })
        $record=[pscustomobject]@{SchemaVersion=1;SessionId=[guid]::NewGuid().ToString('N');CreatedUtc=[DateTime]::UtcNow.ToString('o');UpdatedUtc='';Context=$context;Validation=[bool]$ValidateNative;Status='Prepared';Entries=$entries;Events=@();RestorePoint=$null}
        Save-ToolkitSession -Directory $Directory -Record $record -Event 'Original values durably saved and verified before any preference write.'
        if ($CreateRestorePoint) {
            $record.RestorePoint=New-ToolkitOptionalRestorePoint
            if (-not $record.RestorePoint.Verified) { Write-Warning $record.RestorePoint.Message }
            Save-ToolkitSession -Directory $Directory -Record $record -Event $record.RestorePoint.Message
        }
        $record.Status='Applying';Save-ToolkitSession -Directory $Directory -Record $record -Event 'Session applying.'
        try {
            foreach ($entry in $record.Entries) {
                $fresh=Get-ToolkitBackendState -Id $entry.Id -FixtureState $FixtureState
                if (-not (Test-ToolkitOperationState -OperationId $entry.Id -ExpectedValue $entry.Original -ObservedState $fresh).Matches) { throw "Stale original state: $($entry.Id)" }
                $entry.State='Applying';Save-ToolkitSession -Directory $Directory -Record $record -Event "$($entry.Id): write-ahead apply intent."
                Set-ToolkitBackendState -Directory $Directory -SessionId $record.SessionId -Id $entry.Id -FixtureState $FixtureState
                if (-not (Test-ToolkitOperationState -OperationId $entry.Id -ExpectedValue $entry.Target -ObservedState (Get-ToolkitBackendState -Id $entry.Id -FixtureState $FixtureState)).Matches) { throw "Post-write verification failed: $($entry.Id)" }
                $entry.State='Applied';Save-ToolkitSession -Directory $Directory -Record $record -Event "$($entry.Id): target verified."
            }
            $record.Status='Completed';Save-ToolkitSession -Directory $Directory -Record $record -Event 'All requested targets verified.'
        } catch {
            $failure=$_.Exception.Message
            try {
                $record=Read-ToolkitSession -Directory $Directory -SessionId $record.SessionId -Context $context
                $record=Invoke-ToolkitRecoveryCore -Directory $Directory -Record $record -FixtureState $FixtureState
            } catch {
                $record.Status='RecoveryRequired'
                try { Save-ToolkitSession -Directory $Directory -Record $record -Event 'Automatic rollback could not complete; retain this backup and recover explicitly.' } catch { }
            }
            return Get-ToolkitSessionResult -Record $record -Directory $Directory -ErrorMessage $failure
        }
        if ($ValidateNative) {
            $record=Invoke-ToolkitRecoveryCore -Directory $Directory -Record $record
            if ($record.Status -ne 'Restored') { throw 'Validation restoration is incomplete. Recover this session before using the toolkit.' }
            Write-ToolkitDocument -Path (Join-Path $Directory 'native-validation.json') -Value ([pscustomobject]@{SchemaVersion=1;SessionId=$record.SessionId;Fingerprint=(Get-ToolkitNativeFingerprint);ValidatedUtc=[DateTime]::UtcNow.ToString('o')})
        }
        Get-ToolkitSessionResult -Record $record -Directory $Directory
    } finally { Exit-ToolkitSessionLock -Lock $lock }
}

function Invoke-ToolkitSessionRestore {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$SessionId,
          [string[]]$OptimizationId,[System.Collections.IDictionary]$FixtureState)
    $OptimizationId=@($OptimizationId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $fixture=$PSBoundParameters.ContainsKey('FixtureState')
    if ($fixture -and $null -eq $FixtureState) { throw 'Null fixture rejected.' }
    $backend=if ($fixture) { 'Fixture' } else { 'Native' }
    $context=Get-ToolkitContext -Backend $backend
    if (-not $fixture -and -not (Get-ToolkitOperationPermission -SystemInfo (Get-ToolkitSystemInfo)).Allowed) { throw 'Interactive Windows client required for restore.' }
    $record=Read-ToolkitSession -Directory $Directory -SessionId $SessionId -Context $context
    $description=(@($record.Entries | Where-Object { @($OptimizationId).Count -eq 0 -or $_.Id -in $OptimizationId } | ForEach-Object { $_.Id+': '+($_.Original | ConvertTo-Json -Compress) }) -join '; ')
    if (-not $PSCmdlet.ShouldProcess($SessionId,'Restore exact original values: '+$description)) { return [pscustomobject]@{SessionId=$SessionId;Status='Cancelled';ChangedWindows=$false} }
    $lock=Enter-ToolkitSessionLock -Directory $Directory -Context $context
    try {
        $record=Read-ToolkitSession -Directory $Directory -SessionId $SessionId -Context $context
        $record=Invoke-ToolkitRecoveryCore -Directory $Directory -Record $record -OptimizationId $OptimizationId -FixtureState $FixtureState
        Get-ToolkitSessionResult -Record $record -Directory $Directory
    } finally { Exit-ToolkitSessionLock -Lock $lock }
}
Export-ModuleMember -Function Invoke-ToolkitSession, Test-ToolkitNativeValidation, New-ToolkitOptionalRestorePoint, Invoke-ToolkitSessionRestore
