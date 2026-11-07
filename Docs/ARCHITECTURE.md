# Architecture

`Start.ps1` loads settings and modules, validates the simulation phase, loads declarative catalogs, queries hardware and starts the interface. `-Preview` and `-SystemInfoOnly` exit without interactive prompts or data writes.

- **Interface:** renders the dashboard, numbered navigation, checklists, detailed explanations, confirmation preview and simulation history. ASCII borders work in basic terminals; green text uses host color APIs.
- **SystemInfo:** read-only CIM queries for Windows version/build, CPU, GPU, RAM, disks and power plan. Independent queries degrade gracefully. No fake Windows hardware on other platforms. Gaming-setting reads are deferred.
- **Optimization:** validates catalog references, creates a session selection, blocks known unsupported/experimental options and emits `SIMULATED` results with `ChangedWindows=false`. This module has no real-change dispatcher.
- **Logging:** writes only explicitly requested simulation records. It is not a backup module. Invalid history JSON is skipped with a warning.
- **Backup / Restore:** status-only APIs that explicitly report unavailability; future implementations belong in Phase 4.
- **Config / Profiles:** data only. Catalog IDs map to reviewed code in a future engine, never executable JSON.

Minimum-build checks in Phase 1 are only preliminary filters, not full feature compatibility validation. Suggested options come from the specification and are not dynamically inferred recommendations. Current setting values remain explicitly unknown.

PowerShell sources use UTF-8 with BOM so Windows PowerShell 5.1 reads them consistently. The project avoids PowerShell 7-only syntax and external modules. Use strict mode and terminating errors for configuration failures; hardware discovery and optional log writes expose recoverable failures in the UI.
