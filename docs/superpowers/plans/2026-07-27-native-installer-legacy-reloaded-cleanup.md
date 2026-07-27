# Native Installer and Legacy Reloaded Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make new AccessXI installations use the accepted native PlayOnline ASI path and safely remove obsolete AccessXI-owned Reloaded files left by older installer executables.

**Architecture:** A focused PowerShell cleanup library owns legacy detection and removal. The existing installer consumes that library, deploys a small `PlayOnlineNative` payload, and records cleanup and native hashes. The packager builds and verifies the native stage and no longer ships Reloaded-II or .NET Desktop Runtime installers.

**Tech Stack:** PowerShell 5.1, C# WinForms/.NET 9 self-contained publishing, C++20 x86 native ASI, CMake/CTest, ZIP embedded resource packaging.

## Global Constraints

- Never modify or delete `pol.exe` or `viewer\com\app.dll`.
- Preserve the `ddraw.dll` Ultimate ASI Loader required by the native ASI.
- Delete a complete Reloaded root only when both old AccessXI marker directories prove ownership.
- Preserve unrelated Reloaded roots, configurations, mods, ASI files, and user data.
- Back up removable global config and POL-side files before deletion.
- Keep unknown PlayOnline builds fail-closed through the native ASI fingerprint guard.
- Do not stage or commit `ACCESSXI_HANDOFF_2026-07-12_ROUTE_RECORDER.md`.

---

### Task 1: Legacy cleanup integration contract

**Files:**

- Create: `installer/legacy_reloaded_cleanup.ps1`
- Create: `tools/test_legacy_reloaded_cleanup.ps1`

**Interfaces:**

- Produces: `Remove-LegacyAccessXiReloaded -InstallRoot <string> -PolExe <string> -ReloadedConfigRoot <string> -BackupRoot <string>`
- Returns: an object containing `Detected`, `RemovedPaths`, `PreservedPaths`, and `ConfigRemoved`

- [ ] Write a test fixture with an installer-owned Reloaded root, targeted loader config, legacy POL scripts, `ddraw.dll`, and an unrelated ASI.
- [ ] Run the test and verify it fails because the cleanup function does not exist.
- [ ] Implement path-boundary checks, ownership detection, backup helpers, exact legacy removal, and a structured result.
- [ ] Verify owned artifacts are removed while `ddraw.dll`, native files, Square Enix files, and unrelated ASIs remain.
- [ ] Add partial-marker, unrelated-root, mismatched-config, malformed-config, and second-run cases.
- [ ] Run the test and verify every real filesystem assertion passes.

### Task 2: Native PowerShell installer

**Files:**

- Modify: `installer/install_accessxi.ps1`
- Modify: `tools/test_accessxi_installer_setup_guide_and_cleanup.ps1`

**Interfaces:**

- Consumes: `payload\PlayOnlineNative` and `Remove-LegacyAccessXiReloaded`
- Produces: native POL deployment and `install_summary.json`

- [ ] Add failing smoke assertions for a native payload deployment and a legacy cleanup result in the install summary.
- [ ] Remove Reloaded copy/config/bootstrap and .NET Desktop Runtime installation paths.
- [ ] Source the packaged cleanup library and invoke it before native deployment.
- [ ] Deploy and hash-verify `ddraw.dll`, `AccessXI.PolNative.asi`, `accessxi_pol_native.dll`, and `prism.dll`.
- [ ] Record cleanup results, native hashes, backups, and native diagnostic log paths.
- [ ] Run cleanup, installer, and existing URL-repair checks.

### Task 3: Native package

**Files:**

- Modify: `tools/package_accessxi_installer.ps1`
- Modify: `tools/test_accessxi_installer_package.ps1`
- Modify: `tools/build_pol_native_asi.ps1`

**Interfaces:**

- Consumes: `stage\pol-native` and the known x86 Ultimate ASI Loader
- Produces: `dist\AccessXI-Ashita-Installer` and `dist\AccessXI-Ashita-Installer.zip`

- [ ] Change package tests to require the complete native payload and reject Reloaded-II and .NET Desktop Runtime payloads.
- [ ] Run tests against the current package and verify the expected failure.
- [ ] Make Prism build input come from `third_party\prism`.
- [ ] Build and structure-test the native stage before packaging.
- [ ] Copy the native stage and ASI loader, package the cleanup library, and emit native hashes.
- [ ] Remove stale old-named package outputs and build the new ZIP.
- [ ] Run package tests and verify the ZIP contains no Reloaded payload.

### Task 4: GUI installer and resource

**Files:**

- Modify: `installer/AccessXIInstaller/Program.cs`
- Modify: `installer/AccessXIInstaller/AccessXIInstaller.csproj`
- Modify: `tools/build_accessxi_installer_exe.ps1`
- Modify: `tools/test_accessxi_installer_exe.ps1`

**Interfaces:**

- Consumes: `AccessXI-Ashita-Installer.zip`
- Produces: `dist\AccessXI Installer.exe`

- [ ] Update tests to reject Reloaded and .NET Desktop Runtime installer behavior.
- [ ] Run the tests and verify they fail against the old GUI.
- [ ] Rename the embedded resource and extraction filename.
- [ ] Remove .NET Desktop Runtime detection and installation; retain Visual C++ handling.
- [ ] Update accessible UI and progress text to describe Ashita, native PlayOnline support, and automatic legacy cleanup.
- [ ] Replace the old Reloaded diagnostic build guard with native ASI structure/offline guards.
- [ ] Publish the self-contained EXE and run its structural test.

### Task 5: Documentation, live cleanup, and publication

**Files:**

- Modify: `setup-guide.md`

- [ ] Explain that new releases use native PlayOnline accessibility and automatically remove old AccessXI Reloaded components.
- [ ] Remove obsolete Reloaded and .NET Desktop Runtime dependency instructions.
- [ ] Run the full native, installer, package, guide, and whitespace checks.
- [ ] Verify ZIP guide parity, absence of Reloaded entries, and native payload hashes.
- [ ] Run the cleanup library against this machine's PlayOnline installation and confirm the native ASI remains active.
- [ ] Rebuild the installer outputs, commit only intended files, push the existing private branch, and verify the remote commit.
