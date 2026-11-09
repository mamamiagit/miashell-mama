# Windows Performance Toolkit

A Windows 10/11 optimization and debloat toolkit with a black-and-neon-green PowerShell interface.

**Version 0.4.0 — Phase 4: persistent backups and restoration.** Dry-run remains the default. Two reviewed native operations (mouse acceleration and minimize/restore animation) support confirmed, backed-up apply and restore after a successful validation round trip on your Windows user/machine. Other catalog options remain comparisons/simulations.

## Run on Windows

Windows PowerShell 5.1 is supported; PowerShell 7 is optional. Administrator permissions are not required.

If downloading a GitHub ZIP, right-click the ZIP **before extracting** → **Properties → Unblock → Apply**, then extract it. Open PowerShell in the folder containing `Start.ps1` and run:

```powershell
powershell.exe -NoProfile -File .\Start.ps1
```

If you already extracted a trusted download and Windows reports that the scripts are unsigned, unblock the local PowerShell files first:

```powershell
Get-ChildItem -Recurse -File -Include *.ps1,*.psm1 | Unblock-File
powershell.exe -NoProfile -File .\Start.ps1
```

This removes the download marker; it does not change execution policy or satisfy an organization policy requiring signed scripts. The toolkit does not bypass execution policy. Signed releases and verified release installation are future distribution work. `Install.ps1` is only a local launcher.

Alternatively, clone the source:

```powershell
git clone https://github.com/mamamiagit/miashell-mama.git
cd miashell-mama
powershell.exe -NoProfile -File .\Start.ps1
```

With PowerShell 7 installed, use `pwsh` instead of `powershell.exe`. No runtime packages or network requests are needed. Linux/macOS can preview the UI; Windows observations and action selections remain unavailable.

## What's new in Phase 4

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

- Dashboard: **D** previews engine operations; **O** opens the comparison of all 18 options; **S** shows hardware and GPU driver details.
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
```

CI is configured for PowerShell 7 on Linux and Windows, and Windows PowerShell 5.1 on Windows. See [validation notes](Docs/VALIDATION.md) for actual local coverage and limitations.

See [recommendation rules and sources](Docs/RECOMMENDATIONS.md), [architecture](Docs/ARCHITECTURE.md), [roadmap](Docs/ROADMAP.md), and [original requirements](Docs/Requirements/SPECIFICATION.md). Native changes require the local validation and backup workflow above. Phase 5 (performance comparisons) requires an instruction to proceed.
