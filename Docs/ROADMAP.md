# Development roadmap

The additional user specification supersedes the original five-phase sequence.

1. **Terminal UI (complete):** dashboard, system detection, profiles, checklists, information screens, simulated results. No Windows changes.
2. **Recommendation engine (complete):** actual hardware/driver compatibility, current setting reads, evidence-backed suggestions, comparison and sorting interface. No invented FPS gains.
3. **Optimization engine (complete):** a small reviewed set of documented reversible operations, dry-run previews, permission checks and post-change verification. Live execution now uses the Phase 4 transaction gate.
4. **Backup and restoration (complete):** original values including absent registry values, persistent timestamped sessions, individual restore, full rollback, verified optional restore points. Normal native apply requires a successful explicit local round trip; fixtures do not establish Windows compatibility.
5. **Performance comparison (complete):** baseline measurements, controlled before/after comparisons, optional benchmark imports and exportable reports. Idle RAM/process counts alone do not establish gaming improvements.
6. **Distribution (current):** versioned GitHub releases, SHA-256 verification, reviewed installation workflow, offline use, optional updates and documentation.

## Release maintenance

- Manually test the UI and read-only hardware queries on Windows 10 and 11.
- Review desired per-profile selections, particularly privacy preferences.
- Review Windows observation results against Settings on multiple real machines.
- Collect user-confirmed native round-trip results on Windows 10/11 before expanding the operation set.
- Review hosted Windows compatibility results and the draft release assets before publication.
- Validate read-only measurements and native apply/restore behavior on real Windows before expanding the operation catalog.
- Obtain a real signing certificate only if future Authenticode distribution is desired; never claim unsigned scripts are signed.

## Non-negotiable boundaries

Preserve Defender, Firewall, Windows Update, Secure Boot, critical services and dependencies. Do not delete personal files, run arbitrary profile commands, or select experimental settings automatically. Require informed previews and confirmation for future real changes. Removed apps may require reinstalling, so do not promise universal restoration.
