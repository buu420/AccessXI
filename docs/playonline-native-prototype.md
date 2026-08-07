# PlayOnline native accessibility

AccessXI loads through the 32-bit Ultimate ASI Loader when PlayOnline Viewer starts. It does not patch `pol.exe` or `viewer\com\app.dll`.

## Build and verify

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_pol_native_asi.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_asi_structure.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_offline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_deployment.ps1
```

The build stages:

```text
stage\pol-native\AccessXI.PolNative.asi
stage\pol-native\AccessXI.PolNative\accessxi_pol_native.dll
stage\pol-native\AccessXI.PolNative\prism.dll
```

## Deploy

Close PlayOnline Viewer, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\deploy_pol_native_asi.ps1
```

The deployment validates the reviewed `app.dll`, backs up prior AccessXI native files under `%USERPROFILE%\AccessXI\backups\pol-native`, and installs the three staged files beneath `PlayOnlineViewer\scripts`.

Startup details are written to `%USERPROFILE%\AccessXI\logs\pol-native-startup.log`. Speech result counters, without spoken labels, are written to `%USERPROFILE%\AccessXI\logs\pol-native-speech.log`.

The successful startup sequence is:

```text
ACCESSXI_POL_NATIVE worker-start
ACCESSXI_POL_NATIVE app-fingerprint-ok
ACCESSXI_POL_NATIVE prism-ready
ACCESSXI_POL_NATIVE speech-sink-registered
ACCESSXI_POL_NATIVE hook-initialize-ok
ACCESSXI_POL_NATIVE ready
```

## Roll back

Close PlayOnline Viewer, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\rollback_pol_native_asi.ps1
```

Rollback disables the AccessXI native ASI. Neither deployment nor rollback modifies Square Enix executables, credentials, member data, or Final Fantasy XI files.
