# Windows Performance Toolkit

A Windows 10/11 optimization and debloat toolkit with a black-and-neon-green PowerShell interface.

**Version 0.6.0 — Phase 6: verified distribution.** Versioned ZIP packages, published SHA-256 checksums, per-file manifests, side-by-side local/offline installs, a Windows launcher and an optional update checker. Installation never executes the downloaded app. The toolkit still defaults to dry-run; live mouse/animation operations require local validation, durable backups and confirmation.

## Run on Windows

Use Windows PowerShell 5.1 (already installed on Windows 10/11) or PowerShell 7. No administrator permissions are needed for ordinary use or per-user installation.

For a source ZIP: right-click the ZIP **before extracting** → **Properties → Unblock → Apply**. Extract, then double-click `Launch.cmd`, or open PowerShell in the folder containing Start.ps1:

```powershell
powershell.exe -NoProfile -File .\Start.ps1
```

If already extracted from a trusted source, unblock its scripts first:

```powershell
Get-ChildItem -Recurse -File -Include *.ps1,*.psm1 | Unblock-File
powershell.exe -NoProfile -File .\Start.ps1
```

Unblocking removes the download marker; it does not bypass execution policy or satisfy an organization requiring signed scripts. This project does not ship an Authenticode certificate. With PowerShell 7 installed, `pwsh` can replace `powershell.exe`. Ordinary startup makes no network requests.

## Phase 6: verified release installation

Use the assets under [GitHub Releases](https://github.com/mamamiagit/miashell-mama/releases), not GitHub's automatically generated source ZIP, for verified installation. A version tag builds a **draft** release only after compatibility and package checks pass; draft assets are not available to the public downloader until a maintainer publishes the release.

### Portable/offline release

Download `WindowsPerformanceToolkit-0.6.0.zip` and `WindowsPerformanceToolkit-0.6.0.zip.sha256` from the same trusted release. Verify the archive before extracting or running any script:

```powershell
$package = '.\WindowsPerformanceToolkit-0.6.0.zip'
$checksum = '.\WindowsPerformanceToolkit-0.6.0.zip.sha256'
$expected = ((Get-Content -LiteralPath $checksum -Raw).Trim() -split '\s+')[0]
$actual = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash
if ($expected -notmatch '^[a-fA-F0-9]{64}$' -or $actual -ine $expected) {
    throw 'Checksum mismatch. Do not extract or run this package.'
}
Unblock-File -LiteralPath $package
Expand-Archive -LiteralPath $package -DestinationPath .\WindowsPerformanceToolkit-0.6.0
```

Review the extracted files. Double-click `Launch.cmd` to run portably/offline. Optionally, from the extracted folder, install a verified copy into a versioned per-user directory:

```powershell
powershell.exe -NoProfile -File .\Install.ps1 -PackagePath ..\WindowsPerformanceToolkit-0.6.0.zip -ChecksumPath ..\WindowsPerformanceToolkit-0.6.0.zip.sha256
```

The installer verifies the archive and every manifested file, rejects unsafe ZIP paths, stages and verifies contents, unblocks only verified PowerShell files on Windows, then publishes the whole version directory. It prints `LaunchPath`; run that launcher yourself. Existing version folders and recovery data are never replaced.

Default install location: `%LOCALAPPDATA%\WindowsPerformanceToolkit\Versions\0.6.0`. Use `-DestinationRoot` to choose another versions folder. Application data remains in `%LOCALAPPDATA%\WindowsPerformanceToolkit`, separate from installed versions. No profile, PATH, registry, execution-policy or administrator changes are made.

SHA-256 checks establish consistency with the published checksum, **not** an independent publisher signature. Trust the release/source you obtain the checksum and initial installer from. See [distribution design](Docs/DISTRIBUTION.md).

### Explicit online install and update checks

From an already reviewed source/release folder, this downloads only the selected version's assets from this repository, verifies them, and installs without starting code:

```powershell
powershell.exe -NoProfile -File .\Install.ps1 -Version 0.6.0
```

No arbitrary GitHub/script URL is accepted. Online installation needs a **published** release; a draft or missing version fails without installing it. Use the offline route with downloaded assets when disconnected.

Choose **U** on the dashboard, or run:

```powershell
powershell.exe -NoProfile -File .\Start.ps1 -CheckUpdates
```

Update checks are opt-in and informational only: they never download or install updates. Offline/rate-limited/missing-release responses show Unavailable, not a false “up to date.” To update, explicitly install a new version side by side, inspect it, and launch it. Keep old versions and all session backups until restoration needs are resolved.

## Performance comparison (Phase 5)

Choose **P** on the dashboard for performance captures and reports:

1. Capture **Before** with the background workload you want to compare.
2. Make your explicitly selected changes, restart if needed, then recreate the same workload.
3. Capture **After**, list saved IDs, and compare the two captures.
4. Optionally import actual external benchmark summaries for each side. Imports create new derived IDs; use those new IDs for the gaming comparison.
5. Export the last comparison as JSON, CSV and Markdown with menu option **6**.

Captures include sampled CPU utilization, physical-memory usage/availability, process count, startup-command inventory, uptime, power plan, GPU drivers and configuration observations. Missing readings stay unavailable. CPU defaults to three samples one second apart; this is a lightweight resource snapshot, not a controlled benchmark.

**Fewer processes or lower idle RAM do not prove higher gaming FPS.** Benchmark deltas require matching declared game/scene/settings/tool/duration/run count and hardware/driver context. No FPS or frame-time values are generated by the toolkit. Raw PresentMon/CapFrameX frame CSV is not automatically parsed; import the documented normalized summary format instead. See [performance measurement and benchmark guide](Docs/PERFORMANCE.md).

CLI examples (replace ID placeholders with saved 32-character measurement IDs):

```powershell
powershell.exe -NoProfile -File .\Start.ps1 -CaptureMeasurement Before
powershell.exe -NoProfile -File .\Start.ps1 -CaptureMeasurement After
powershell.exe -NoProfile -File .\Start.ps1 -MeasurementHistory
powershell.exe -NoProfile -File .\Start.ps1 -CompareMeasurements -BeforeId BEFORE_ID -AfterId AFTER_ID -ReportPath .\comparison.md
```

Optional benchmark attachment and other export formats:

```powershell
powershell.exe -NoProfile -File .\Start.ps1 -ImportBenchmark .\before-summary.json -MeasurementId BEFORE_ID
powershell.exe -NoProfile -File .\Start.ps1 -CompareMeasurements -BeforeId BEFORE_WITH_BENCHMARK_ID -AfterId AFTER_WITH_BENCHMARK_ID -ReportFormat CSV -ReportPath .\comparison.csv
```

Records use the existing Local AppData folder under `Measurements/`; UI exports go under `Reports/`. Reports omit SID/machine name and source-file paths, but include hardware, labels and benchmark conditions. Existing export files are never overwritten.

## Phase 4 backups and restoration

- Timestamped session records with original values, intended targets, checksums, write-ahead history and atomic file replacement.
- Per-setting restore and full session rollback, with post-write verification and automatic rollback when an apply fails.
- Recovery of interrupted sessions; protection against stale plans, conflicting external changes, corrupt backups, and concurrent toolkit operations.
- An explicit local native validation step before normal live use. Fixture tests do not unlock Windows writes.
- Backups in `%LOCALAPPDATA%\WindowsPerformanceToolkit` by default, so downloading a new ZIP does not discard recovery data. Keep this folder.

**Only mouse acceleration and minimize/restore animation support live changes.** The mouse operation preserves both thresholds and pointer speed. No registry edits, app removal, security changes, service changes or Windows Update changes are performed.

### First-time native validation

After reviewing the dry run, choose **T** on the dashboard, or run:

```powershell
powershell.exe -NoProfile -File .\Start.ps1 -ValidateNative
```

This asks for confirmation, saves originals, temporarily sets both supported preferences, verifies them, restores the originals, and verifies restoration. It genuinely calls the Windows setting APIs; it is not a simulation. Leave the toolkit open until it finishes. A validation marker is created only after both restorations succeed. It is specific to the current Windows user/machine, OS build and implementation, and expires after 30 days. If validation fails or is interrupted, use **R** to inspect/recover the saved session before trying again.

### Apply and restore

Choose **L** on the dashboard to review and apply the two supported settings, or use a single operation:

```powershell
powershell.exe -NoProfile -File .\Start.ps1 -Apply -OptimizationId mouse
powershell.exe -NoProfile -File .\Start.ps1 -ListSessions
# Replace SESSION_ID with the 32-character ID shown in the result/history:
powershell.exe -NoProfile -File .\Start.ps1 -RestoreSession SESSION_ID
# Or restore only one setting:
powershell.exe -NoProfile -File .\Start.ps1 -RestoreSession SESSION_ID -RestoreId mouse
```

Live apply and restore require confirmation. Recovery remains available without a current validation marker. Already configured operations are skipped. A partial restore or conflict is not reported as complete recovery. The toolkit never forces a preference over a conflicting external change; inspect Windows Settings and session history instead. New mutations are blocked while a session is unfinished or an overlapping setting remains applied in another session.

The optional `-CreateRestorePoint` flag on `-Apply` attempts a Windows restore point only when supported and already elevated, then verifies it exists. It never elevates automatically. Unsupported, rate-limited or failed restore points produce a warning; the toolkit still requires its own durable backups. No restore point is assumed successful.

See [backup and recovery details](Docs/BACKUP-RESTORE.md) and [engine design](Docs/ENGINE.md). Native Windows behavior is not established by the Linux fixture suite; local validation is required before normal use.

## Phase 2 features retained

- Fixed read-only preference queries for gaming, input, desktop effects, privacy, Widgets visibility, and active hours.
- Separate **Known**, **Missing**, and **Error** read outcomes; missing values never become guessed defaults.
- Recommendations include reasons, risks, restart requirements, current observations and data sources. Stored preferences are distinguished from effective Windows behavior.
- Windows build/client checks, laptop power advice, GPU/driver metadata, and conservative HAGS capability checks.
- Comparison sorting by recommended changes, risk, category, restart, already configured, or unsupported.
- Administrative capture/privacy policy observations stop conflicting recommendations.

Known disabled Game Mode is currently the only automatically selected simulation. Known enabled privacy, appearance, mouse, and background-recording preferences can be selected manually for a clearly labeled optional simulation; none is preselected. Grouped app settings remain individual review items. HAGS and priority tweaks are never selected automatically. A result labeled “already configured” means the observed preference matches the recommendation; it does not mean a measured performance improvement.

## Interface

Seven profiles cover Balanced Gaming (default), Competitive Gaming, Low-End PC, Windows Debloat, Privacy Focused, System Responsiveness, and Custom.

- Dashboard: **U** optionally checks published updates; **P** opens performance captures and reports; **D** previews engine operations; **O** opens the comparison of all 18 options; **S** shows hardware and GPU driver details.
- Inside a profile: **V** switches between comparison and compact list; **S** chooses one of six sorting orders.
- **I** opens an item's explanation, drawbacks and sources. Numbers refer to the currently displayed order.
- **N** selects available recommended changes; numbers toggle eligible entries; **R** resets the selection.
- **A** previews selected options and asks you to type `SIMULATE`. It never applies a Windows change. **L** applies only reviewed engine IDs after validation, backup and confirmation.
- Optional simulation logs appear under **H**. **R** lists native session backups and restores one setting or a full session. Simulation logs are not backups.

Observations are a startup snapshot. Restart the toolkit after changing Windows Settings or drivers. Current custom selections last only for that profile visit. On Windows, logs and backups use `%LOCALAPPDATA%\WindowsPerformanceToolkit`; non-Windows previews use `Data/`. Use `-DataDirectory` consistently if selecting a different store. Do not switch stores while settings remain applied, and do not delete recovery data with an old downloaded source folder.

## Non-interactive output

```powershell
powershell.exe -NoProfile -File .\Start.ps1 -Preview
powershell.exe -NoProfile -File .\Start.ps1 -SystemInfoOnly
powershell.exe -NoProfile -File .\Start.ps1 -Compare -SortBy Risk
powershell.exe -NoProfile -File .\Start.ps1 -DryRun
powershell.exe -NoProfile -File .\Start.ps1 -DryRun -OptimizationId mouse
```

`-Compare` returns structured objects when called from an existing PowerShell session:

```powershell
.\Start.ps1 -Compare -SortBy Recommended |
    Format-Table Optimization, CurrentState, Recommendation, Availability, Risk -Wrap
```

In an existing PowerShell session, use `.\Start.ps1 -DryRun -OptimizationId mouse,animations` to supply multiple operation IDs. `-DryRun` returns structured plans and never applies them. No administrator prompt is needed; an interactive Windows desktop is required for live API reads. A blocked or unreadable setting is reported without guessing.

Supported sort names: `Recommended`, `Risk`, `Category`, `Restart`, `Applied`, `Unsupported`.

### Optional HAGS report

A GPU name, driver version, or stored HAGS preference alone cannot establish hardware scheduling support. Without verified capability evidence, HAGS stays **Unknown**. To supply a local DirectX Diagnostic XML report:

```powershell
dxdiag /x "$env:TEMP\toolkit-dxdiag.xml"
# Wait for dxdiag to finish writing the report, then:
powershell.exe -NoProfile -File .\Start.ps1 -DxDiagPath "$env:TEMP\toolkit-dxdiag.xml"
```

The reader requires matching GPU names/driver versions, WDDM 2.7+, and explicit stable scheduling support for every detected adapter. Missing fields, mixed adapters, stale drivers, and malformed XML stay unknown. Re-export after driver/hardware changes. Even a supported result leaves HAGS experimental and unselected. This XML format varies across Windows builds; lack of a matching field is not proof that HAGS is unsupported.

## Validate

No test framework installation is needed:

```powershell
powershell.exe -NoProfile -File .\Tests\Run.Tests.ps1
powershell.exe -NoProfile -File .\Tests\Recommendation.Tests.ps1
powershell.exe -NoProfile -File .\Tests\UI.Smoke.ps1
powershell.exe -NoProfile -File .\Tests\Engine.Tests.ps1
powershell.exe -NoProfile -File .\Tests\Transactions.Tests.ps1
powershell.exe -NoProfile -File .\Tests\Performance.Tests.ps1
powershell.exe -NoProfile -File .\Tests\Distribution.Tests.ps1
```

CI is configured for PowerShell 7 on Linux and Windows, and Windows PowerShell 5.1 on Windows. See [validation notes](Docs/VALIDATION.md) for actual local coverage and limitations.

See [recommendation rules and sources](Docs/RECOMMENDATIONS.md), [architecture](Docs/ARCHITECTURE.md), [roadmap](Docs/ROADMAP.md), and [original requirements](Docs/Requirements/SPECIFICATION.md). Native changes require the local validation and backup workflow above. The six planned implementation phases are present. Release publication, Windows validation and future expansion remain explicit maintenance work.
