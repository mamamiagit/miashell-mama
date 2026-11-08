Set-StrictMode -Version Latest

function Get-ToolkitRecommendation {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Definition, [Parameter(Mandatory)]$SystemInfo,
          [hashtable]$Observations = @{})
    $d = $Definition
    $entry = [pscustomobject]@{
        Definition=$d; Selected=$false; CanSelect=$false; CurrentState='Unknown (not read)'
        ReadState='Unknown'; Availability='Unknown'; Recommendation='Review manually'
        Reason='This option needs an individual decision; no automatic change is recommended.'
        RecommendedChange=$false; AlreadyApplied=$false; ProposedState=''; Source='Windows Settings (manual review)'
    }
    if (-not $SystemInfo.IsWindows -or $SystemInfo.Build -lt $d.minimumBuild -or $SystemInfo.Build -ge 30000 -or
        ($null -ne $SystemInfo.PSObject.Properties['ProductType'] -and $SystemInfo.ProductType -ne 1)) {
        $entry.Availability='Unsupported'
        $entry.Reason='Requires a supported Windows 10/11 client build. Non-Windows, Server, unknown, and future builds are not assumed compatible.'
        return $entry
    }
    $entry.Availability='Supported'
    if ($d.experimental -and $d.id -ne 'hags') {
        $entry.Availability='Unsupported'; $entry.Recommendation='Keep default'
        $entry.Reason='Unsupported priority/registry tweaks are excluded.'; return $entry
    }
    $observation = $null
    if ($Observations.ContainsKey($d.id)) { $observation=$Observations[$d.id] }
    if ($null -ne $observation) {
        $entry.ReadState=$observation.State; $entry.Source=$observation.Source
        if ($observation.State -eq 'Known') { $entry.CurrentState="Stored value: $($observation.Value)" }
        else { $entry.CurrentState="Unknown ($($observation.State)): $($observation.Detail)" }
    }
    # Administrative policies are never overridden or reinterpreted as user defaults.
    $policyKeys = switch ($d.id) {
        'game-dvr' { 'dvr-policy'; 'dvr-mdm' }
        'advertising' { 'advertising-policy' }
        'diagnostics' { 'diagnostics-policy' }
        'widgets' { 'widgets-policy' }
    }
    foreach ($key in @($policyKeys)) {
        if ($Observations.ContainsKey($key) -and $Observations[$key].State -ne 'Missing') {
            $entry.Availability='Unknown'; $entry.Recommendation='Review policy'
            $entry.Reason='A policy value or policy-read error was found. Effective policy and user preference may differ; no change is selected.'
            $entry.Source=$Observations[$key].Source
            if ($Observations[$key].State -eq 'Known') { $entry.CurrentState="Policy configured: $($Observations[$key].Value); user preference not treated as effective state" }
            return $entry
        }
    }
    if ($d.id -eq 'hags') {
        $support = [pscustomobject]@{ State='Unknown'; Detail='No verified GPU/driver capability report.' }
        if ($null -ne $SystemInfo.PSObject.Properties['HagsSupport']) { $support=$SystemInfo.HagsSupport }
        $entry.Availability=$support.State
        $entry.Recommendation='Test both (only on confirmed supported hardware)'
        $entry.Reason=$support.Detail
        if ($null -ne $observation -and $observation.State -eq 'Known') {
            if ("$($observation.Value)" -eq '2') { $entry.CurrentState='Enabled preference (effective state not verified)' }
            elseif ("$($observation.Value)" -eq '1') { $entry.CurrentState='Disabled preference (effective state not verified)' }
            else { $entry.CurrentState='Unknown HAGS preference value'; $entry.ReadState='Unknown' }
        }
        # Experimental comparison only; never preselected, even with a capability report.
        return $entry
    }
    if ($d.id -in @('power','usb','pcie')) {
        $entry.Recommendation='Keep current / default'
        $entry.Reason='No universal gaming benefit. Higher power usage and heat are possible; change only for a measured troubleshooting need.'
        if ($d.id -eq 'power' -and $null -ne $SystemInfo.PSObject.Properties['PowerPlan']) {
            $entry.CurrentState=$SystemInfo.PowerPlan
            if ($SystemInfo.PowerPlan -ne 'Unavailable') { $entry.ReadState='Known'; $entry.Source='Win32_PowerPlan (active plan)' }
        }
        if ($null -ne $SystemInfo.PSObject.Properties['IsPortable'] -and $SystemInfo.IsPortable) { $entry.Reason += ' Portable system detected: preserve battery life.' }
        return $entry
    }
    if ($d.id -in @('startup','apps','notifications','suggestions','diagnostics','active-hours','widgets')) {
        switch ($d.id) {
            'startup' { $entry.CurrentState='Review startup apps individually in Windows Settings'; $entry.Recommendation='Review individual entries' }
            'apps' { $entry.CurrentState='App removal is not implemented'; $entry.Recommendation='Review individual apps'; $entry.Reason='Preserve Store, Security, Edge and system dependencies; removal may require reinstalling.' }
            'notifications' { $entry.CurrentState='Review per-app notifications and Do not disturb'; $entry.Reason='Notification preferences are app- and Windows-version-specific.' }
            'suggestions' { $entry.Recommendation='Review personalization preference'; $entry.Reason='Stored value covers tailored experiences only, not every Windows suggestion.' }
            'diagnostics' { $entry.Recommendation='Review supported diagnostic data options'; $entry.Reason='Diagnostic policy levels depend on Windows edition/build. A stored value does not prove effective data collection.' }
            'widgets' { $entry.Recommendation='User preference'; $entry.Reason='Stored taskbar visibility is not proof that Widgets is installed or available on this Windows build.' }
            'active-hours' {
                $entry.Recommendation='Review active hours; keep updates enabled'
                if ($Observations.ContainsKey('active-start') -and $Observations.ContainsKey('active-end')) {
                    $start=$Observations['active-start']; $end=$Observations['active-end']
                    if ($start.State -eq 'Known' -and $end.State -eq 'Known' -and "$($start.Value)" -match '^([0-9]|1[0-9]|2[0-3])$' -and "$($end.Value)" -match '^([0-9]|1[0-9]|2[0-3])$') {
                        $entry.CurrentState=('Stored active hours: {0:00}:00 - {1:00}:00 (automatic scheduling/policy not resolved)' -f [int]$start.Value,[int]$end.Value)
                        $entry.ReadState='Known'; $entry.Source="$($start.Source); $($end.Source)"
                    }
                }
            }
        }
        # Grouped settings have no unambiguous single operation to simulate.
        return $entry
    }
    if ($null -eq $observation -or $observation.State -ne 'Known') {
        $entry.Availability='Unknown'; $entry.Reason='Current preference could not be established. Check Windows Settings; no assumed defaults or automatic selection.'
        return $entry
    }
    $value = "$($observation.Value)"
    if ($d.id -eq 'mouse') {
        if ($value -notin @('0','1','2')) { $entry.Availability='Unknown'; $entry.Reason='Unrecognized mouse acceleration value.'; return $entry }
        $entry.CurrentState = if ($value -eq '0') { 'Acceleration disabled (stored preference)' } else { 'Acceleration enabled (stored preference)' }
        $entry.Recommendation='Disable acceleration only if preferred'; $entry.Reason='Pointer preference; games using raw input may ignore it. No FPS claim.'
        $entry.CanSelect=$value -ne '0'; $entry.ProposedState='Acceleration disabled'
        return $entry
    }
    if ($value -notin @('0','1')) { $entry.Availability='Unknown'; $entry.Reason='Unrecognized stored value; no default is assumed.'; return $entry }
    $entry.CurrentState = if ($value -eq '1') { 'Enabled (stored preference)' } else { 'Disabled (stored preference)' }
    switch ($d.id) {
        'game-mode' {
            $entry.Recommendation='Enable'
            $entry.Reason='Game Mode can prioritize a gaming workload. Benefits vary; there is no measured FPS claim.'
            $entry.AlreadyApplied=$value -eq '1'
            $entry.RecommendedChange=$value -eq '0'; $entry.CanSelect=$entry.RecommendedChange
            $entry.Selected=$entry.RecommendedChange; $entry.ProposedState='Enabled'
        }
        'game-dvr' {
            $entry.Recommendation='Disable background recording only if unused'
            $entry.Reason='App capture and background recording are different preferences. Confirm capture usage before changing either.'
            $entry.CurrentState="App capture: $($entry.CurrentState); background recording unknown"
            if ($Observations.ContainsKey('dvr-background') -and $Observations['dvr-background'].State -eq 'Known') {
                $background="$($Observations['dvr-background'].Value)"
                if ($background -in @('0','1')) {
                    $entry.CurrentState += "; stored background recording: $background"
                    $entry.Source += "; $($Observations['dvr-background'].Source)"
                    $entry.CanSelect=$background -eq '1'; $entry.ProposedState='Background recording disabled'
                }
            }
        }
        'advertising' { $entry.CanSelect=$value -eq '1'; $entry.ProposedState='Advertising ID disabled'; $entry.Recommendation='Disable if unwanted'; $entry.Reason='Privacy preference only; no gaming performance benefit is claimed.' }
        'animations' { $entry.CanSelect=$value -eq '1'; $entry.ProposedState='Minimize/maximize animations disabled'; $entry.Recommendation='Disable only if preferred'; $entry.Reason='This is the minimize/maximize animation preference, not every Windows animation. No guaranteed gaming improvement.' }
        'transparency' { $entry.CanSelect=$value -eq '1'; $entry.ProposedState='Transparency disabled'; $entry.Recommendation='Disable only if preferred'; $entry.Reason='Desktop appearance preference; any resource savings depend on workload and hardware.' }
    }
    $entry
}

function Get-ToolkitComparison {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Selection,
          [ValidateSet('Recommended','Risk','Category','Restart','Applied','Unsupported')][string]$SortBy='Recommended')
    $rank = @{ Low=0; Moderate=1; High=2 }
    switch ($SortBy) {
        'Recommended' { $Selection | Sort-Object @{Expression={ if ($_.RecommendedChange) { 0 } else { 1 } }}, @{Expression={$_.Definition.title}} }
        'Risk' { $Selection | Sort-Object @{Expression={$rank[$_.Definition.risk]}}, @{Expression={$_.Definition.title}} }
        'Category' { $Selection | Sort-Object @{Expression={$_.Definition.category}}, @{Expression={$_.Definition.title}} }
        'Restart' { $Selection | Sort-Object @{Expression={$_.Definition.restartRequired}}, @{Expression={$_.Definition.title}} }
        'Applied' { $Selection | Sort-Object @{Expression={ if ($_.AlreadyApplied) { 0 } else { 1 } }}, @{Expression={$_.Definition.title}} }
        'Unsupported' { $Selection | Sort-Object @{Expression={ if ($_.Availability -eq 'Unsupported') { 0 } elseif ($_.Availability -eq 'Unknown') { 1 } else { 2 } }}, @{Expression={$_.Definition.title}} }
    }
}

Export-ModuleMember -Function Get-ToolkitRecommendation, Get-ToolkitComparison
