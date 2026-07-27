# Native Installer and Legacy Reloaded Cleanup Design

Date: 2026-07-27

## Objective

Ship AccessXI's accepted native PlayOnline ASI path without installing Reloaded-II, and automatically remove files left by older AccessXI installers when ownership can be established safely.

## Evidence

- The native PlayOnline implementation is live-tested and runs through `AccessXI.PolNative.asi`, `accessxi_pol_native.dll`, Prism, and the existing `ddraw.dll` Ultimate ASI Loader proxy.
- The Ghidra-backed PlayOnline project still identifies `pol.exe` as the host for the reviewed native path. The accepted native design requires preserving the ASI loader and removing the Reloaded managed bridge.
- Ultimate ASI Loader officially supports an x86 `ddraw.dll` proxy and loads `.asi` files from the `scripts` directory.
- The previous AccessXI installer copied a private `Reloaded-II` tree under the selected AccessXI install root, wrote an AccessXI-specific Reloaded application, wrote a global loader configuration pointing at that private tree, and placed a delayed Reloaded bootstrap plus its managed bootstrapper in PlayOnline's `scripts` directory.

## Selected Approach

The installer will package the native ASI stage instead of Reloaded-II. Before deploying the native files, it will run an ownership-bounded legacy cleanup.

The cleanup may delete the complete old `<InstallRoot>\Reloaded-II` directory only when both of these AccessXI markers exist:

- `Mods\AccessXI.PolReloaded`
- `Apps\AccessXI.PolPreLogin`

If only one marker exists, the cleanup removes only the exact AccessXI marker directory and preserves the surrounding Reloaded installation. A Reloaded directory with neither marker is unrelated and remains untouched.

The global `%APPDATA%\Reloaded-Mod-Loader-II\ReloadedII.json` file is removed only when its parsed loader and launcher paths resolve inside the detected old AccessXI Reloaded root. The file is backed up first. A missing, malformed, or differently targeted configuration remains untouched.

PlayOnline cleanup is enabled only when an AccessXI legacy marker was detected. It removes these obsolete exact paths:

- `scripts\AccessXI.PolReloadedBootstrap.asi`
- `scripts\AccessXI.PolReloadedBootstrap.asi.disabled`
- `scripts\Reloaded.Mod.Loader.Bootstrapper.dll`
- `scripts\Reloaded.Mod.Loader.Bootstrapper.asi`
- `scripts\Reloaded.Mod.Loader.Bootstrapper.asi.direct-disabled`
- `scripts\ReloadedPortable.txt`

It does not remove `ddraw.dll`, `AccessXI.PolNative.asi`, the `AccessXI.PolNative` dependency directory, Square Enix binaries, unrelated ASI files, or unrelated Reloaded roots and configurations.

## Native Payload

The packaged PlayOnline payload is:

```text
payload\PlayOnlineNative\
  ddraw.dll
  AccessXI.PolNative.asi
  AccessXI.PolNative\
    accessxi_pol_native.dll
    prism.dll
```

The packager builds the reviewed x86 native stage, verifies its structure, and copies the known x86 Ultimate ASI Loader as `ddraw.dll`. Reloaded-II, its managed mod, its bootstrapper, and its .NET Desktop Runtime installers are not shipped.

## Installation Flow

1. Validate the packaged Ashita, native PlayOnline, Visual C++ runtime, and setup-guide files.
2. Install or skip the bundled Visual C++ prerequisites according to the GUI choice.
3. Copy Ashita and configure the machine-specific Final Fantasy XI path.
4. Detect and clean only AccessXI-owned legacy Reloaded artifacts.
5. Repair the existing PlayOnline URL key-path files when necessary.
6. Back up and deploy `ddraw.dll`, the native ASI, and its private dependencies.
7. Hash-verify every deployed native file and verify that `pol.exe` and `app.dll` were not changed.
8. Write cleanup details, native hashes, backup paths, and native diagnostic paths to `install_summary.json`.

## Failure Handling

- PlayOnline must be closed before POL-side cleanup or deployment.
- Missing native payload files stop installation before any POL-side change.
- Unknown PlayOnline builds remain update-safe because the native ASI validates the reviewed `app.dll` fingerprint before installing hooks.
- Cleanup ambiguity results in preservation and a recorded skip, never a broad deletion.
- Existing POL-side files are backed up before replacement or removal.

## Verification

- Integration tests construct fake owned, partial, and unrelated Reloaded installations and assert real filesystem outcomes.
- Tests verify idempotent cleanup, configuration targeting, preservation of `ddraw.dll`, and preservation of unrelated ASI files.
- Package tests assert the native files exist and no Reloaded-II or .NET Desktop Runtime payload remains.
- Existing native x86/ABI/offline tests remain green.
- The final ZIP and self-contained installer EXE are rebuilt, inspected, and hash-checked.
