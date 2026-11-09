# Validation record

Phase 2 local validation uses PowerShell 7.4.13 on Linux. Earlier user testing confirmed that the patched Phase 1 dashboard launches in Windows PowerShell after fixing parameter default timing and JSON-array enumeration. That does not establish Windows validation of the new Phase 2 readers.

- Regression suite parses every source and tests catalog/profile loading, legacy non-enumerated JSON arrays, startup from a different working directory, comparison output, build gates, experimental rejection, simulation records, history, and listed-mutation/dynamic-dispatch guards.
- Recommendation suite uses fixtures and mocked registry reads for enabled/disabled/missing/error states, administrative policy precedence, capture/background-recording distinction, active hours, laptop tradeoffs, all sort modes, matching/stale/multi-GPU HAGS XML, unsupported driver models, malformed XML and prohibited external entities.
- UI smoke test uses a Windows fixture to exercise navigation, cancellation, information, sorting, comparison view, select-recommended, reset, simulation confirmation, optional history, restoration status, settings and exit.
- Non-interactive dashboard and comparison modes are run against the actual Linux host; Windows fields remain unavailable and no Windows action is selected.

Windows 10/11 registry/CIM behavior, actual dxdiag schema variations, console layout, organization execution policy, and Windows PowerShell 5.1 must still be verified on Windows. The GitHub workflow is configured for all three test scripts on PowerShell 7 (Linux/Windows) and Windows PowerShell 5.1, including a native `-File` startup smoke check. Configuration alone is not evidence of a passing hosted run.

No Windows settings were changed during local development or testing. The toolkit still has no real-change engine or rollback implementation.


## Phase 3 validation

The engine suite uses in-memory fixtures to check complete original/target values, preserved mouse thresholds, current-user permission gates, duplicate IDs, already configured state, stale/mismatched observations, invalid/unreadable state and explicit unsupported IDs. Apply is tested with normal, WhatIf, disabled-confirmation, empty and forged plans; all must fail before native reads. The fixed C# bridge is compiled locally and its public surface is inspected to ensure only getters are exposed. Tests do not invoke setters.

The CLI DryRun entry point and both dashboard/profile dry-run screens are exercised. On Linux, actual Windows API reads are unavailable; the UI reports that boundary. Windows API read/write/restore cycles remain unvalidated. No hosted CI success is claimed without observing the run.

Local Phase 3 result: 47 regression assertions, 41 recommendation assertions, 38 engine assertions, and the UI walkthrough passed under PowerShell 7.4.13 on Linux. The actual CLI dry-run returned blocked Windows-only plans on this host, as intended.


## Phase 4 validation

Local tests run on Linux with PowerShell 7.4.13. Persistent fixture transactions cover exact originals, per-setting/full/idempotent restoration, identity/schema/checksum rejection, write-ahead history, WhatIf, lock contention, interrupted writes, stale plans, external changes, pre/post-write failures, failed automatic rollback and retry, post-write mismatch, and persistence failure before mutation. Tests cannot produce a native validation marker. The CLI, default dry-run behavior and menu walkthrough are checked separately.

Native Windows writes, named-mutex behavior on Windows, restore-point support and local validation itself are not claimed tested by Linux fixtures. The explicit -ValidateNative command performs the real backed-up round trip on the user's Windows system only after confirmation. CI runs fixture suites on Linux/Windows/PowerShell 5.1; it never automatically changes Windows preferences.

Phase 4 local result: 51 regression assertions, 41 recommendation assertions, 38 engine assertions, 39 transaction assertions (169 total), and the UI walkthrough passed. No native Windows setter or restore-point command was executed locally.
