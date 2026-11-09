Set-StrictMode -Version Latest

function Write-ToolkitLine {
    param([string]$Text = '', [ConsoleColor]$Color = 'Green')
    Write-Host $Text -ForegroundColor $Color
}

function Show-ToolkitHeader {
    param([string]$Title, [switch]$NoClear)
    if (-not $NoClear -and -not [Console]::IsOutputRedirected) { Clear-Host }
    Write-ToolkitLine '+------------------------------------------------------------------+'
    Write-ToolkitLine '|                 WINDOWS PERFORMANCE TOOLKIT                      |'
    Write-ToolkitLine '+------------------------------------------------------------------+'
    Write-ToolkitLine " $Title"
    Write-ToolkitLine ' PHASE 5 / DEFAULT: DRY-RUN / LIVE CHANGES REQUIRE VALIDATION + CONFIRMATION' Yellow
    Write-ToolkitLine ''
}

function Read-ToolkitInput {
    param([string]$Prompt = 'Selection')
    $answer = Read-Host " $Prompt >"
    if ($null -eq $answer) { throw 'Input closed. Use -Preview for non-interactive output.' }
    $answer.Trim().ToUpperInvariant()
}

function Wait-ToolkitInput { $null = Read-ToolkitInput 'Press Enter to continue' }

function Show-ToolkitInformation {
    param($Entry)
    $d = $Entry.Definition
    Show-ToolkitHeader $d.title
    foreach ($row in @(
        "Description: $($d.description)", "Current: $($Entry.CurrentState)",
        "Recommendation: $($Entry.Recommendation)", "Optional simulation target: $($Entry.ProposedState)", "Risk: $($d.risk)",
        "Restart after a real change: $($d.restartRequired)",
        "Compatibility: $($d.compatibility)", "Availability: $($Entry.Availability)",
        "Read state: $($Entry.ReadState)", "Reason: $($Entry.Reason)", "Source: $($Entry.Source)",
        "Evidence: $($d.expectedBenefit)", "Drawbacks: $($d.drawbacks)",
        'Mouse/animation engine operations support backed-up apply and restore after local validation; other items remain simulations.'
    )) { Write-ToolkitLine " $row" }
    foreach ($reference in $d.references) { Write-ToolkitLine " Reference: $reference" DarkGray }
    if ($d.experimental) { Write-ToolkitLine ' [WARN] Experimental/informational: selection is disabled.' Yellow }
    Wait-ToolkitInput
}

function Show-ToolkitDryRun {
    param([string[]]$OptimizationId, $SystemInfo)
    Show-ToolkitHeader 'ENGINE DRY RUN / NO CHANGES'
    $plan=@(New-ToolkitExecutionPlan -OptimizationId $OptimizationId -SystemInfo $SystemInfo)
    $results=@(Invoke-ToolkitEngine -Plan $plan -Mode DryRun)
    if ($results.Count -eq 0) { Write-ToolkitLine ' No settings selected.' Yellow }
    foreach ($result in $results) {
        Write-ToolkitLine " [$($result.Status)] $($result.Id)"
        Write-ToolkitLine " Reason: $($result.Reason)"
        Write-ToolkitLine " Scope: $($result.Scope) | Permission: $($result.Permission)"
        Write-ToolkitLine " Risk: $($result.Risk) | Restart after future real change: $($result.RestartRequired)"
        if ($null -ne $result.Original) { Write-ToolkitLine (' Original: ' + ($result.Original | ConvertTo-Json -Compress)) }
        if ($null -ne $result.Target) { Write-ToolkitLine (' Target:   ' + ($result.Target | ConvertTo-Json -Compress)) }
        Write-ToolkitLine " Drawbacks: $($result.Drawbacks)"
        Write-ToolkitLine " Verification: $($result.Verification)"
    }
    Write-ToolkitLine (Get-ToolkitExecutionPolicy).Reason Yellow
    Wait-ToolkitInput
}

function Show-ToolkitProfile {
    param($Profile, [array]$Items, $SystemInfo, [string]$HistoryDirectory, [hashtable]$Observations = @{}, [switch]$Comparison)
    $selection = @(New-ToolkitSelection -Profile $Profile -Items $Items -SystemInfo $SystemInfo -Observations $Observations)
    $showComparison = [bool]$Comparison
    $sortBy = 'Recommended'
    while ($true) {
        $selection = @(Get-ToolkitComparison -Selection $selection -SortBy $sortBy)
        Show-ToolkitHeader $Profile.title
        Write-ToolkitLine " $($Profile.description)"
        Write-ToolkitLine ' Read-only snapshot: stored preferences may differ from effective Windows policy.' DarkGray
        Write-ToolkitLine " Sort: $sortBy | Live apply requires local validation and confirmation."
        if ($showComparison) { Write-ToolkitLine ' OPTIMIZATION COMPARISON' Cyan }
        for ($i = 0; $i -lt $selection.Count; $i++) {
            $entry = $selection[$i]
            $mark = if ($entry.Selected) { 'ON ' } else { 'OFF' }
            $flag = if ($entry.AlreadyApplied) { ' [ALREADY CONFIGURED]' } elseif ($entry.Definition.experimental) { ' [EXPERIMENTAL]' } elseif ($entry.Availability -eq 'Unsupported') { ' [UNSUPPORTED]' } elseif ($entry.Availability -eq 'Unknown') { ' [UNKNOWN]' } elseif (-not $entry.CanSelect) { ' [REVIEW]' } else { '' }
            Write-ToolkitLine (' [{0:00}] [{1}] {2} / {3}{4}' -f ($i+1), $mark, $entry.Definition.title, $entry.Definition.risk, $flag)
            if ($showComparison) {
                Write-ToolkitLine "     CURRENT: $($entry.CurrentState)" DarkGray
                Write-ToolkitLine "     RECOMMENDED: $($entry.Recommendation)"
                Write-ToolkitLine "     COMPATIBILITY: $($entry.Availability) | RESTART (real change): $($entry.Definition.restartRequired)"
                Write-ToolkitLine "     WHY: $($entry.Reason)" DarkGray
            }
        }
        Write-ToolkitLine ''
        Write-ToolkitLine ' [number] Toggle  [I] Information  [R] Reset  [N] Select recommended'
        Write-ToolkitLine ' [V] Compare/list  [S] Sort  [D] Engine dry-run  [A] Simulate
 [L] Live apply selected engine settings  [B] Back'
        $choice = Read-ToolkitInput
        if ($choice -eq 'B') { return }
        if ($choice -eq 'L') {
            $ids=@($selection | Where-Object { $_.Selected } | ForEach-Object { $_.Definition.id })
            if ($ids.Count -eq 0) { Write-ToolkitLine ' No settings selected.' Yellow; Wait-ToolkitInput; continue }
            try { Invoke-ToolkitSession -Directory $HistoryDirectory -OptimizationId $ids | Format-List | Out-Host }
            catch { Write-ToolkitLine " [WARN] $($_.Exception.Message)" Yellow }
            Wait-ToolkitInput; continue
        }
        if ($choice -eq 'D') {
            $ids=@($selection | Where-Object { $_.Selected } | ForEach-Object { $_.Definition.id })
            Show-ToolkitDryRun -OptimizationId $ids -SystemInfo $SystemInfo
            continue
        }
        if ($choice -eq 'V') { $showComparison = -not $showComparison; continue }
        if ($choice -eq 'S') {
            Write-ToolkitLine ' [1] Recommended [2] Risk [3] Category [4] Restart [5] Already configured [6] Unsupported'
            $sortChoice = Read-ToolkitInput 'Sort order'
            $sorts = @{ '1'='Recommended'; '2'='Risk'; '3'='Category'; '4'='Restart'; '5'='Applied'; '6'='Unsupported' }
            if ($sorts.ContainsKey($sortChoice)) { $sortBy=$sorts[$sortChoice] }
            else { Write-ToolkitLine ' Invalid sort choice.' Yellow; Wait-ToolkitInput }
            continue
        }
        if ($choice -eq 'N') {
            foreach ($entry in $selection) { $entry.Selected = $entry.CanSelect -and $entry.RecommendedChange -and -not $entry.Definition.experimental }
            continue
        }
        if ($choice -eq 'R') {
            $selection = @(New-ToolkitSelection -Profile $Profile -Items $Items -SystemInfo $SystemInfo -Observations $Observations)
            continue
        }
        if ($choice -eq 'I') {
            $number = 0
            if ([int]::TryParse((Read-ToolkitInput 'Optimization number'), [ref]$number) -and $number -ge 1 -and $number -le $selection.Count) {
                Show-ToolkitInformation $selection[$number-1]
            } else { Write-ToolkitLine ' Invalid optimization number.' Yellow; Wait-ToolkitInput }
            continue
        }
        if ($choice -eq 'A') {
            $chosen = @($selection | Where-Object { $_.Selected })
            if ($chosen.Count -eq 0) { Write-ToolkitLine ' No settings selected.' Yellow; Wait-ToolkitInput; continue }
            Write-ToolkitLine ' SIMULATION PREVIEW' Cyan
            foreach ($entry in $chosen) {
                Write-ToolkitLine " $($entry.Definition.title): $($entry.CurrentState) -> $($entry.ProposedState)"
            }
            if ((Read-ToolkitInput 'Type SIMULATE to confirm') -ne 'SIMULATE') { continue }
            $results = @(Invoke-ToolkitSimulation -Selection $selection)
            foreach ($result in $results) { Write-ToolkitLine " [SIMULATED] $($result.Title)" Cyan }
            Write-ToolkitLine ' No settings were changed. No restart is needed for this simulation.'
            if ((Read-ToolkitInput 'Save simulation log locally? Y/N') -eq 'Y') {
                try {
                    $path = Save-ToolkitSimulation -Directory $HistoryDirectory -ProfileId $Profile.id -Results $results
                    Write-ToolkitLine " Saved: $path"
                } catch { Write-ToolkitLine " [FAIL] Could not save log: $($_.Exception.Message)" Red }
            }
            Wait-ToolkitInput
            continue
        }
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $selection.Count) {
            $entry = $selection[$number-1]
            if ($entry.CanSelect) { $entry.Selected = -not $entry.Selected }
            else { Write-ToolkitLine ' Unavailable or experimental setting; inspect Information for details.' Yellow; Wait-ToolkitInput }
        } else { Write-ToolkitLine ' Invalid selection.' Yellow; Wait-ToolkitInput }
    }
}

function Show-ToolkitSystemInfo {
    param($SystemInfo)
    Show-ToolkitHeader 'SYSTEM INFORMATION'
    foreach ($name in @('OS','Build','CPU','GPU','RAM','Storage','PowerPlan','Administrator','GamingSettings')) {
        Write-ToolkitLine (' {0,-16} {1}' -f $name, $SystemInfo.$name)
    }
    if ($null -ne $SystemInfo.PSObject.Properties['GPUDetails']) {
        foreach ($gpu in $SystemInfo.GPUDetails) { Write-ToolkitLine " GPU driver: $($gpu.Name) / $($gpu.DriverVersion)" }
    }
    if ($null -ne $SystemInfo.PSObject.Properties['HagsSupport']) { Write-ToolkitLine " HAGS capability: $($SystemInfo.HagsSupport.State) / $($SystemInfo.HagsSupport.Detail)" }
    foreach ($warning in $SystemInfo.Warnings) { Write-ToolkitLine " [WARN] $warning" Yellow }
}


function Read-ToolkitText {
    param([string]$Prompt)
    $answer=Read-Host " $Prompt >"
    if ($null -eq $answer) { throw 'Input closed.' }
    $answer.Trim()
}

function Show-ToolkitPerformance {
    param([string]$Directory)
    $lastReport=$null
    while ($true) {
        Show-ToolkitHeader 'PERFORMANCE COMPARISON'
        Write-ToolkitLine ' CPU / RAM snapshots are not proof of FPS improvement.' Yellow
        Write-ToolkitLine ' [1] Capture Before  [2] Capture After  [3] List captures'
        Write-ToolkitLine ' [4] Compare captures  [5] Import benchmark summary  [6] Export last comparison'
        Write-ToolkitLine ' [B] Back'
        $choice=Read-ToolkitInput
        if ($choice -eq 'B') { return }
        try {
            switch ($choice) {
                {$_ -in @('1','2')} {
                    $label=if ($choice -eq '1') {'Before'} else {'After'}
                    Write-ToolkitLine ' Capturing three CPU samples, one second apart, and current system/configuration data...'
                    $snapshot=Get-ToolkitPerformanceSnapshot -Label $label
                    $saved=Save-ToolkitPerformanceSnapshot -Directory $Directory -Snapshot $snapshot
                    Write-ToolkitLine " Saved $label capture: $($saved.Id)"
                    $snapshot.Metrics | Format-Table Id,Value,Unit,Status -AutoSize | Out-Host
                }
                '3' {
                    Get-ToolkitPerformanceHistory -Directory $Directory | Select-Object Id,Label,CapturedUtc,Origin | Format-Table -AutoSize | Out-Host
                }
                '4' {
                    $beforeId=(Read-ToolkitText 'Before measurement ID').ToLowerInvariant()
                    $afterId=(Read-ToolkitText 'After measurement ID').ToLowerInvariant()
                    $before=Read-ToolkitPerformanceSnapshot -Directory $Directory -Id $beforeId
                    $after=Read-ToolkitPerformanceSnapshot -Directory $Directory -Id $afterId
                    $lastReport=Compare-ToolkitPerformance -Before $before -After $after
                    @($lastReport.Metrics)+@($lastReport.Configuration)+@($lastReport.Benchmarks) | Format-Table Category,Metric,Before,After,Delta,Unit,Status -Wrap | Out-Host
                    foreach ($warning in $lastReport.Warnings) { Write-ToolkitLine " [NOTE] $warning" Yellow }
                }
                '5' {
                    $id=(Read-ToolkitText 'Measurement ID to attach results to').ToLowerInvariant()
                    $path=Read-ToolkitText 'Path to normalized benchmark summary JSON/CSV (no surrounding quotes)'
                    $original=Read-ToolkitPerformanceSnapshot -Directory $Directory -Id $id
                    $updated=Add-ToolkitBenchmarkToSnapshot -Snapshot $original -Path $path
                    $saved=Save-ToolkitPerformanceSnapshot -Directory $Directory -Snapshot $updated
                    Write-ToolkitLine " Saved derived measurement: $($saved.Id). Use this NEW ID when comparing imported results."
                }
                '6' {
                    if ($null -eq $lastReport) { Write-ToolkitLine ' Compare two captures first.' Yellow }
                    else {
                        $folder=Join-Path $Directory 'Reports'
                        $stem='comparison-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')
                        foreach ($format in @('JSON','Markdown','CSV')) {
                            $extension=@{JSON='json';Markdown='md';CSV='csv'}[$format]
                            $path=Export-ToolkitPerformanceReport -Report $lastReport -Path (Join-Path $folder ($stem+'.'+$extension)) -Format $format
                            Write-ToolkitLine " Saved: $path"
                        }
                    }
                }
                default { Write-ToolkitLine ' Invalid selection.' Yellow }
            }
        } catch { Write-ToolkitLine " [WARN] $($_.Exception.Message)" Yellow }
        Wait-ToolkitInput
    }
}

function Show-ToolkitDashboard {
    param($Catalog, $SystemInfo, [string]$Version, [switch]$NoClear)
    Show-ToolkitHeader "DASHBOARD / v$Version" -NoClear:$NoClear
    Write-ToolkitLine " OS: $($SystemInfo.OS)"
    Write-ToolkitLine " CPU: $($SystemInfo.CPU)"
    Write-ToolkitLine " GPU: $($SystemInfo.GPU) | RAM: $($SystemInfo.RAM)"
    Write-ToolkitLine " Power plan: $($SystemInfo.PowerPlan)"
    foreach ($warning in $SystemInfo.Warnings) { Write-ToolkitLine " [WARN] $warning" Yellow }
    Write-ToolkitLine ''
    for ($i=0; $i -lt $Catalog.Profiles.Count; $i++) {
        Write-ToolkitLine (' [{0}] {1}' -f ($i+1), $Catalog.Profiles[$i].title)
    }
    Write-ToolkitLine ' [O] Optimization comparison (all options)  [D] Engine dry-run'
    Write-ToolkitLine ' [S] System information  [H] Simulation history  [R] Session history / restore'
    Write-ToolkitLine ' [T] Validate native apply/restore on this PC (requires confirmation)'
    Write-ToolkitLine ' [L] Backed-up live apply: mouse + animations (requires confirmation)'
    Write-ToolkitLine ' [P] Performance captures, comparisons and reports'
    Write-ToolkitLine ' [C] Settings / roadmap  [0] Exit'
}

function Start-ToolkitInterface {
    [CmdletBinding()]
    param($Catalog, $SystemInfo, $Settings, [string]$HistoryDirectory, [hashtable]$Observations = @{})
    while ($true) {
        Show-ToolkitDashboard -Catalog $Catalog -SystemInfo $SystemInfo -Version $Settings.version
        $choice = Read-ToolkitInput
        switch ($choice) {
            '0' { return }
            'P' { Show-ToolkitPerformance -Directory $HistoryDirectory; continue }
            'D' {
                Show-ToolkitDryRun -OptimizationId @('mouse','animations') -SystemInfo $SystemInfo
                continue
            }
            'O' {
                $custom = $Catalog.Profiles | Where-Object { $_.id -eq 'custom' } | Select-Object -First 1
                Show-ToolkitProfile -Profile $custom -Items $Catalog.Items -SystemInfo $SystemInfo -HistoryDirectory $HistoryDirectory -Observations $Observations -Comparison
                continue
            }
            'S' { Show-ToolkitSystemInfo $SystemInfo; Wait-ToolkitInput; continue }
            'L' {
                try { Invoke-ToolkitSession -Directory $HistoryDirectory | Format-List | Out-Host }
                catch { Write-ToolkitLine " [WARN] $($_.Exception.Message)" Yellow }
                Wait-ToolkitInput; continue
            }
            'T' {
                try { Invoke-ToolkitSession -Directory $HistoryDirectory -ValidateNative | Format-List | Out-Host }
                catch { Write-ToolkitLine " [WARN] $($_.Exception.Message)" Yellow }
                Wait-ToolkitInput; continue
            }
            'R' {
                Show-ToolkitHeader 'RESTORATION / SESSION HISTORY'
                Write-ToolkitLine (Get-ToolkitRestoreStatus).Message Yellow
                try {
                    $sessions=@(Get-ToolkitSessionHistory -Directory $HistoryDirectory -Context (Get-ToolkitContext))
                    foreach ($session in $sessions) { Write-ToolkitLine " $($session.SessionId) | $($session.Status) | $($session.CreatedUtc)" }
                    if ($sessions.Count -eq 0) { Write-ToolkitLine ' No native session backups.' }
                    else {
                        $id=Read-ToolkitInput 'Session ID to restore, or B to go back'
                        if ($id -ne 'B') {
                            $id=$id.ToLowerInvariant()
                            Get-ToolkitRestorePreview -Directory $HistoryDirectory -SessionId $id | Format-List | Out-Host
                            $setting=Read-ToolkitInput 'Setting ID (mouse/animations), or ALL for full rollback'
                            if ($setting -eq 'ALL') { Restore-ToolkitSession -Directory $HistoryDirectory -SessionId $id | Format-List | Out-Host }
                            else { Restore-ToolkitSession -Directory $HistoryDirectory -SessionId $id -OptimizationId $setting.ToLowerInvariant() | Format-List | Out-Host }
                        }
                    }
                } catch { Write-ToolkitLine " [WARN] $($_.Exception.Message)" Yellow }
                Wait-ToolkitInput; continue
            }
            'H' {
                Show-ToolkitHeader 'SIMULATION HISTORY / NO REAL OPTIMIZATIONS'
                $history = @(Get-ToolkitSimulationHistory -Directory $HistoryDirectory)
                if ($history.Count -eq 0) { Write-ToolkitLine ' No saved simulations.' }
                foreach ($record in $history) {
                    Write-ToolkitLine " $($record.TimestampUtc) | $($record.ProfileId) | $(@($record.Results).Count) simulated items"
                }
                Wait-ToolkitInput; continue
            }
            'C' {
                Show-ToolkitHeader 'SETTINGS / ROADMAP'
                Write-ToolkitLine " Version: $($Settings.version) | Theme: $($Settings.theme)"
                Write-ToolkitLine " Optional simulation logs: $HistoryDirectory"
                Write-ToolkitLine ' Phase 5: baseline measurements, benchmark imports and reports (current)'
                Write-ToolkitLine ' Next: release packaging and distribution.'
                Write-ToolkitLine ' Native apply requires successful local validation; default mode remains dry-run.'
                Wait-ToolkitInput; continue
            }
        }
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $Catalog.Profiles.Count) {
            Show-ToolkitProfile -Profile $Catalog.Profiles[$number-1] -Items $Catalog.Items -SystemInfo $SystemInfo -HistoryDirectory $HistoryDirectory -Observations $Observations
        } elseif ($choice -notin @('P','D','L','T','O','S','R','H','C')) {
            Write-ToolkitLine ' Invalid selection.' Yellow; Wait-ToolkitInput
        }
    }
}

Export-ModuleMember -Function Show-ToolkitDashboard, Show-ToolkitSystemInfo, Start-ToolkitInterface
