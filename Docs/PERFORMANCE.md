# Performance captures and comparisons

Phase 5 is read-only with respect to Windows configuration. It neither applies optimizations nor launches third-party benchmarks. Native apply remains the separate Phase 4 flow.

## Capture protocol

Use the same system, user, foreground workload, game scene, power state and settings. Close or retain the same background apps. Let startup activity settle. Capture Before, make the intended changes explicitly, restart if required, reproduce the workload, then capture After. Uptime is recorded so a restart is visible; it is not a speed score. Snapshots do not establish causation or statistical significance.

CPU is the mean of successful `Win32_PerfFormattedData_PerfOS_Processor` `_Total` PercentProcessorTime readings. Defaults: three readings, one second apart. Sampling records requested/successful counts, interval, timestamps, minimum and maximum. Partial reads remain labeled by their lower count; zero successful readings means unavailable. `-SampleCount` is 1–15, `-SampleInterval` is 1–5 seconds, and requested sleep time is limited to 30 seconds (provider/query overhead is additional).

Memory uses OS-visible total/free physical memory in KiB, converted to MiB and physical-memory used percentage. Process count comes from Get-Process. StartupCommandCount is the accessible Win32_StartupCommand inventory, not a complete count of enabled Task Manager entries, scheduled tasks, services or boot work. Process names and command lines are not saved. Power plan and read-only/native setting observations form a separate configuration comparison.

CIM/permission/native read failures remain unavailable or unknown; absent values never become zero. Non-Windows captures are Preview records with unavailable Windows metrics, not invented Windows performance data. Driver versions and hardware metadata help flag comparability limits.

Sources: [Microsoft WMI performance monitoring](https://learn.microsoft.com/windows/win32/wmisdk/wmi-tasks--performance-monitoring), [Win32_OperatingSystem](https://learn.microsoft.com/windows/win32/cimwin32prov/win32-operatingsystem), and [Win32_StartupCommand](https://learn.microsoft.com/windows/win32/cimwin32prov/win32-startupcommand).

## Saved records

`Measurements/<id>.json` stores a checksummed, schema-validated snapshot in the current data directory, separate from native recovery sessions. On Windows the default is `%LOCALAPPDATA%\WindowsPerformanceToolkit`. IDs are immutable and snapshots are bound to the same machine/user/platform. Label, UTC time, CPU/GPU/driver/OS metadata, sampling context, metrics and configuration observations are retained. Captures are not backups and cannot authorize native writes.

Attaching benchmark results creates a new ID with DerivedFrom referencing the old capture. Original capture time and resource measurements remain unchanged; BenchmarkImportedUtc records attachment time. A benchmark run is user-supplied and is not independently proven to have occurred at the resource capture time. Use the derived IDs for the comparison; the original baseline is untouched.

## Supported external benchmark import

Use a normalized summary `.json` or exactly one-row `.csv`. Templates in `Docs/Benchmarks/` contain no measured values and deliberately fail import until you supply at least one actual result. Replace placeholder metadata and duration/run count with the conditions you really used. Raw tool-specific per-frame output is not supported; no arbitrary scripts or executable files are run.

Required metadata:

| Field | Meaning |
| --- | --- |
| schemaVersion | 1 |
| game | Game/application name |
| scenario | Fixed replay, scene or built-in benchmark |
| resolution | Resolution actually used |
| qualityPreset | Preset or explicit settings description; include relevant upscaling/frame-generation settings |
| tool / toolVersion | External benchmark tool and version |
| durationSeconds | Positive measured duration, at most 86400 seconds |
| runCount | Integer 1–1000; describe the same aggregation method in scenario for repeated runs |

Optional metrics: averageFps, onePercentLowFps, meanFrameTimeMs. At least one must be a positive finite number. Missing/blank metrics remain unmeasured, not zero. 1% low cannot exceed average FPS for this summary schema. Numeric strings use invariant decimal dots; NaN, infinity, invalid ranges and multi-row CSV are rejected. Tool-specific percentile definitions are not recomputed or assumed interchangeable.

For gaming deltas, both sides must include that metric and have matching declared game, scenario, resolution, preset, tool/version, duration and run count. Hardware/OS/driver differences or incomplete hardware metadata suppress benchmark deltas. Matching metadata is still only a declared comparison, not proof of controlled conditions or an optimization benefit. Repeat benchmarks and inspect run-to-run variation yourself; this release does not calculate confidence intervals.

## Comparison and export

Resource deltas are After minus Before in their existing units. Percent-valued resource deltas are percentage points. PercentChange in JSON/CSV is the relative change `100*(After-Before)/Before`; it is null when Before is zero or either reading is unavailable. Neither direction is automatically labeled an improvement.

Configuration rows are Changed/Unchanged only when both values are known. Missing/unreadable values, including a key present on only one side, produce Unknown. A configuration change is not counted as measured performance.

The P menu exports the last comparison as JSON, Markdown and CSV under `Reports/`, with unique filenames. CLI exports require `-CompareMeasurements -BeforeId ... -AfterId ... -ReportPath ...`, with ReportFormat JSON/Markdown/CSV (Markdown default). Exports are standalone and do not overwrite existing files.

Reports omit SID/machine name and raw file paths. Hardware, user labels and benchmark metadata remain visible; review before sharing. Markdown values are escaped and text-like spreadsheet formula prefixes are neutralized in CSV. JSON preserves structured metrics and provenance. Exports show unavailable data honestly and always include the limits of resource snapshots and imported benchmark evidence.
