# Persistent backups and recovery

Phase 4 supports two current-user Windows APIs: mouse acceleration and minimize/restore animation. There are no registry writes, so absent registry-value restoration is not applicable; a missing native state is unreadable and blocks apply. Future registry operations must model absent keys/values explicitly before implementation.

## Storage and identity

Windows defaults to `%LOCALAPPDATA%\WindowsPerformanceToolkit`. `Sessions/<32-character-id>.json` contains a schema-versioned session, UTC creation/update timestamps, current Windows SID/machine identity, backend, exact original/target values, per-setting state and event history. Other systems default to a local Data directory for previews/tests. Fixture records are explicitly a different backend and can never serve as native validation proof.

Records are JSON envelopes with a SHA-256 checksum of the payload. Data is written to a new temporary file, flushed, atomically moved/replaced on the same filesystem, then read back and validated before a preference write. If that filesystem does not support replacement or persistence fails, writes stop. This protects against torn application writes and accidental corruption; the checksum is not a signature, encryption or defense against an owner deliberately rewriting their own files. Storage/power-loss guarantees beyond the operating system's file APIs are not claimed.

Keep recovery data and use one store consistently. Do not move backups between Windows users/machines, mix native/fixture stores, or change stores to bypass an outstanding session. Native operations additionally hold a named mutex for the current user/desktop session, plus an exclusive store lock. Multiple interactive desktop sessions for the same Windows account are not a supported concurrency scenario.

## Apply transaction

1. Verify Windows client/interactive-desktop prerequisites and successful local validation, except during an explicitly requested validation run.
2. Read native state, derive only reviewed targets, display exact original/target data and obtain confirmation. WhatIf performs no writes or store creation.
3. Acquire locks and reject corrupt/foreign records, unfinished sessions, and overlapping still-applied settings.
4. Persist and read back all originals before any preference mutation.
5. Before each setting, re-read the original to reject stale plans; persist an Applying intent, perform the fixed setter, read back every modeled field, then persist Applied.
6. Mark Completed only when all targets were verified. On failure, attempt reverse-order recovery using the durable record and return the original error even if rollback succeeds.

The two underlying APIs do not offer compare-and-swap. Another program can race the read/write interval; checks and locks reduce toolkit races but cannot eliminate concurrent external preference changes. Such conflicts are not force-overwritten during recovery.

## Restore transaction

`-RestoreSession` restores all settings; `-RestoreId` limits restoration to a recorded ID. Restore is available even when the validation marker expired, because recovery must not depend on permission to start a new apply.

- Current equals original: mark Restored without writing.
- Current equals recorded target: persist Restoring intent, write exact original values, read back and verify.
- Current equals neither, or cannot be read: record Conflict/Unverified and preserve the current setting. Continue restoring unrelated recoverable entries.

Interrupted Applying/Restoring sessions follow the same observed-state rules. An original backup and a write-ahead intent allow recovery even when a crash occurs between write and completion logging. Repeated successful restoration is harmless. PartialRestore/RecoveryRequired never means fully restored; the record and original values remain available for a later retry. New mutations are blocked until unfinished sessions are resolved.

Do not manually edit records to override a conflict. Inspect current Windows Settings and the recorded original/target values. If you deliberately return a setting to its recorded target, the toolkit can retry restoration; alternatively restore the displayed original manually. There is no Force switch.

## Local native validation

`-ValidateNative` explicitly confirms a backed-up set/read/restore/read cycle for both operations, including already configured values so setter calls are exercised. It invalidates any old marker before starting. A new checksummed marker is written only after verified restoration, references that restored native session, matches SID/machine/build and implementation source, and expires after 30 days. Failed/interrupted validation cannot unlock normal apply. This local compatibility check is not a general product certification or a security sandbox against source modification.

Normal fixture tests never call native setters or write a native marker. Linux CI does not validate Windows API behavior. A real Windows round trip must be performed locally and can itself change preferences temporarily; it is never run automatically on startup or in CI.

## Optional Windows restore point

`-Apply -CreateRestorePoint` attempts Checkpoint-Computer only if the commands are available and the user is already elevated. It queries restore point IDs before and after, using a unique description, and records success only when a new matching point is observed. Restore-point creation can be disabled/rate-limited by Windows or unavailable in PowerShell 7. Failures are warnings, never fabricated success. File-based original snapshots remain mandatory and do not depend on restore points.
