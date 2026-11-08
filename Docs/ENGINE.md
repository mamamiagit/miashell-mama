# Phase 3 optimization engine

This release implements reviewed operation definitions, native state reads, target planning, permission checks, dry-run results and state verification. Native setters are implemented internally for the two modeled preferences, but there is deliberately no public native write route or live dispatcher. All Apply requests are locked pending Phase 4. No real apply/restore cycle has been validated.

## Operations

| ID | Read / future write | Target | Original state needed for restoration |
| --- | --- | --- | --- |
| mouse | SPI_GETMOUSE / SPI_SETMOUSE | Acceleration = 0; preserve both thresholds | Threshold1, Threshold2, Acceleration |
| animations | SPI_GETANIMATION / SPI_SETANIMATION | MinAnimate = 0 | MinAnimate |

These are optional user preferences, not measured gaming performance improvements. Mouse pointer speed is a separate parameter and is never changed by this operation. Games using raw input may ignore desktop acceleration. MinAnimate refers to minimize/restore animation, not every Windows effect.

[Microsoft SystemParametersInfoW documentation](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-systemparametersinfow) defines the mouse array, SPI actions, persistence/notification flags and error return. [ANIMATIONINFO documentation](https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-animationinfo) defines structure size and animation state. Setter implementations use SPIF_UPDATEINIFILE | SPIF_SENDCHANGE, free native buffers in finally blocks, and throw on API failure. The bridge is fixed C# source; JSON cannot supply native actions, paths, or executable code.

## Planning and verification

1. Validate Windows client/build and interactive desktop prerequisites. Current-user operations require no elevation. Server, unknown product type, non-Windows and service/session-zero contexts are blocked.
2. Normalize IDs and remove duplicates. Any operation without a reviewed implementation is UNSUPPORTED.
3. Read original values through the Windows API, not from registry preferences. Failures remain WARN; no defaults are invented.
4. Validate and copy every modeled field. Mouse thresholds are nonnegative 32-bit integers, acceleration is 0–2, MinAnimate is 0–1. Build a fixed target. Already configured state yields SKIP.
5. Produce DRYRUN output with original/target state, permission, risk, drawbacks, restart requirements and the live-execution lock. Nothing is saved or changed automatically.

`Test-ToolkitOperationState` compares every modeled field to an explicitly expected value. A known match yields MATCH; a value difference yields MISMATCH; unreadable or invalid state yields UNVERIFIED. It can compare a fresh observation to the original snapshot to detect a stale plan, or to the target for future post-write verification. A match is a state comparison, not evidence of a performance improvement.

The test-only optional StateSnapshot parameter is clearly labeled caller-supplied fixture evidence, never a live read. Original values are copied to avoid later caller mutation. Plan objects are data, not authority to execute code.

## Capability boundary

`Invoke-ToolkitEngine` defaults to DryRun. Mode Apply fails before inspecting caller-supplied plan entries or touching native code. No configuration field, elevated shell, WhatIf option or confirmation override enables writes. Native getter methods are public; setters are internal and have no public dispatcher in this build. This is a guard against accidental use through the toolkit, not a sandbox against someone modifying source or invoking private members through reflection.

Registry mutation, power management, app removal, security settings, Windows Update and service changes are outside this engine. Other catalog items remain comparisons/simulations and are not falsely presented as implemented operations.

## Phase 4 requirements before enabling Apply

- Persist validated originals successfully before any mutation; distinguish absent values for future registry-based operations.
- Bind plans and backups to the current Windows user, session and machine; re-read original state immediately before applying and reject stale plans.
- Require a complete review and confirmation; never treat configuration or imported plans as executable authority.
- Write through reviewed dispatch only; verify results immediately and record failures honestly, including partial success and interrupted sessions.
- Implement individual restore and session rollback using the exact originals, with verification and concurrency handling.
- Test native read/write/restore cycles on real Windows 10/11 before exposing live changes. Linux bridge compilation and fixture tests do not validate Windows behavior.
