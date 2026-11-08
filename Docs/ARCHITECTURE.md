# Architecture

`Start.ps1` validates dry-run/simulation-only Phase 3 configuration, loads reviewed modules and catalog data, gathers a read-only startup snapshot, and opens the UI. Preview, system info, and comparison modes exit without prompts or history writes. JSON remains data only.

- **SystemInfo:** independent CIM queries for Windows client/build, CPU, GPU/driver versions, RAM, disks, active power plan, and portable chassis. Errors become warnings. No fabricated Windows data on other platforms.
- **Detection:** fixed registry reads return Known/Missing/Error plus source and caveat. Missing values do not imply defaults. Optional dxdiag XML is parsed with DTD/external entities disabled and a document-size limit; imported capability evidence must match detected adapters/drivers.
- **Recommendation:** pure rules consume catalog data, hardware metadata, and observations. They distinguish stored preferences, unsupported builds, unknown capability, policy review, individual preferences and actionable recommendations. No commands are read from JSON. Comparison sorting preserves object identity and user selections.
- **NativeSettings:** fixed C# bridge for documented current-user Windows preference APIs. Only getters are public. Setter implementations remain internal and unconnected to a live dispatcher. API read failures never produce assumed values.
- **Engine:** fixed operation definitions, permission checks, validated snapshots, deterministic targets, skip/deduplication logic, state verification and dry-run results. Apply is a code-level locked capability until Phase 4.
- **Optimization:** validates IDs/profiles, builds recommendation-backed selections, and emits simulation records. It rejects selected unsupported, unknown, experimental, already configured, or entries without an explicit simulation target. There is no unlocked real execution dispatcher.
- **Interface:** dashboard, profiles, compact/comparison views, all six sort modes, detail screens, simulation confirmation, engine dry-run previews and optional simulation history.
- **Logging:** explicitly requested simulation records only; not system backups.
- **Backup / Restore:** status-only APIs. Real restoration is unavailable until Phase 4.

Windows PowerShell 5.1 compatibility: script-relative defaults resolve after binding; top-level JSON arrays are assigned before normalization to avoid nested arrays. Sources use UTF-8 with BOM and avoid PowerShell 7-only syntax.

The recommendation module intentionally accepts observations as data so fixtures can test access errors, missing values and policy precedence without modifying Windows. The registry adapter is tested with mocked reads; real Windows provider behavior still requires Windows validation. Test guards detect listed mutation commands and dynamic dispatch, but are not a sandbox for arbitrary future code.
