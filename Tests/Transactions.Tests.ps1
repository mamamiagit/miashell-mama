#Requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach ($name in @('SystemInfo','NativeSettings','Engine','Backup','Transactions','Restore')) { Import-Module (Join-Path $root "Modules/$name.psm1") -Force }
$count=0
function Assert-That([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "FAIL: $Message" };$script:count++;Write-Host "PASS: $Message" }
function New-Fixture { @{mouse=[pscustomobject]@{Threshold1=6;Threshold2=10;Acceleration=2};animations=[pscustomobject]@{MinAnimate=1}} }
function Must-Reject([scriptblock]$Action,[string]$Message) { $failed=$false;try { $null=& $Action } catch { $failed=$true }; Assert-That $failed $Message }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('toolkit-transactions-'+[guid]::NewGuid().ToString('N'))
$context=Get-ToolkitContext -Backend Fixture
# Fault injection is module-scoped test code only, never a product callback or profile command.
& (Get-Module Transactions) {
    $script:originalSetter=${function:Set-ToolkitBackendState}
    $script:originalReader=${function:Get-ToolkitBackendState}
    $script:fault='';$script:setCalls=0;$script:mouseReads=0
    function script:Set-ToolkitBackendState {
        param([string]$Directory,[string]$SessionId,[string]$Id,[switch]$Restore,[System.Collections.IDictionary]$FixtureState)
        $script:setCalls++
        $record=Read-ToolkitSession -Directory $Directory -SessionId $SessionId -Context (Get-ToolkitContext -Backend Fixture)
        if ($null -eq $record.Entries[0].Original) { throw 'Write happened without an original backup.' }
        if (-not $Restore -and $Id -eq 'animations' -and $script:fault -in @('BeforeSecond','CrashAndRestore')) { throw 'Fixture failure before second write' }
        if ($Restore -and $script:fault -in @('RestoreFailure','CrashAndRestore')) { throw 'Fixture restore error' }
        & $script:originalSetter @PSBoundParameters
        if (-not $Restore -and $Id -eq 'animations' -and $script:fault -eq 'AfterSecond') { throw 'Fixture failure after second write' }
        if (-not $Restore -and $Id -eq 'mouse' -and $script:fault -eq 'CorruptAfterWrite') { $FixtureState.mouse.Acceleration=1 }
    }
    function script:Get-ToolkitBackendState {
        param([string]$Id,[System.Collections.IDictionary]$FixtureState)
        if ($Id -eq 'mouse') {
            $script:mouseReads++
            if ($script:fault -eq 'Stale' -and $script:mouseReads -eq 2) { $FixtureState.mouse.Acceleration=1 }
        }
        & $script:originalReader @PSBoundParameters
    }
}
try {
    $state=New-Fixture;$dir=Join-Path $temp 'normal'
    $applied=Invoke-ToolkitSession -Directory $dir -FixtureState $state -Confirm:$false
    Assert-That ($applied.Status -eq 'Completed' -and -not $applied.ChangedWindows) 'Fixture apply completes without pretending to change Windows'
    Assert-That ($state.mouse.Acceleration -eq 0 -and $state.animations.MinAnimate -eq 0) 'Both fixture targets applied'
    $saved=Read-ToolkitSession -Directory $dir -SessionId $applied.SessionId -Context $context
    Assert-That ($saved.Entries[0].Original.Acceleration -eq 2 -and $saved.Entries[1].Original.MinAnimate -eq 1) 'Exact originals survive persistent backup'
    Assert-That (@($saved.Events).Count -ge 6) 'History records write intent and verification'
    $first=Restore-ToolkitSession -Directory $dir -SessionId $applied.SessionId -OptimizationId mouse -FixtureState $state -Confirm:$false
    Assert-That ($first.Status -eq 'PartialRestore' -and $state.mouse.Acceleration -eq 2 -and $state.animations.MinAnimate -eq 0) 'Individual restore affects only the selected setting'
    $restored=Restore-ToolkitSession -Directory $dir -SessionId $applied.SessionId -FixtureState $state -Confirm:$false
    Assert-That ($restored.RestorationVerified -and $state.animations.MinAnimate -eq 1) 'Session rollback restores all remaining originals'
    $again=Restore-ToolkitSession -Directory $dir -SessionId $applied.SessionId -FixtureState $state -Confirm:$false
    Assert-That ($again.Status -eq 'Restored') 'Repeated rollback is idempotent'
    Assert-That (@(Get-ToolkitSessionHistory -Directory $dir -Context $context).Count -eq 1) 'History loads checksummed sessions'
    Assert-That (@(Get-ToolkitRestorePreview -Directory $dir -SessionId $applied.SessionId -FixtureState $state).Count -eq 2) 'Restore preview includes both exact originals'
    $foreign=$context.PSObject.Copy();$foreign.User='Different user'
    Must-Reject {Read-ToolkitSession -Directory $dir -SessionId $applied.SessionId -Context $foreign} 'Backups cannot cross user contexts'
    Must-Reject {Read-ToolkitSession -Directory $dir -SessionId '../outside' -Context $context} 'Session IDs cannot escape the backup directory'
    Must-Reject {Invoke-ToolkitSession -Directory $dir -FixtureState $null -Confirm:$false} 'Null fixture cannot fall through to native execution'
    Must-Reject {Invoke-ToolkitSession -Directory $dir -FixtureState $state -ValidateNative -Confirm:$false} 'Fixture tests cannot create native validation proof'
    $noop=New-Fixture;$noop.mouse.Acceleration=0;$noop.animations.MinAnimate=0
    $noDir=Join-Path $temp 'noop'
    $none=Invoke-ToolkitSession -Directory $noDir -FixtureState $noop -Confirm:$false
    Assert-That ($none.Status -eq 'NoChanges' -and -not (Test-Path $noDir)) 'Already configured settings create no session or writes'
    $what=New-Fixture;$whatDir=Join-Path $temp 'whatif'
    $cancel=Invoke-ToolkitSession -Directory $whatDir -FixtureState $what -WhatIf
    Assert-That ($cancel.Status -eq 'Cancelled' -and -not (Test-Path $whatDir) -and $what.mouse.Acceleration -eq 2) 'WhatIf creates no backup and changes no fixture values'
    foreach ($fault in @('BeforeSecond','AfterSecond')) {
        & (Get-Module Transactions) {param($mode) $script:fault=$mode;$script:mouseReads=0} $fault
        $failedState=New-Fixture;$faultDir=Join-Path $temp $fault
        $failed=Invoke-ToolkitSession -Directory $faultDir -FixtureState $failedState -Confirm:$false
        Assert-That ($failed.Status -eq 'Restored' -and -not [string]::IsNullOrWhiteSpace($failed.Error)) "$fault failure is reported after verified automatic rollback"
        Assert-That ($failedState.mouse.Acceleration -eq 2 -and $failedState.animations.MinAnimate -eq 1) "$fault rollback recovers both original values"
    }
    & (Get-Module Transactions) {$script:fault='CrashAndRestore';$script:mouseReads=0}
    $retryState=New-Fixture;$retryDir=Join-Path $temp 'retry'
    $incomplete=Invoke-ToolkitSession -Directory $retryDir -FixtureState $retryState -Confirm:$false
    Assert-That ($incomplete.Status -eq 'PartialRestore' -and -not $incomplete.RestorationVerified) 'A failed rollback never reports complete recovery'
    Assert-That (Test-Path $incomplete.BackupPath) 'Original backup remains available after rollback failure'
    & (Get-Module Transactions) {$script:fault='';$script:mouseReads=0}
    $retry=Restore-ToolkitSession -Directory $retryDir -SessionId $incomplete.SessionId -FixtureState $retryState -Confirm:$false
    Assert-That ($retry.Status -eq 'Restored' -and $retryState.mouse.Acceleration -eq 2) 'Recovery can be retried after a restore error'
    & (Get-Module Transactions) {$script:fault='CorruptAfterWrite';$script:mouseReads=0}
    $mismatchState=New-Fixture;$mismatchDir=Join-Path $temp 'mismatch'
    $mismatch=Invoke-ToolkitSession -Directory $mismatchDir -FixtureState $mismatchState -Confirm:$false
    Assert-That ($mismatch.Status -eq 'PartialRestore' -and $mismatch.Error.Contains('verification')) 'Post-write mismatch is reported without claiming success'
    Assert-That ($mismatchState.mouse.Acceleration -eq 1) 'Unrecognized post-write state is preserved for explicit recovery'
    & (Get-Module Transactions) {$script:fault='Stale';$script:mouseReads=0}
    $stale=New-Fixture;$staleDir=Join-Path $temp 'stale'
    $staleResult=Invoke-ToolkitSession -Directory $staleDir -FixtureState $stale -Confirm:$false
    Assert-That ($staleResult.Status -eq 'PartialRestore' -and $stale.mouse.Acceleration -eq 1) 'Stale plan preserves an external preference instead of overwriting it'
    Assert-That ($staleResult.Entries[0].State -eq 'Conflict') 'Conflict is persisted for later recovery'
    & (Get-Module Transactions) {$script:fault='';$script:mouseReads=0}
    Must-Reject {Invoke-ToolkitSession -Directory $staleDir -FixtureState $stale -Confirm:$false} 'Unfinished sessions block new mutations'
    $stale.mouse.Acceleration=0
    $fixed=Restore-ToolkitSession -Directory $staleDir -SessionId $staleResult.SessionId -FixtureState $stale -Confirm:$false
    Assert-That ($fixed.Status -eq 'Restored' -and $stale.mouse.Acceleration -eq 2) 'Explicit recovery succeeds when state again matches the recorded target'
    $conflict=New-Fixture;$conflictDir=Join-Path $temp 'external'
    $base=Invoke-ToolkitSession -Directory $conflictDir -FixtureState $conflict -Confirm:$false
    $conflict.mouse.Threshold1=7
    $external=Restore-ToolkitSession -Directory $conflictDir -SessionId $base.SessionId -FixtureState $conflict -Confirm:$false
    Assert-That ($external.Status -eq 'PartialRestore' -and $conflict.mouse.Threshold1 -eq 7 -and $conflict.animations.MinAnimate -eq 1) 'Full rollback preserves external mouse changes while restoring unrelated settings'
    $restoreWhat=New-Fixture;$restoreDir=Join-Path $temp 'restorewhat'
    $base=Invoke-ToolkitSession -Directory $restoreDir -FixtureState $restoreWhat -Confirm:$false
    $cancel=Restore-ToolkitSession -Directory $restoreDir -SessionId $base.SessionId -FixtureState $restoreWhat -WhatIf
    Assert-That ($cancel.Status -eq 'Cancelled' -and $restoreWhat.mouse.Acceleration -eq 0) 'Restore WhatIf is read-only'
    $lock=Enter-ToolkitSessionLock -Directory $restoreDir -Context $context
    try { Must-Reject {Restore-ToolkitSession -Directory $restoreDir -SessionId $base.SessionId -FixtureState $restoreWhat -Confirm:$false} 'Concurrent session-store access is rejected' }
    finally { Exit-ToolkitSessionLock -Lock $lock }
    # Corrupt envelope is never used for restoration or silently ignored before applying.
    $path=Get-ToolkitSessionPath -Directory $restoreDir -SessionId $base.SessionId
    [IO.File]::WriteAllText($path,'{"Payload":"{}","SHA256":"incorrect"}')
    Must-Reject {Restore-ToolkitSession -Directory $restoreDir -SessionId $base.SessionId -FixtureState $restoreWhat -Confirm:$false} 'Checksum mismatch blocks restoration'
    $restoreWhat.mouse.Acceleration=2
    Must-Reject {Invoke-ToolkitSession -Directory $restoreDir -FixtureState $restoreWhat -Confirm:$false} 'Corrupt session is not ignored before a new mutation'
    # Simulate a crash after a write but before completion; reload from disk.
    $crashState=New-Fixture;$crashDir=Join-Path $temp 'crash'
    $crash=Invoke-ToolkitSession -Directory $crashDir -FixtureState $crashState -Confirm:$false
    $record=Read-ToolkitSession -Directory $crashDir -SessionId $crash.SessionId -Context $context
    $record.Status='Applying';$record.Entries[0].State='Applying'
    Save-ToolkitSession -Directory $crashDir -Record $record -Event 'Fixture crash after mouse write.'
    $recovery=Restore-ToolkitSession -Directory $crashDir -SessionId $crash.SessionId -FixtureState $crashState -Confirm:$false
    Assert-That ($recovery.Status -eq 'Restored' -and $crashState.mouse.Acceleration -eq 2) 'Interrupted write intent recovers using reloaded original state'
    # Fail persistence before any write, and verify the fixture remains untouched.
    & (Get-Module Backup) {
        $script:originalDocumentWriter=${function:Write-ToolkitDocument}
        function script:Write-ToolkitDocument {param($Path,$Value) throw 'Fixture disk unavailable'}
    }
    try {
        $disk=New-Fixture
        Must-Reject {Invoke-ToolkitSession -Directory (Join-Path $temp 'disk') -FixtureState $disk -Confirm:$false} 'Backup persistence failure aborts apply'
        Assert-That ($disk.mouse.Acceleration -eq 2 -and $disk.animations.MinAnimate -eq 1) 'No setting changes when originals cannot be saved'
    } finally { & (Get-Module Backup) {Set-Item Function:script:Write-ToolkitDocument $script:originalDocumentWriter} }
    Assert-That (-not (Test-ToolkitNativeValidation -Directory $dir)) 'Fixture sessions do not unlock native changes'
    Assert-That (-not (Test-Path (Join-Path $dir 'native-validation.json'))) 'No native validation marker written by fixture tests'
    $malformed=Read-ToolkitSession -Directory $dir -SessionId $applied.SessionId -Context $context
    $malformed.Entries[0].Target.Threshold1=99
    Write-ToolkitDocument -Path (Get-ToolkitSessionPath -Directory $dir -SessionId $applied.SessionId) -Value $malformed
    Must-Reject {Read-ToolkitSession -Directory $dir -SessionId $applied.SessionId -Context $context} 'Checksummed but invalid operation targets are rejected'
} finally {
    & (Get-Module Transactions) {
        Set-Item Function:script:Set-ToolkitBackendState $script:originalSetter
        Set-Item Function:script:Get-ToolkitBackendState $script:originalReader
    }
    if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host "`n$count transaction assertions passed. Fixture tests do not validate native Windows writes."
