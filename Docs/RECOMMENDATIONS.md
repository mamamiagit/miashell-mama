# Phase 2 recommendation rules

The engine evaluates a startup snapshot. Known enabled advertising, appearance, acceleration and background-recording preferences offer explicit optional disable simulations. They are never preselected; Select Recommended selects only the Game Mode rule. “Known” means a read returned a stored preference, not that the setting is currently effective. Windows policy, edition, app installation, driver capability, and pending restarts can change effective behavior. Unknown or missing data is not interpreted as enabled, disabled, or a default. There is no FPS prediction.

| Option | Observation and recommendation |
| --- | --- |
| Game Mode | Read AutoGameModeEnabled. Build 15063+; known 0 suggests Enable, known 1 is already configured. Only this rule currently auto-selects a simulation. |
| Game DVR | Read AppCaptureEnabled separately from HistoricalCaptureEnabled. Review usage before disabling recording. Group Policy or MDM policy (including unreadable policy state) blocks change suggestions. |
| HAGS | Read HwSchMode as a preference only. Optional matching dxdiag evidence checks explicit scheduling capability and WDDM version. No support inference from vendor or GPU name. Experimental and never selected. |
| Mouse | Read MouseSpeed as acceleration preference. Review preference; no FPS claim. |
| Power plan | Display active CIM power plan. Keep current/default; laptops receive a battery-life caveat. |
| Startup apps | Individual Windows Settings review; startup enumeration/management is not implemented here. |
| Animations | Read MinAnimate, which covers minimize/maximize animations only. Review preference. |
| Transparency | Read EnableTransparency; review appearance preference. |
| Notifications | Per-app manual review; no single global switch is inferred. |
| Active hours | Read stored start/end hours, validate hour range, explain automatic scheduling/policy may differ. Keep Windows Update enabled. |
| Advertising ID | Read Enabled and check configured advertising policy. Privacy preference; no performance claim. |
| Suggestions | Read tailored-experience preference only; it does not represent every Windows suggestion. |
| Diagnostics | Display stored diagnostic level, checking configured diagnostic policy first. Do not equate a raw level with effective data collection across editions. |
| Optional apps | Individual review. No package deletion; preserve Store, Security, Edge and system dependencies. |
| Widgets | Windows 11 build prerequisite; read taskbar visibility and check configured policy. Visibility does not prove installation or capability. |
| USB / PCIe power saving | Keep defaults unless troubleshooting with measurements. No powercfg calls or guesses about current values. |
| CPU priority tweaks | Excluded as unsupported/experimental; keep default. |

The build gate targets Windows client builds 10240–29999, with per-feature minima; it is a conservative family filter, not a certification of every feature/build combination. Detected Server editions, unknown builds and builds outside that range are blocked. HAGS also needs build 19041+ and independent adapter capability evidence. A mixed or incomplete multi-GPU report stays unknown.

## Sources and evidence limits

- [Microsoft Game Mode documentation](https://learn.microsoft.com/previous-versions/windows/desktop/gamemode/game-mode-portal) describes workload prioritization. It does not substantiate a universal FPS gain.
- [Microsoft's HAGS introduction](https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/) explains that compatible hardware and an exposing driver are both needed. [WDDM 2.7 capability documentation](https://learn.microsoft.com/windows-hardware/drivers/ddi/d3dkmdt/ns-d3dkmdt-d3dkmt_wddm_2_7_caps) distinguishes support from enabled state. This toolkit reads imported dxdiag evidence rather than invoking that native API.
- [AllowGameDVR policy](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-applicationmanagement#allowgamedvr) documents the administrative capture control. It is distinct from a user's background-recording preference.
- [General Windows privacy settings](https://support.microsoft.com/en-us/windows/privacy/general-privacy-settings-in-windows) explains advertising and personalization choices; these are privacy choices, not performance benchmarks.
- [Tailored-experience policy](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-experience#allowtailoredexperienceswithdiagnosticdata) and [diagnostic configuration guidance](https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization) describe policy/edition considerations.
- [Windows focus and appearance settings](https://support.microsoft.com/en-us/accessibility/windows/make-it-easier-to-focus-on-tasks) describes animation and transparency preferences.

Registry preference locations are read-only implementation observations, not a documented universal configuration API. They can change or disappear between builds. No registry writes are implemented. These policy probes do not enumerate every possible domain/MDM override; effective policy is never claimed to have been fully resolved.
