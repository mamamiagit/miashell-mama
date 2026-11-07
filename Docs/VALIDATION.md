# Validation record

Local validation performed on November 7, 2026 with PowerShell 7.4.13 on Linux:

- All PowerShell source files parsed successfully.
- Dependency-free regression suite passed: catalog/profile loading, known Windows build exclusions, non-Windows blocking, experimental-setting rejection, simulation output, optional log round trip, and unavailable backup/restore APIs.
- Scripted UI smoke test passed with a clearly labeled Windows 11 fixture: profile navigation, cancellation, information, invalid input, simulation confirmation, selection reset, optional history, restoration status, settings and exit.
- `Start.ps1 -Preview` rendered the real non-Windows dashboard successfully.
- `Start.ps1 -SystemInfoOnly` returned honest unavailable Windows fields on Linux.

Windows 10/11 CIM queries, console appearance, execution policy behavior, and Windows PowerShell 5.1 have not been tested locally. A GitHub Actions workflow is configured for PowerShell 7 on Linux and Windows plus Windows PowerShell 5.1; workflow configuration is not evidence that those hosted jobs have passed.

The fixture exercises the UI and compatibility data paths without invoking actual Windows configuration changes. The forbidden-command check is a regression guard against listed mutation commands, not a security sandbox for arbitrary future code.
