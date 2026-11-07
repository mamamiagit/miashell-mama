# Project: Windows Optimization & Debloat Toolkit

## Project Overview

Create a professional, open-source Windows 10/11 optimization and debloating application built primarily with PowerShell 7, while maintaining compatibility with Windows PowerShell 5.1 where practical.

The application should run directly inside Windows Terminal or PowerShell and provide a clean, interactive terminal interface.

Users should be able to launch the application through a command copied from its GitHub repository, review available optimizations, select a performance profile, and apply changes to their Windows installation.

The application should focus on gaming performance, system responsiveness, privacy, and removing unnecessary Windows features.

**Important:** Prioritize measurable performance improvements, system stability, transparency, and reversibility over aggressive or misleading optimization claims.

## 1. Visual Design and Interface

Use the provided screenshots as visual inspiration.

Create a retro, high-performance terminal interface with:

- Black or extremely dark background.
- Bright neon-green text and outlines.
- ASCII/Unicode borders and dividers.
- Color-coded optimization statuses.
- Numbered menus with keyboard navigation.
- Progress indicators and live status updates.
- Clean spacing and organized sections.
- A polished command-line dashboard.

Use a visual style inspired by classic computer terminals, with a modern layout.

Example interface:

```text
╔══════════════════════════════════════════════╗
║       WINDOWS PERFORMANCE TOOLKIT            ║
║          SYSTEM OPTIMIZATION v1.0            ║
╚══════════════════════════════════════════════╝

 SYSTEM INFORMATION
 ──────────────────────────────────────────────
 OS:       Windows 11 Pro
 CPU:      Intel Core i7-10700KF
 GPU:      NVIDIA GeForce RTX 3070
 RAM:      32 GB
 STATUS:   Ready

 OPTIMIZATION PROFILES
 ──────────────────────────────────────────────
 [1] Gaming Performance
 [2] Windows Debloat
 [3] Privacy Optimization
 [4] System Responsiveness
 [5] Custom Optimization
 [6] Restore Previous Settings

 [7] View System Information
 [8] Optimization History
 [9] Settings

 [0] Exit

 Select an option >
```

Detect hardware and operating system information automatically. The example specifications above are placeholders.

## 2. GitHub Installation

Design the application to be distributed through GitHub.

Users should be able to copy a command from the repository README and launch the toolkit.

Requirements:

- Support installation through GitHub.
- Provide a straightforward PowerShell launch method.
- Support local installation and offline execution.
- Provide an optional update checker.
- Display the installed application version.
- Verify downloaded releases using published SHA-256 hashes.
- Avoid blindly executing remote scripts.
- Do not automatically execute arbitrary code from user-provided GitHub URLs.
- Do not download or run unverified third-party optimization scripts.
- Explain what administrator permissions are needed and request elevation only for operations that require them.

Use a trusted release-download workflow rather than piping downloaded scripts directly into execution.

## 3. Optimization Profiles

Create several profiles that users can apply individually.

### Gaming Performance

Include configurable options for:

1. Windows Game Mode.
2. Xbox Game DVR background recording.
3. Hardware-Accelerated GPU Scheduling (HAGS).
4. Windows graphics preferences.
5. Windowed game optimizations.
6. Variable Refresh Rate settings.
7. Mouse acceleration.
8. Power plan configuration.
9. PCIe power management.
10. USB selective suspend.
11. Background applications.
12. Startup applications.
13. Windows visual effects.
14. Windows Update active hours.
15. Delivery Optimization.
16. Game-related background services.
17. CPU scheduling settings.
18. Multimedia Class Scheduler settings.
19. Windows notifications.

Each optimization must explain what it changes, why it might help, and any possible drawbacks.

Do not automatically enable controversial registry tweaks or unsupported scheduling modifications.

### Windows Debloat

Allow users to remove or disable optional Windows applications and features.

Include:

- Preinstalled promotional applications.
- Unwanted optional Windows apps.
- Widgets.
- Windows suggestions.
- Consumer experience features.
- Unnecessary startup applications.
- Optional gaming overlays.

Never automatically remove Microsoft Store, Windows Security, Microsoft Edge, system dependencies, or components required for Windows updates.

Show exactly what will be removed before making changes.

### Privacy Optimization

Include options for:

- Advertising ID.
- Personalized suggestions.
- Optional diagnostic data settings.
- Windows activity tracking preferences.
- App permission settings.
- Optional telemetry-related features.

Do not disable Windows security protections or critical diagnostic services indiscriminately.

### System Responsiveness

Include:

- Startup application management.
- Windows animation settings.
- Transparency effects.
- Power management preferences.
- Background process review.
- Optional visual performance settings.

Avoid unsupported claims about increasing FPS through registry changes.

## 4. Interactive Optimization Checklist

Before applying any profile, display a numbered checklist.

Example:

```text
 GAMING PERFORMANCE PROFILE
 ──────────────────────────────────────────────

 [01/12] [ON]  Windows Game Mode
 [02/12] [ON]  Disable background Game DVR
 [03/12] [OFF] Hardware GPU Scheduling
 [04/12] [ON]  Disable mouse acceleration
 [05/12] [ON]  Optimize visual effects
 [06/12] [OFF] Change power plan

 ──────────────────────────────────────────────

 [A] Apply Selected
 [T] Toggle Optimization
 [I] View Information
 [R] Restore Defaults
 [B] Back

 Selection >
```

Each optimization should have:

- A unique identifier.
- A description.
- Its current Windows state.
- Its recommended state.
- A risk level.
- Whether a restart is required.
- A method to apply the change.
- A method to restore the previous state.
- A way to verify that the change succeeded.

Use clear status indicators:

- `[OK]` Successfully applied.
- `[SKIP]` Already configured.
- `[WARN]` Requires attention.
- `[FAIL]` Failed to apply.
- `[RESTART]` Restart required.

## 5. Backup and Restoration System

Create a reliable rollback system.

Before modifying Windows settings:

1. Detect the original configuration.
2. Save the original values.
3. Create a timestamped backup.
4. Offer to create a Windows restore point where supported.
5. Record every change in an optimization history file.

Allow users to restore individual settings or revert an entire optimization session.

Never assume a restore point was created successfully. Verify the result.

For removed applications, clearly explain when restoration requires reinstalling the application.

## 6. System Detection

Automatically detect:

- Windows version and build.
- CPU model.
- GPU model.
- Installed RAM.
- Storage devices.
- Active power plan.
- Administrator status.
- Relevant Windows gaming settings.

Use this information to determine which optimizations are compatible with the system.

For example, don't offer unsupported Windows 11 features on Windows 10.

## 7. Performance Measurement

Include an optional benchmarking section.

Provide:

- CPU utilization.
- RAM utilization.
- Startup application count.
- Available memory.
- System uptime.
- Current power plan.
- Before-and-after configuration comparisons.

Clearly distinguish between configuration changes and actual performance improvements.

Do not claim FPS improvements without benchmark evidence.

## 8. Safety and Reliability

The toolkit must:

- Never disable Microsoft Defender or Windows Firewall.
- Never disable Windows Update completely.
- Never disable critical Windows services.
- Never disable Secure Boot or other security protections.
- Never make undocumented registry changes.
- Never force changes without user confirmation.
- Never delete personal files.
- Never assume a tweak works on every PC.
- Handle permission errors gracefully.
- Avoid duplicate modifications.
- Verify changes after applying them.
- Support dry-run mode.

Label experimental settings separately and leave them disabled by default.

## 9. Code Architecture

Use a modular PowerShell project structure.

```text
WindowsPerformanceToolkit/
│
├── README.md
├── LICENSE
├── Install.ps1
├── Start.ps1
│
├── Modules/
│   ├── Interface.psm1
│   ├── SystemInfo.psm1
│   ├── Optimization.psm1
│   ├── Backup.psm1
│   ├── Restore.psm1
│   └── Logging.psm1
│
├── Profiles/
│   ├── Gaming.json
│   ├── Debloat.json
│   ├── Privacy.json
│   └── Responsiveness.json
│
├── Config/
│   └── Settings.json
│
├── Tests/
│
└── Docs/
```

Separate interface code from system modification logic.

Use JSON files for profile configuration, but implement actual optimization operations through reviewed PowerShell functions.

Do not execute arbitrary commands stored in JSON.

## 10. Development Instructions

Build the application incrementally.

**Phase 1: Terminal Interface**

Start by creating a working PowerShell terminal application with:

- Main dashboard.
- Neon-green terminal theme.
- Keyboard-driven menus.
- System hardware detection.
- Optimization profile navigation.
- Interactive checklists.
- Placeholder optimization operations.

All system modifications should initially be simulated.

Do not implement actual Windows changes during Phase 1.

**Phase 2: Optimization Engine**

Implement a small set of documented, reversible Windows settings.

Add current-state detection, dry-run previews, verification, and error handling.

**Phase 3: Backup and Restoration**

Implement persistent backups, per-setting restoration, and optimization history.

**Phase 4: Expanded Optimization Profiles**

Add more tested optimizations and Windows compatibility checks.

**Phase 5: GitHub Distribution**

Implement release packaging, installation instructions, integrity verification, and optional updates.

## 11. Expectations for Codex

Write clean, maintainable, documented PowerShell code.

Prioritize reliability over the number of available tweaks.

Avoid unnecessary dependencies.

Explain how to run and test the application.

Do not claim to have tested Windows-specific functionality unless it has actually been tested.

Begin by implementing **Phase 1 only**.

Create the project structure, terminal interface, hardware detection, menu navigation, and simulated optimization checklist.

After completing Phase 1, summarize the files created, how to launch the application, and what should be implemented next.

Do not proceed to Phase 2 until instructed.


# Additional Features: Intelligent Optimization & Performance Comparison

Integrate the following features into the Windows Performance Toolkit project specification.

## 12. Intelligent Optimization Recommendations

Create a system that evaluates the user's hardware, Windows version, and current configuration before recommending optimizations.

Instead of automatically applying every available tweak, the application should explain whether each optimization is useful for that particular PC.

Each optimization must include:

- Current setting and recommended setting.
- Expected benefit, if supported by evidence.
- Compatibility with the detected hardware.
- Risk level: Low, Moderate, or High.
- Whether a restart is required.
- Possible disadvantages.
- An option to apply or skip.
- An option to restore the original configuration.

Do not invent performance percentages or promise FPS improvements.

### Example Recommendations

| Optimization | Default Recommendation |
|---|---|
| Windows Game Mode | Generally enable |
| Background Game DVR | Disable if unused |
| Hardware GPU Scheduling | Test on supported hardware |
| Ultimate Performance power plan | Optional, often minimal gaming benefit |
| Mouse acceleration | User preference |
| PCIe power saving | Leave default unless testing shows a benefit |
| USB selective suspend | Leave enabled unless troubleshooting |
| High CPU priority tweaks | Avoid by default |
| MMCSS registry modifications | Avoid undocumented changes |
| Windows telemetry | Adjust supported privacy settings only |
| Windows animations | Optional |
| Windows Update | Keep enabled, configure active hours |
| Background applications | Review individually |
| Startup applications | Disable unnecessary entries with confirmation |

Recommendations should adapt to the detected system rather than treating every PC identically.

## 13. Optimization Comparison System

Implement a comparison menu where users can inspect individual optimizations before applying them.

Example terminal interface:

```text
╔══════════════════════════════════════════════╗
║          OPTIMIZATION COMPARISON             ║
╚══════════════════════════════════════════════╝

 [01] Windows Game Mode
 ──────────────────────────────────────────────
 CURRENT:       Disabled
 RECOMMENDED:   Enabled
 RISK:          LOW
 RESTART:       No
 BENEFIT:       Gaming resource prioritization

 [02] Hardware GPU Scheduling
 ──────────────────────────────────────────────
 CURRENT:       Disabled
 RECOMMENDED:   Test Both
 RISK:          MODERATE
 RESTART:       Yes
 BENEFIT:       Hardware-dependent

 [03] CPU Priority Registry Tweaks
 ──────────────────────────────────────────────
 CURRENT:       Windows Default
 RECOMMENDED:   Keep Default
 RISK:          HIGH
 BENEFIT:       No consistent proven improvement

 [A] Apply Recommended
 [C] Customize Selection
 [I] Detailed Information
 [B] Back
```

Allow users to sort optimizations by:

- Recommended changes.
- Risk level.
- Category.
- Restart requirement.
- Already applied.
- Unsupported on this PC.

Experimental settings must never be selected automatically.

## 14. Before-and-After Performance Testing

Add an optional performance comparison feature.

The application should record baseline system information before applying optimizations.

Collect measurable information such as:

- CPU utilization.
- Memory utilization.
- Background process count.
- Startup application count.
- Current power plan.
- Available physical memory.
- System configuration differences.

Include optional gaming benchmark support.

If the user supplies FPS or frame-time results from a supported external benchmark, allow the application to compare those measurements.

Example:

```text
 PERFORMANCE COMPARISON
 ──────────────────────────────────────────────

 METRIC                 BEFORE       AFTER
 ──────────────────────────────────────────────
 Startup Applications      14           8
 Background Processes     142         131
 RAM Usage               5.2GB       4.8GB
 Power Plan              Balanced    Balanced

 GAMING BENCHMARK
 ──────────────────────────────────────────────
 Average FPS:          Not measured
 1% Low FPS:           Not measured
 Frame Time:           Not measured

 [S] Save Results
 [E] Export Report
 [B] Back
```

Clearly explain that fewer background processes or lower idle RAM usage does not necessarily mean higher gaming FPS.

Do not generate fictional benchmark results.

## 15. Optimization Profiles Based on User Goals

Expand the profile selection system to include:

### Competitive Gaming

Prioritize stable frame times, input responsiveness, and avoiding unnecessary background interruptions.

Do not apply aggressive registry or CPU priority modifications.

### Balanced Gaming

Preserve Windows functionality while adjusting supported gaming settings.

This should be the recommended default profile.

### Low-End PC

Focus on reducing unnecessary startup applications, visual effects, and optional background software.

Avoid disabling important Windows services.

### Privacy Focused

Adjust supported Windows privacy settings without compromising security.

### Custom Profile

Allow users to choose individual optimizations and save their selections as reusable profiles.

## 16. Detailed Optimization Explanations

Every optimization should have an information screen accessible through the terminal interface.

Example:

```text
╔══════════════════════════════════════════════╗
║         HARDWARE GPU SCHEDULING              ║
╚══════════════════════════════════════════════╝

 DESCRIPTION
 Allows supported GPUs to manage certain
 scheduling operations directly.

 CURRENT STATE
 Disabled

 RECOMMENDATION
 Test enabled and disabled.

 POSSIBLE BENEFITS
 Performance and latency may improve in
 some hardware and game combinations.

 POSSIBLE DRAWBACKS
 Performance or stability may vary.

 RESTART REQUIRED
 Yes

 [1] Enable
 [2] Disable
 [3] Restore Original Setting
 [0] Back
```

Explanations should use clear language understandable to someone without advanced Windows knowledge.

## 17. Safety and Recommendation Logic

Implement these rules:

1. Never classify an optimization as beneficial without a reasonable technical basis.
2. Avoid recommending registry modifications based only on online gaming myths.
3. Preserve Windows security functionality.
4. Never automatically disable important services.
5. Treat unsupported hardware configurations as incompatible.
6. Clearly identify changes that are experimental.
7. Require confirmation before applying potentially disruptive changes.
8. Keep a record of original settings for restoration.
9. Verify that a change actually succeeded.
10. Allow users to inspect all planned modifications before execution.

## 18. Updated Development Order

Use this development sequence:

**Phase 1: Terminal UI**
- Dashboard and navigation.
- Hardware detection.
- Profile selection.
- Interactive optimization checklist.
- Detailed optimization information screens.
- Simulated changes only.

**Phase 2: Recommendation Engine**
- Hardware compatibility checks.
- Optimization risk ratings.
- Recommended settings.
- Comparison interface.

**Phase 3: Optimization Engine**
- Implement documented, reversible settings.
- Dry-run mode.
- Permission checks.
- State verification.

**Phase 4: Backup and Restoration**
- Save original configurations.
- Restore individual settings.
- Session rollback.
- Optimization history.

**Phase 5: Performance Comparison**
- Baseline measurements.
- Before-and-after comparisons.
- Optional benchmark imports.
- Exportable reports.

**Phase 6: Distribution**
- GitHub release packaging.
- Verified installation.
- Offline execution.
- Update checker.
- Documentation.

## Final Instructions for Codex

Integrate these requirements with the original project specification rather than creating a separate application.

Maintain the black-and-neon-green terminal aesthetic shown in the reference screenshots.

Keep the code modular, readable, and easy to maintain.

Start with Phase 1 only. All optimization actions must remain simulated until the real optimization engine and rollback system are implemented.

After Phase 1 is complete, provide a summary of the implementation, instructions for running it, and the next recommended development task.