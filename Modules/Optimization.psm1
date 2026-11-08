Set-StrictMode -Version Latest

function Get-ToolkitCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    # Windows PowerShell 5.1 emits a JSON array as a single pipeline object.
    # Assign first, then normalize: wrapping the pipeline in @() nests that array.
    $items = Get-Content -LiteralPath (Join-Path $Root 'Config/Optimizations.json') -Raw | ConvertFrom-Json
    $items = @($items)
    $ids = @{}
    foreach ($item in $items) {
        if ($ids.ContainsKey($item.id)) { throw "Duplicate optimization ID: $($item.id)" }
        $ids[$item.id] = $true
        if ($item.risk -notin @('Low', 'Moderate', 'High')) { throw "Invalid risk: $($item.id)" }
        if ($item.experimental -and $item.selectedByDefault) { throw 'Experimental settings cannot be selected by default.' }
    }
    $profiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'Profiles') -Filter '*.json' |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
    $profileIds = @{}
    foreach ($profile in $profiles) {
        if ($profileIds.ContainsKey($profile.id)) { throw "Duplicate profile ID: $($profile.id)" }
        $profileIds[$profile.id] = $true
        foreach ($id in $profile.optimizationIds) {
            if (-not $ids.ContainsKey($id)) { throw "Unknown optimization in profile: $id" }
        }
    }
    [pscustomobject]@{ Items = $items; Profiles = $profiles }
}

function New-ToolkitSelection {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile, [Parameter(Mandatory)][array]$Items,
          [Parameter(Mandatory)]$SystemInfo, [hashtable]$Observations = @{})
    foreach ($id in $Profile.optimizationIds) {
        $item = $Items | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if ($null -eq $item) { throw "Unknown optimization: $id" }
        Get-ToolkitRecommendation -Definition $item -SystemInfo $SystemInfo -Observations $Observations
    }
}

function Invoke-ToolkitSimulation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Selection)
    # Deliberately accepts data only. No registry, services, app removal or command dispatch.
    foreach ($entry in $Selection) {
        if (-not $entry.Selected) { continue }
        if (-not $entry.CanSelect -or $entry.Definition.experimental -or $entry.Availability -ne 'Supported' -or $entry.ReadState -ne 'Known' -or [string]::IsNullOrWhiteSpace($entry.ProposedState)) {
            throw "Cannot simulate unavailable or experimental setting: $($entry.Definition.id)"
        }
        [pscustomobject]@{
            Id = $entry.Definition.id; Title = $entry.Definition.title
            Status = 'SIMULATED'; Before = $entry.CurrentState
            Proposed = $entry.ProposedState; ChangedWindows = $false
            RestartRequired = $entry.Definition.restartRequired
        }
    }
}

Export-ModuleMember -Function Get-ToolkitCatalog, New-ToolkitSelection, Invoke-ToolkitSimulation
