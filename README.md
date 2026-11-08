# Windows Performance Toolkit

A Windows 10/11 optimization and debloat toolkit with a black-and-neon-green PowerShell interface.

**Version 0.2.0 — Phase 2: read-only detection, recommendations, and comparisons.** All optimization actions remain simulated. No registry writes, service changes, app removal, power changes, elevation, or real optimization operations are implemented.

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

## What's new in Phase 2

- Fixed read-only preference queries for gaming, input, desktop effects, privacy, Widgets visibility, and active hours.
- Separate **Known**, **Missing**, and **Error** read outcomes; missing values never become guessed defaults.
- Recommendations include reasons, risks, restart requirements, current observations and data sources. Stored preferences are distinguished from effective Windows behavior.
- Windows build/client checks, laptop power advice, GPU/driver metadata, and conservative HAGS capability checks.
- Comparison sorting by recommended changes, risk, category, restart, already configured, or unsupported.
- Administrative capture/privacy policy observations stop conflicting recommendations.

Known disabled Game Mode is currently the only automatically selected simulation. Known enabled privacy, appearance, mouse, and background-recording preferences can be selected manually for a clearly labeled optional simulation; none is preselected. Grouped app settings remain individual review items. HAGS and priority tweaks are never selected automatically. A result labeled “already configured” means the observed preference matches the recommendation; it does not mean a measured performance improvement.

## Interface

Seven profiles cover Balanced Gaming (default), Competitive Gaming, Low-End PC, Windows Debloat, Privacy Focused, System Responsiveness, and Custom.

- Dashboard: **O** opens the comparison of all 18 options; **S** shows hardware and GPU driver details.
- Inside a profile: **V** switches between comparison and compact list; **S** chooses one of six sorting orders.
- **I** opens an item's explanation, drawbacks and sources. Numbers refer to the currently displayed order.
- **N** selects available recommended changes; numbers toggle eligible entries; **R** resets the selection.
- **A** previews selected options and asks you to type `SIMULATE`. It never applies a Windows change.
- Optional simulation logs appear under **H**. Logs are not backups; actual backup/restore is unavailable.

Observations are a startup snapshot. Restart the toolkit after changing Windows Settings or drivers. Current custom selections last only for that profile visit. Logs go to ignored `Data/` by default; use `-DataDirectory` to choose another location.

## Non-interactive output

```powershell
powershell.exe -NoProfile -File .\Start.ps1 -Preview
powershell.exe -NoProfile -File .\Start.ps1 -SystemInfoOnly
powershell.exe -NoProfile -File .\Start.ps1 -Compare -SortBy Risk
```

`-Compare` returns structured objects when called from an existing PowerShell session:

```powershell
.\Start.ps1 -Compare -SortBy Recommended |
    Format-Table Optimization, CurrentState, Recommendation, Availability, Risk -Wrap
```

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
```

CI is configured for PowerShell 7 on Linux and Windows, and Windows PowerShell 5.1 on Windows. See [validation notes](Docs/VALIDATION.md) for actual local coverage and limitations.

See [recommendation rules and sources](Docs/RECOMMENDATIONS.md), [architecture](Docs/ARCHITECTURE.md), [roadmap](Docs/ROADMAP.md), and [original requirements](Docs/Requirements/SPECIFICATION.md). Real changes remain gated until both engine and rollback are implemented. Phase 3 requires an instruction to proceed.
