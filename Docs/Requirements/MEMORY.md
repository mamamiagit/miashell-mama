# Windows Optimization & Debloat Toolkit — project reference

User supplied both specifications on November 7, 2026 and requested retention for later. “This optimizer” refers to this project.

Full requirements: SPECIFICATION.md in this directory. The additional specification extends the original and updates the development order.

- Open-source Windows 10/11 terminal application, primarily PowerShell 7 with Windows PowerShell 5.1 compatibility where practical.
- Black/neon-green retro terminal UI; modular PowerShell modules and JSON profile data; no arbitrary commands from JSON.
- Focus: gaming, responsiveness, privacy, optional debloating. Balanced Gaming is the recommended default; also Competitive Gaming, Low-End PC, Privacy Focused, Custom, plus original categories.
- Hardware-aware recommendations, risk/compatibility/restart information, detailed explanations, selectable changes and comparison screens.
- Prioritize documented, measurable, reversible changes, stability, security, and transparent limitations. No invented FPS gains or benchmark results.
- Preserve Defender, Firewall, Windows Update, Secure Boot, critical services and system dependencies. No personal file deletion or automatic experimental tweaks.
- Real changes require preview/confirmation, original-state backups, verification, and rollback support. All optimization actions remain simulated until the real engine and rollback system exist.
- GitHub distribution via verified release downloads and SHA-256 hashes, offline use, optional update checks; no blind remote script execution.

Updated development order:
1. Terminal UI: dashboard, hardware detection, navigation, profiles, interactive checklist, detailed information; simulated changes only.
2. Recommendation engine: hardware compatibility, risks, recommendations, comparison interface.
3. Optimization engine: documented reversible settings, dry runs, permissions, verification.
4. Backup/restoration: original state, individual restore, session rollback, history.
5. Performance comparison: baseline metrics, before/after results, optional external benchmark imports, report exports.
6. Distribution: releases, verified installer, offline execution, updates, documentation.

Implementation scope when later requested: Phase 1 only. Do not proceed to Phase 2 without instruction. The current request was to retain specifications, not start implementation. Screenshots mentioned in the source documents were not supplied with this request.

## Current scope update

The user explicitly authorized Phase 2 (recommendation engine) after confirming the patched Phase 1 works on Windows. Version 0.2.0 implements read-only observation, conservative recommendations and sortable comparisons. All Windows changes remain simulated; Phase 3 is not authorized by that instruction. See Docs/RECOMMENDATIONS.md (relative to repository root) for implemented rules and limits.


## Phase 3 authorization and implementation

After confirming Phase 2 worked, the user authorized the next phase. Version 0.3.0 adds the reviewed operation engine for mouse acceleration and minimize/restore animation: native snapshots, original/target plans, dry-run output, permission checks, and verification. Internal setter implementations are reserved for a future rollback-aware dispatcher; no live changes are exposed. Persistent backups and restoration remain Phase 4 and are not authorized by the Phase 3 instruction. See Docs/ENGINE.md.


## Phase 4 authorization and implementation

The user said “Next” after Phase 3, authorizing Phase 4. Version 0.4.0 adds persistent session snapshots/history, atomic checksummed persistence, confirmed backed-up native apply, per-setting/full rollback, interruption recovery, and conservative conflict handling for mouse/animations. Native live use is gated by a successful explicit local validation round trip; Linux fixtures never unlock it. Windows defaults to Local AppData for recovery data across source downloads. Phase 5 is not authorized by this instruction. See Docs/BACKUP-RESTORE.md.


## Phase 5 authorization and implementation

The user first mentioned Phase 6, then explicitly said “Do phase 5”; this turn implements Phase 5 only. Version 0.5.0 adds Before/After resource/configuration captures, saved measurement IDs/history, strict normalized external benchmark summary imports, descriptive comparisons and JSON/CSV/Markdown reports. Missing measurements are never fabricated, incompatible benchmark conditions suppress deltas, and attaching results preserves the original capture by creating a derived ID. Phase 6 distribution work is not included in this update. See Docs/PERFORMANCE.md.


## Phase 6 authorization and implementation

The user explicitly requested Phase 6 after Phase 5. Version 0.6.0 adds clean-checkout ZIP/checksum/per-file manifest packaging, verified side-by-side offline/explicit-online installation, Launch.cmd, optional informational updates and tag-triggered tested draft releases. Installation never launches payloads, changes execution policy or overwrites existing versions/recovery data. Draft creation/public asset availability must be observed rather than assumed. See Docs/DISTRIBUTION.md.
