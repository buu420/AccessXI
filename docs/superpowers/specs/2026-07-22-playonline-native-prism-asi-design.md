# PlayOnline Native Prism ASI Design

Date: 2026-07-22

## Objective

Run AccessXI's PlayOnline accessibility support inside the stock 32-bit PlayOnline Viewer process without Reloaded-II and without modifying Square Enix's `pol.exe` or `viewer\com\app.dll` files.

The installed Ultimate ASI Loader proxy (`PlayOnlineViewer\ddraw.dll`) will load a small native AccessXI ASI. The ASI will start the existing Ghidra-backed PlayOnline hook engine and host Prism speech directly in-process.

## Research Findings

- ILSpy 10.1.1 rejects both the installed `pol.exe` and `viewer\com\app.dll` with `PE file does not contain any managed metadata`. ILSpy is useful for the existing managed `AccessXI.PolReloaded.dll`, but it cannot decompile or rewrite PlayOnline itself.
- Ghidra 12.0.4 imports `pol.exe` as `Portable Executable (PE)`, `x86:LE:32:default:windows`. The executable imports `DDRAW.DLL`, providing the existing proxy-DLL load point.
- The installed `ddraw.dll` identifies itself as the 32-bit Ultimate ASI Loader. Its documented behavior is to load `.asi` files from the game root or `scripts`, `plugins`, and `update` directories.
- The actual accessibility hooks already exist in `src/accessxi_pol.cpp` and target the updated `viewer\com\app.dll` build using Ghidra-backed offsets and guarded native focus paths.
- The native hook currently writes UTF-8 speech lines to `pol-reloaded-native-speech.queue`; the managed Reloaded mod tails that file and calls Prism. The new design replaces this disk relay with an in-process callback and native speech worker.

## Goals

1. Starting the ordinary PlayOnline Viewer automatically loads AccessXI accessibility support.
2. Prism speaks the same verified native labels currently produced by the AccessXI PlayOnline hook engine.
3. Reloaded-II, its managed bootstrapper, and its managed mod are absent from the active process and launch path.
4. `pol.exe` and `viewer\com\app.dll` remain byte-for-byte unchanged.
5. Unknown PlayOnline builds fail closed: no native hooks are installed against unrecognized code.
6. Hook callbacks never perform Prism work, file I/O, or other potentially blocking work.
7. The first prototype is instantly reversible to the existing Reloaded path.

## Non-goals

- Rewriting PlayOnline as managed code or using ILSpy to patch native Square Enix binaries.
- Replacing or expanding the existing menu-label recovery algorithms.
- Adding OCR, guessed labels, or synthetic menu content.
- Removing Reloaded-II files from disk during the prototype.
- Hot-unloading native hooks from a running PlayOnline process.
- Changing Final Fantasy XI's in-game Ashita addon or navigation system.

## Considered Approaches

### 1. Native ASI host with the existing hook engine — selected

Ultimate ASI Loader loads `AccessXI.PolNative.asi`. The ASI loads the existing native hook engine and Prism by absolute path, connects a nonblocking speech callback, and calls the hook initializer.

Advantages:

- No Reloaded or managed runtime in the PlayOnline process.
- No modifications to Square Enix binaries.
- Reuses the already tested Ghidra-backed hook engine.
- Easy rollback by renaming one `.asi` file.
- Clear separation between loading/speech and menu interpretation.

Cost:

- Requires a small new native host and one narrow callback export in the hook engine.

### 2. Reactivate the Ashita PlayOnline plugin

The existing native DLL still exposes Ashita `IPolPlugin` exports. It could initialize hooks and Prism from Ashita's plugin lifecycle.

This remains a possible fallback, but it still requires launching through Ashita and revives an older path that the current installer deliberately disables. It does not satisfy the direct stock-PlayOnline launch goal as cleanly.

### 3. Patch `pol.exe` or its import table

This would literally modify the executable to load AccessXI. It is rejected because it is update-fragile, harder to restore, and unnecessary when PlayOnline already imports `DDRAW.DLL` and the installed proxy safely supplies an ASI load point.

## Deployed Layout

The prototype will use this layout:

```text
PlayOnlineViewer\
  ddraw.dll                              existing Ultimate ASI Loader
  scripts\
    AccessXI.PolNative.asi               new 32-bit native host
    AccessXI.PolNative\
      accessxi_pol_native.dll            existing hook engine, extended with speech sink
      prism.dll                          existing 32-bit Prism build
```

The ASI derives all paths from its own module filename. It must not depend on the process current directory, `%PATH%`, Reloaded directories, or a user-specific absolute path.

Diagnostics remain outside the game directory:

```text
%USERPROFILE%\AccessXI\logs\pol-native-startup.log
%USERPROFILE%\AccessXI\logs\pol-native-speech.log
```

## Component Boundaries

### `AccessXI.PolNative.asi`

Responsibilities:

- Enter through both `DllMain` and an exported `InitializeASI`, guarded by one idempotent startup latch.
- Keep loader-lock work minimal: record the module handle, disable thread notifications, and schedule one bootstrap thread.
- Resolve its private dependency directory from its own module path.
- Wait for the expected PlayOnline window and `viewer\com\app.dll` module.
- Validate the recognized `app.dll` size and FNV-1a fingerprint before enabling hooks.
- Load `prism.dll` and `accessxi_pol_native.dll` with explicit absolute paths and safe DLL-search flags.
- Own the speech queue, Prism context, Prism backend, speech worker, diagnostics, and failure notification.
- Register a speech sink with the hook engine before calling its initializer.

It does not inspect PlayOnline UI objects or contain menu-label tables.

### `accessxi_pol_native.dll`

Responsibilities:

- Retain the existing Ghidra-backed hook installation and native-label resolution code.
- Export a new versioned speech-sink registration function.
- Copy verified UTF-8 speech into the registered sink without blocking or throwing across the ABI.
- Retain the current disk queue only as a temporarily testable fallback when no sink is registered; the direct ASI path must not use it after initialization.
- Remain safe if initialized twice.

It does not initialize Prism and does not own a speech thread.

### Prism speech worker

Responsibilities:

- Be the only thread that owns and calls a Prism context/backend.
- Use the current proven backend policy: try explicit screen-reader backends supported by the shipped Prism build, then Prism's best-backend selection.
- Retry initialization after the real PlayOnline window exists rather than permanently failing during early process startup.
- Convert the hook engine's UTF-8 text directly into `prism_backend_output` calls.
- Recover from an output failure by resetting and recreating the backend once.

## Native ABI

The hook engine will expose a narrow C ABI, versioned from its first release:

```cpp
using AccessXiPolSpeechSinkV1 = void (__stdcall *)(
    const char* utf8_text,
    int interrupt,
    void* context);

int __stdcall AccessXI_POL_SetSpeechSinkV1(
    AccessXiPolSpeechSinkV1 sink,
    void* context);
```

Rules:

- `utf8_text` is valid only for the duration of the call; the ASI copies it immediately.
- The callback is nonblocking and catches all internal failures.
- `interrupt != 0` means the newest visible focus state supersedes pending focus speech.
- Registering a null sink is supported for controlled shutdown tests but not for live hot-unload.
- The return value reports ABI acceptance, not Prism readiness.

## Startup Lifecycle

1. `pol.exe` loads the local `ddraw.dll` proxy as it already does.
2. Ultimate ASI Loader loads `scripts\AccessXI.PolNative.asi`.
3. The ASI's idempotent startup path schedules a bootstrap thread and returns from loader lock.
4. The bootstrap thread writes an initial diagnostic marker and waits for `app.dll`.
5. It fingerprints `app.dll`. A mismatch stops initialization before any hook is written.
6. It loads Prism and the hook engine from `scripts\AccessXI.PolNative` using absolute paths.
7. It starts the Prism worker and waits for an initialized backend with a bounded timeout and retry policy.
8. It registers `AccessXI_POL_SetSpeechSinkV1`.
9. It calls the existing standalone hook initializer, renamed only if needed to remove Reloaded-specific wording while retaining a compatibility export during migration.
10. Hook callbacks enqueue verified native speech; the Prism worker speaks it.

## Speech Queue Behavior

- The queue is bounded so a broken backend cannot consume unbounded memory.
- Enqueueing performs only a text copy, a small lock/atomic operation, and a worker notification.
- Repeated identical focus lines are coalesced.
- When interrupting focus speech arrives, older pending focus speech is discarded so the user hears the currently visible selection rather than stale navigation history.
- If capacity is exhausted, the oldest superseded focus line is removed first. The overflow is logged with counters; current visible focus is retained.
- Text is cleaned and filtered by the existing hook engine before it reaches the sink. The ASI does not invent, relabel, or expand text.

## Accessibility and Privacy Boundaries

- Existing password and one-time-password suppression remains mandatory.
- Speech must correspond to a verified native focus, label, value, or resource already available to a sighted player.
- Unknown pointers, stale focus, unverified builds, and unresolved labels remain silent and diagnostic-only.
- The ASI performs no network access and transmits no user data.
- Diagnostics must escape text safely and must not log password-field contents.

## Failure Handling

### Unrecognized `app.dll`

- Do not install any hooks.
- Write the detected size and hash to `pol-native-startup.log`.
- Show at most one standard Windows error dialog explaining that AccessXI disabled native hooks for safety and naming the log path.

### Missing or invalid Prism

- Do not initialize the hook engine until the speech sink is available.
- Retry only within a bounded startup window.
- If all Prism backends fail, log every backend result without exposing sensitive UI text and show one standard accessible Windows error dialog.

### Missing hook-engine export or ABI mismatch

- Do not call the hook initializer.
- Log the missing export and the expected ABI version.
- Show one standard accessible error dialog.

### Hook initialization failure

- The hook initializer must report success/failure instead of relying only on logs.
- A failure stops further installation attempts for that process unless the failure is explicitly marked retryable.
- Never continue with a partially recognized build.

### Process exit

- Mark the speech worker as stopping and prevent new queue entries.
- Do not perform complex unhooking, Prism teardown, waits, or filesystem work inside `DllMain` during process detach.
- The operating system may reclaim process-lifetime resources at exit. Explicit cleanup belongs in test harnesses, not loader-lock teardown.

## Update Safety

- The first supported build remains the installer-recognized updated `app.dll` with size `4,335,104` and FNV-1a value `0x07E88E8067FEF6CC`.
- Fingerprinting occurs before hook installation.
- Supporting a future PlayOnline build requires fresh Ghidra verification and an explicit new fingerprint/profile; nearest-version or wildcard offsets are prohibited.
- The ASI and dependency directory are independent of Square Enix's executable bytes, making removal and post-update recovery straightforward.

## Prototype Deployment and Rollback

Deployment requires PlayOnline to be closed.

1. Back up the current `scripts` state and hashes.
2. Rename `AccessXI.PolReloadedBootstrap.asi` to a clearly reversible disabled filename.
3. Leave Reloaded-II files installed but inactive.
4. Deploy the new ASI and private dependency directory.
5. Launch the ordinary installed `pol.exe`, not Reloaded-II.
6. Verify startup, fingerprint, Prism, speech-sink, and hook markers before navigating menus.

Rollback:

1. Close PlayOnline.
2. Disable or remove `AccessXI.PolNative.asi` and its private dependency directory.
3. Restore `AccessXI.PolReloadedBootstrap.asi` to its active name.
4. Launch through the current known-good AccessXI path.

No rollback step modifies `pol.exe`, `app.dll`, member data, credentials, or Final Fantasy XI files.

## Testing Strategy

### Static and build tests

- Build every in-process binary as 32-bit x86.
- Verify ASI exports and hook-engine ABI exports.
- Verify the ASI does not reference Reloaded assemblies or the .NET runtime.
- Verify no PlayOnline or app DLL is changed by packaging or deployment.
- Verify startup work is deferred out of loader lock.
- Verify all dependency paths are derived from the ASI module path.
- Verify unrecognized fingerprints cannot reach hook installation.
- Preserve all existing PlayOnline native-focus and no-guessing regression tests.

### Native unit tests

- Speech queue ordering, interruption, deduplication, capacity behavior, and concurrent enqueueing.
- Repeated `DllMain`/`InitializeASI` entry calls start exactly one worker.
- Missing Prism, missing hook DLL, missing export, and ABI mismatch fail closed.
- Prism output failure resets and retries once.
- Password suppression remains upstream of the speech sink.

### Offline integration harness

- Load the ASI speech-host code outside PlayOnline with a fake hook-engine ABI.
- Send known UTF-8 lines through the callback and confirm Prism receives them in order.
- Stress the queue without blocking the producer.
- Exercise initialization and controlled shutdown under Application Verifier where practical.

### Live PlayOnline validation

The first live pass must test one area at a time:

1. Direct `pol.exe` startup without a Reloaded process or Reloaded managed modules.
2. Startup speech and member-list navigation.
3. Member commands and settings.
4. Square Enix password and one-time-password fields, confirming values are never spoken or logged.
5. Connection and pre-login transitions.
6. Post-login PlayOnline menus already covered by the current native hook engine.
7. Rapid arrowing for stale speech, lag, duplicate speech, or crashes.
8. Clean exit and a second launch.
9. Immediate rollback to Reloaded.

After every failure or crash, inspect the fresh logs and Windows crash record before changing hooks. Do not widen native pointer scans or add guessed labels to make a silent case speak.

## Acceptance Criteria

The prototype succeeds when all of the following are true:

- Launching the ordinary installed `pol.exe` produces Prism speech on verified PlayOnline menus.
- Process/module inspection shows that Reloaded-II and `AccessXI.PolReloaded.dll` are not active.
- `pol.exe` and `app.dll` hashes match their pre-test values.
- Password and one-time-password values are neither spoken nor logged.
- Arrow navigation speaks the current visible selection without a growing backlog, duplicates, or measurable new lag.
- An unrecognized `app.dll` test build installs no hooks and produces a clear accessible failure.
- Two consecutive launches and exits complete without a crash.
- Renaming the native ASI off and restoring the Reloaded bootstrap fully restores the previous path.

## Installer Transition

The first implementation is a local prototype. The installer is not switched away from Reloaded until live acceptance passes.

After acceptance:

- Package the native ASI, hook engine, and Prism under the private dependency layout.
- Make the native ASI path the default PlayOnline installation.
- Retain a documented Reloaded fallback for at least one release.
- Update installer structure tests, setup guidance, cleanup, hashes, and rollback behavior.
- Rebuild the installer EXE and ZIP and verify their payload hashes before publishing.

## References

- [ILSpy](https://github.com/icsharpcode/ILSpy) — managed .NET assembly browser and decompiler used to inspect the existing Reloaded bridge.
- [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader) — existing `ddraw.dll` proxy and documented `.asi` loading mechanism.
- [Prism](https://github.com/ethindp/prism) — native screen-reader and speech abstraction used by AccessXI.

## Implementation Boundary

The first implementation plan must stay focused on:

1. Native speech-sink ABI in the existing hook engine.
2. Native ASI bootstrap and Prism speech worker.
3. Tests and offline harness.
4. Reversible local deployment and live validation.

Installer migration begins only after the native prototype passes the live acceptance criteria.
