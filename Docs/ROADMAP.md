# Development roadmap

The additional user specification supersedes the original five-phase sequence.

1. **Terminal UI (complete):** dashboard, system detection, profiles, checklists, information screens, simulated results. No Windows changes.
2. **Recommendation engine (current):** actual hardware/driver compatibility, current setting reads, evidence-backed suggestions, comparison and sorting interface. No invented FPS gains.
3. **Optimization engine:** a small reviewed set of documented reversible operations, dry-run previews, permission checks and post-change verification. Keep real execution gated until rollback is ready.
4. **Backup and restoration:** original values including absent registry values, persistent timestamped sessions, individual restore, full rollback, verified optional restore points. Enable real execution only after engine and rollback are tested together.
5. **Performance comparison:** baseline measurements, controlled before/after comparisons, optional benchmark imports and exportable reports. Idle RAM/process counts alone do not establish gaming improvements.
6. **Distribution:** versioned GitHub releases, SHA-256 verification, reviewed installation workflow, offline use, optional updates and documentation.

## Before Phase 3

- Manually test the UI and read-only hardware queries on Windows 10 and 11.
- Review desired per-profile selections, particularly privacy preferences.
- Review Windows observation results against Settings on multiple real machines.
- Choose the first small set of documented operations; specify original-state serialization and verification.
- Keep real execution disabled while the engine is developed, until restoration is implemented and verified.

## Non-negotiable boundaries

Preserve Defender, Firewall, Windows Update, Secure Boot, critical services and dependencies. Do not delete personal files, run arbitrary profile commands, or select experimental settings automatically. Require informed previews and confirmation for future real changes. Removed apps may require reinstalling, so do not promise universal restoration.
