# PlayOnline native accessibility prototype

This prototype loads AccessXI through the existing 32-bit Ultimate ASI Loader when the ordinary PlayOnline Viewer starts. It does not patch `pol.exe` or `viewer\com\app.dll`, and Reloaded-II remains installed only as a reversible fallback.

## Build and verify

From `C:\Users\buu42\AccessXI`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_pol_native_asi.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_asi_structure.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_offline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_deployment.ps1
```

## Deploy

Close PlayOnline Viewer, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\deploy_pol_native_asi.ps1
```

The script validates the reviewed `app.dll`, backs up the previous AccessXI script state under `%USERPROFILE%\AccessXI\backups\pol-native`, disables `AccessXI.PolReloadedBootstrap.asi`, and installs:

```text
PlayOnlineViewer\scripts\AccessXI.PolNative.asi
PlayOnlineViewer\scripts\AccessXI.PolNative\accessxi_pol_native.dll
PlayOnlineViewer\scripts\AccessXI.PolNative\prism.dll
```

Start PlayOnline from the normal shortcut. Do not use Reloaded-II for this test.

Startup details are written to `%USERPROFILE%\AccessXI\logs\pol-native-startup.log`. Speech result counters, without label text, are written to `%USERPROFILE%\AccessXI\logs\pol-native-speech.log`.

The successful startup sequence is:

```text
ACCESSXI_POL_NATIVE worker-start
ACCESSXI_POL_NATIVE app-fingerprint-ok
ACCESSXI_POL_NATIVE prism-ready
ACCESSXI_POL_NATIVE speech-sink-registered
ACCESSXI_POL_NATIVE hook-initialize-ok
ACCESSXI_POL_NATIVE ready
```

Validate member-list navigation and the existing verified menus first. Then confirm that Square Enix password and one-time-password values are never spoken or logged, rapid arrowing speaks the current item without a stale backlog, exit is clean, and a second ordinary launch succeeds.

## Roll back

Close PlayOnline Viewer, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\rollback_pol_native_asi.ps1
```

Rollback disables the native ASI and restores the disabled Reloaded bootstrap. It leaves the private dependency folder and backup manifest in place for diagnosis. Neither deployment nor rollback modifies Square Enix executables, credentials, member data, or FFXI files.
