Set-StrictMode -Version Latest

function Get-ToolkitCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $items = @(Get-Content -LiteralPath (Join-Path $Root 'Config/Optimizations.json') -Raw | ConvertFrom-Json)
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
          [Parameter(Mandatory)]$SystemInfo)
    foreach ($id in $Profile.optimizationIds) {
        $item = $Items | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if ($null -eq $item) { throw "Unknown optimization: $id" }
        $availability = 'Compatibility not yet validated'
        if (-not $SystemInfo.IsWindows) { $availability = 'Preview only: non-Windows host' }
        elseif ($SystemInfo.Build -gt 0 -and $SystemInfo.Build -lt $item.minimumBuild) { $availability = 'Unsupported Windows build' }
        $eligible = $SystemInfo.IsWindows -and $SystemInfo.Build -ge $item.minimumBuild
        [pscustomobject]@{
            Definition = $item
            Selected = ($eligible -and $item.selectedByDefault -and -not $item.experimental)
            CanSelect = ($eligible -and -not $item.experimental)
            CurrentState = 'Not detected in Phase 1'
            Availability = $availability
        }
    }
}

function Invoke-ToolkitSimulation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Selection)
    # Deliberately accepts data only. No registry, services, app removal or command dispatch.
    foreach ($entry in $Selection) {
        if (-not $entry.Selected) { continue }
        if (-not $entry.CanSelect -or $entry.Definition.experimental) {
            throw "Cannot simulate unavailable or experimental setting: $($entry.Definition.id)"
        }
        [pscustomobject]@{
            Id = $entry.Definition.id; Title = $entry.Definition.title
            Status = 'SIMULATED'; Before = $entry.CurrentState
            Proposed = $entry.Definition.recommended; ChangedWindows = $false
            RestartRequired = $entry.Definition.restartRequired
        }
    }
}

Export-ModuleMember -Function Get-ToolkitCatalog, New-ToolkitSelection, Invoke-ToolkitSimulation
