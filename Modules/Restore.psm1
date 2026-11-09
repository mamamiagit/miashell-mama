Set-StrictMode -Version Latest
function Get-ToolkitRestoreStatus {
    [CmdletBinding()]
    param()
    [pscustomobject]@{Available=$true;Message='Restore a session or an individual setting from its original snapshot. Conflicting external changes are never overwritten automatically.'}
}

function Get-ToolkitRestorePreview {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$SessionId,
          [string[]]$OptimizationId,[System.Collections.IDictionary]$FixtureState)
    $OptimizationId=@($OptimizationId | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $backend=if ($PSBoundParameters.ContainsKey('FixtureState')) { 'Fixture' } else { 'Native' }
    if ($backend -eq 'Fixture' -and $null -eq $FixtureState) { throw 'Null fixture rejected.' }
    $record=Read-ToolkitSession -Directory $Directory -SessionId $SessionId -Context (Get-ToolkitContext -Backend $backend)
    foreach ($entry in $record.Entries) {
        if (@($OptimizationId).Count -gt 0 -and $entry.Id -notin $OptimizationId) { continue }
        [pscustomobject]@{Id=$entry.Id;SessionId=$SessionId;Original=$entry.Original;AppliedTarget=$entry.Target;RecordedState=$entry.State;Rule='Restore only if current state equals the recorded target; otherwise preserve external changes.'}
    }
}

function Restore-ToolkitSession {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$SessionId,
          [string[]]$OptimizationId,[System.Collections.IDictionary]$FixtureState)
    Invoke-ToolkitSessionRestore @PSBoundParameters
}

Export-ModuleMember -Function Get-ToolkitRestoreStatus, Get-ToolkitRestorePreview, Restore-ToolkitSession
