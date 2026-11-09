# Contributing

Read Docs/ROADMAP.md and the requirements before changing scope. Phase 4 must default to dry-run. Every live write requires durable intent and confirmation; normal native apply also requires local validation. Keep UI, hardware detection, profile data, and execution logic separate.

Run `pwsh -NoProfile -File ./Tests/Run.Tests.ps1`, `pwsh -NoProfile -File ./Tests/Recommendation.Tests.ps1`, `pwsh -NoProfile -File ./Tests/UI.Smoke.ps1`, `pwsh -NoProfile -File ./Tests/Engine.Tests.ps1`, `pwsh -NoProfile -File ./Tests/Transactions.Tests.ps1` and `pwsh -NoProfile -File ./Start.ps1 -Preview`. For Windows-specific work, test Windows 10/11 with both PowerShell 7 and Windows PowerShell 5.1, and describe exactly which environments were used.

New catalog entries need unique IDs, clear descriptions, compatibility limits, risk, restart status, evidence limits and drawbacks. Do not add speculative performance claims. Experimental entries must never be selected by default.

Do not commit local Data/ history, downloaded runtimes, credentials, or machine-specific outputs. Real changes require a reviewed rollback design and explicit authorization to advance development phases.
