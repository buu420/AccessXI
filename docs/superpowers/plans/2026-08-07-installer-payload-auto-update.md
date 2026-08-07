# AccessXI Installer Payload Auto-Update Implementation Plan

**Goal:** Make the installer automatically use the latest verified public AccessXI payload while retaining a complete offline embedded fallback.

**Architecture:** Add a WinForms-independent release updater that compares the embedded payload SHA-256 with GitHub's latest release asset digest. It downloads only a different payload, verifies size/digest/ZIP structure, and returns the selected payload to the existing installer runner. The form owns user-visible progress and logs; the existing PowerShell installer remains the only deployment mechanism.

**Technology:** .NET 9, `HttpClient`, `System.Text.Json`, `System.Security.Cryptography`, `System.IO.Compression`, WinForms, PowerShell test/build scripts, GitHub Releases REST API.

## 1. Establish failing updater tests

- Add a dependency-free console test project under `installer/AccessXIInstaller.UpdaterTests`.
- Build small valid and malicious ZIP fixtures in memory.
- Test current digest/no download, verified different payload, offline fallback, digest mismatch fallback, invalid download URL fallback, and traversal ZIP fallback.
- Add `tools/test_accessxi_installer_auto_update.ps1` to run the test project.
- Run it before implementation and preserve the expected missing-type compile failure.

## 2. Implement the verified release payload selector

- Add `installer/AccessXIInstaller/ReleasePayloadUpdater.cs`.
- Query only the official latest-release endpoint with GitHub REST headers.
- Require exact asset name/state/HTTPS URL/path/SHA-256/size bounds.
- Hash the embedded payload, skip download when identical, otherwise stream to `.partial` while reporting progress.
- Verify byte count and SHA-256, move to a final temporary ZIP, validate all ZIP entry paths and required package entries, and return a cleanup-owned result.
- On any update error, delete temporary data best-effort and return an explicit embedded-fallback warning.

## 3. Integrate with installation

- Start the check after the existing validation/prerequisite choice and before extraction.
- Keep the UI in Installing state during the check/download.
- Log every outcome and map updater progress into the determinate progress bar.
- Refactor `RunInstaller` to accept an optional verified downloaded ZIP. Copy that ZIP or the embedded resource into the extraction root, then retain the existing prerequisite and PowerShell deployment flow.
- Always clean updater temporary data after the run.

## 4. Guard documentation and build behavior

- Update installer structure tests for exact repository/asset constants, digest verification, safe ZIP validation, offline fallback, and async wiring.
- Remove the obsolete blanket `HttpClient` prohibition while retaining guards that Microsoft prerequisites are never downloaded.
- Run the updater test from the installer EXE build script.
- Update README setup and troubleshooting language to explain automatic checks, verified downloads, and offline fallback without duplicating setup steps.

## 5. Verify and deploy

- Run the new updater behavior tests and all focused installer/readme/package tests.
- Build a fresh package and single-file EXE using the live approved Ashita source.
- Run full package, migration, cleanup, public-hygiene, native, and Lua/hotkey validation already enforced by the build.
- Perform a focused Ghidra inspection of the built Windows executable/native payload to verify the expected PE boundary and no unexpected native dependency change.
- Inspect hashes, Git diff, and release contents; scan for secrets.
- Sync the verified EXE/ZIP/guide to the normal local `dist` location, then commit and publish a new public release.
