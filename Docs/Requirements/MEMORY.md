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
