# Optimization engine, Phase 4

The reviewed native operations remain `mouse` (SPI_GETMOUSE / SPI_SETMOUSE) and `animations` (SPI_GETANIMATION / SPI_SETANIMATION). Targets disable only acceleration or minimize/restore animation; exact original thresholds and values are preserved for restoration. Mouse pointer speed is not modified. These are user preferences, not measured FPS improvements.

[Microsoft SystemParametersInfoW documentation](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-systemparametersinfow) defines the mouse array, SPI actions, return errors and persistence/notification flags. [ANIMATIONINFO documentation](https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-animationinfo) defines the animation structure. The fixed C# bridge exposes public getters and internal setters. The journaled native write wrapper invokes only those fixed setters after reading a valid, identity-bound durable intent. Profiles cannot supply code or native action IDs.

## Separation of responsibilities

- `New-ToolkitExecutionPlan`: read and validate current values, normalize/deduplicate IDs, derive fixed targets and detect already configured state.
- `Invoke-ToolkitEngine`: dry-run rendering of plans. Bare-plan Apply is always refused; plan objects do not authorize native writes.
- `Test-ToolkitOperationState`: compare every modeled field; MATCH, MISMATCH or UNVERIFIED. This can check originals before apply, targets after apply, and originals after restore.
- `Invoke-ToolkitSession`: confirmed, locked, backup-first transaction; normal native apply also needs current local validation.
- `Restore-ToolkitSession`: confirmed, conflict-aware per-setting or complete rollback, independent of validation-marker expiry.

See [backup/recovery design](BACKUP-RESTORE.md) for persistence, interruption handling, failure states, locking, validation and limitations. A successful dry run never claims an applied or restored change. Fixtures are labeled as fixtures and cannot unlock native execution.

Windows client/build and interactive-session checks are required. Current-user operations need no administrator elevation. Security, app removal, service changes, undocumented registry writes, Windows Update and power management remain outside the native engine. Other catalog entries remain recommendations/simulations.
