# Release packaging, installation and updates

## Package contract

`Tools/Build-Release.ps1` creates three versioned assets:

- WindowsPerformanceToolkit-VERSION.zip
- WindowsPerformanceToolkit-VERSION.zip.sha256 (one digest and canonical archive name)
- WindowsPerformanceToolkit-VERSION.zip.manifest.json (reviewable provenance/file list)

The ZIP contains Start.ps1, Install.ps1, Launch.cmd, README, LICENSE, CHANGELOG, runtime modules/config/profiles and public docs. Local Data, artifacts, tests, tools, Git metadata and project memory/requirements notes are excluded. PackageManifest.json records schema/application/version, exact source commit, dirty-tree status, UTC build time, and each payload file's relative path, byte length and SHA-256. The manifest excludes itself; the outer archive checksum covers it.

Release builds require a clean checkout and matching source commit. `-AllowDirty` is only for local candidates; candidate provenance explicitly reports SourceDirty. Build timestamps/ZIP metadata mean byte-for-byte reproducibility is not claimed. The workflow always builds the exact tag after compatibility checks. A version tag must equal `v` plus Config/Settings.json's version.

## Offline build and installation

From the source checkout, with PowerShell and Git available:

```powershell
.\Tools\Build-Release.ps1 -OutputDirectory .\artifacts
.\Install.ps1 -PackagePath .\artifacts\WindowsPerformanceToolkit-0.6.0.zip -DestinationRoot .\local-versions
```

A source export without .git requires an explicit full SourceCommit. No runtime/third-party script is downloaded by packaging. The checked-out package builder/module is trusted local code, not fetched-and-evaluated bootstrap code.

Install.ps1 has explicit Package and Online modes; no arguments print usage, and -Preview remains a read-only local launcher preview. Offline installation accepts a local archive plus its published single-file checksum, or an explicitly supplied ExpectedSHA256. Browser-renamed archives such as `(1).zip` can be verified using the original checksum file; the checksum's canonical asset name must still match the manifest version.

## Verification and publication

Before creating an install directory, the installer verifies the outer SHA-256 and manifest structure, then streams every listed payload entry to verify exact byte counts and SHA-256. It rejects traversal, absolute paths, backslashes, drive/alternate-stream syntax, reserved device names, case-insensitive duplicate files, symlinks/reparse entries, missing/extra files, and declared size limits. Limits: 32 MiB archive, 64 MiB payload, 8 MiB per payload file, 1 MiB manifest, 512 manifested files and 1024 ZIP entries. Only reviewed relative paths are used for extraction.

Contents are staged in a newly generated sibling directory, copied with size bounds, and hashed again. The already verified manifest is reconstructed in staging; a later archive-read cannot replace the trusted manifest. Settings must agree with the manifest and Phase 6 dry-run defaults. Only verified .ps1/.psm1 files are unblocked on Windows. An atomic directory move publishes the version. Existing version directories are refused; there is no in-place overwrite, automatic launch, profile/PATH change, elevation or execution-policy bypass. Only the generated staging directory is removed on failure.

SHA-256 and internal manifests detect corruption and inconsistency, not a compromised release owner/channel. A checksum obtained alongside malicious code is not an independent signature. There is no bundled Authenticode certificate or third-party script execution. Review the initial source/release before executing its installer; do not use pipe-to-execution commands.

## Online behavior

Install.ps1 -Version accepts only a bounded three-part numeric version. Asset URLs are constructed under the fixed mamamiagit/miashell-mama GitHub repository. No user GitHub URL, release-supplied asset URL or JSON command is executed. ZIP and checksum are downloaded into a generated temporary folder, verified, installed side by side, and removed from the download staging area. Install never runs the application. WhatIf is explicitly forwarded at script/module boundaries and performs no download/install.

Start.ps1 -CheckUpdates and the U menu query only the fixed GitHub latest-release endpoint. Stable, non-draft release metadata must include both expected ZIP/checksum assets. The result is informational, with a derived fixed-repository release link. Offline, rate-limited, malformed or unavailable responses return Unavailable and make no current-version promise. There are no startup/background checks, silent downloads or automatic updates.

## GitHub workflow and draft review

`release.yml` runs on v* tags. It reuses the compatibility workflow (PowerShell 7 Linux/Windows and Windows PowerShell 5.1), builds the exact version on Windows, uploads assets, then creates a **draft** release with narrowly scoped contents:write permission. The release job does not run on pull requests. A failed check or package build prevents draft creation. Native setting writes are never run by CI.

A maintainer reviews workflow results, provenance, archive hashes and Windows behavior, then publishes the draft through GitHub. Publishing/signing is not claimed merely because a tag or workflow file exists. If Actions is disabled, permission-limited or fails, the local build and artifacts remain usable; inspect the workflow rather than assuming a release exists. Before publication, update checks/explicit online installs can legitimately report unavailable.

## Installed data and rollback

Version files live under LocalAppData/WindowsPerformanceToolkit/Versions/VERSION by default. Sessions, Measurements, Reports and validation metadata remain outside version folders in the existing user data directory. Keep recovery data and a working installed version when testing an upgrade. An older launch folder can be used as an application-version fallback; this does not itself restore Windows settings. Use the native session restoration workflow for that. Changes in relevant implementation source/build can require local native revalidation.
