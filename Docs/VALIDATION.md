# Validation record

Phase 2 local validation uses PowerShell 7.4.13 on Linux. Earlier user testing confirmed that the patched Phase 1 dashboard launches in Windows PowerShell after fixing parameter default timing and JSON-array enumeration. That does not establish Windows validation of the new Phase 2 readers.

- Regression suite parses every source and tests catalog/profile loading, legacy non-enumerated JSON arrays, startup from a different working directory, comparison output, build gates, experimental rejection, simulation records, history, and listed-mutation/dynamic-dispatch guards.
- Recommendation suite uses fixtures and mocked registry reads for enabled/disabled/missing/error states, administrative policy precedence, capture/background-recording distinction, active hours, laptop tradeoffs, all sort modes, matching/stale/multi-GPU HAGS XML, unsupported driver models, malformed XML and prohibited external entities.
- UI smoke test uses a Windows fixture to exercise navigation, cancellation, information, sorting, comparison view, select-recommended, reset, simulation confirmation, optional history, restoration status, settings and exit.
- Non-interactive dashboard and comparison modes are run against the actual Linux host; Windows fields remain unavailable and no Windows action is selected.

Windows 10/11 registry/CIM behavior, actual dxdiag schema variations, console layout, organization execution policy, and Windows PowerShell 5.1 must still be verified on Windows. The GitHub workflow is configured for all three test scripts on PowerShell 7 (Linux/Windows) and Windows PowerShell 5.1, including a native `-File` startup smoke check. Configuration alone is not evidence of a passing hosted run.

No Windows settings were changed during local development or testing. The toolkit still has no real-change engine or rollback implementation.
