# Windows Performance Toolkit

A Windows 10/11 optimization and debloat toolkit with a black-and-neon-green PowerShell terminal interface.

**Version 0.1.0 — Phase 1: UI and simulation only.** No registry edits, service changes, app removals, power changes, elevation, or real optimization operations are implemented. Hardware-aware recommendations and measured performance comparisons are future work.

## Run locally

Use Windows Terminal with PowerShell 7 (recommended) or Windows PowerShell 5.1. Administrator permissions are not needed for Phase 1.

```powershell
git clone https://github.com/mamamiagit/miashell-mama.git
cd miashell-mama
pwsh -NoProfile -File .\Start.ps1
```

With Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File .\Start.ps1
```

Review downloaded source before running it. Follow your machine's execution policy; the toolkit does not change or bypass it. `Install.ps1` is currently only a local launcher. GitHub release installation and SHA-256 verification are planned for Phase 6; there are no packaged releases yet.

Non-interactive dashboard and system information:

```powershell
pwsh -NoProfile -File .\Start.ps1 -Preview
pwsh -NoProfile -File .\Start.ps1 -SystemInfoOnly
```

Linux/macOS can preview the UI, but Windows hardware queries and action selections are unavailable. Offline use requires only the downloaded source and a supported PowerShell runtime. No runtime package dependencies or network requests are required.

## Use the interface

- Choose a numbered profile; Balanced Gaming appears first.
- Type an item's number to toggle selection. Use `I` for details and `R` to reset selections.
- Choose `A` to preview selected options, then type `SIMULATE` to generate simulated results.
- Choose whether to save a local simulation log. Nothing is saved automatically.
- Use `B` to return, `S` for hardware information, `H` for simulation history, and `0` to exit.

Seven profiles cover Balanced Gaming, Competitive Gaming, Low-End PC, Windows Debloat, Privacy Focused, System Responsiveness, and Custom. The catalog includes 18 documented options. Experimental settings cannot be selected; known unsupported Windows builds are blocked. Full compatibility and recommendation logic is not implemented yet. Current optimization states explicitly show “Not detected in Phase 1.”

Simulation logs are stored in ignored `Data/` JSON files by default. Override the directory with `-DataDirectory`. These files contain proposed options, timestamps, and profile IDs; they are not backups and cannot restore Windows settings. Custom selections last only for the current profile visit.

## Checks

No test framework installation is needed:

```powershell
pwsh -NoProfile -File .\Tests\Run.Tests.ps1
pwsh -NoProfile -File .\Tests\UI.Smoke.ps1
```

CI runs PowerShell 7 on Linux and Windows and Windows PowerShell 5.1 on Windows. Tests cover parsing, profiles, compatibility gates, experimental-setting rejection, simulation-only results, history round trips, and a guard against Windows mutation commands. See [validation notes](Docs/VALIDATION.md) for what was actually run locally.

## Project layout

```text
Start.ps1             Entry point and preview mode
Install.ps1           Phase 1 local launcher
Modules/              UI, read-only detection, simulation, history, future restore APIs
Config/               Version, settings, documented optimization catalog
Profiles/             Declarative profile selections; no executable commands
Tests/                Dependency-free PowerShell regression checks
Docs/                 Architecture, roadmap, validation, original requirements
```

See [the roadmap](Docs/ROADMAP.md), [architecture](Docs/ARCHITECTURE.md), and [full user specification](Docs/Requirements/SPECIFICATION.md). Real changes must remain unavailable until both the optimization engine and rollback system are implemented. The next implementation phase requires an explicit instruction to proceed.
