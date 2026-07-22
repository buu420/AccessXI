# PlayOnline Native Prism ASI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ordinary 32-bit PlayOnline Viewer load AccessXI's verified native menu hooks and speak them through Prism without loading Reloaded-II or changing Square Enix binaries.

**Architecture:** The existing Ultimate ASI Loader proxy loads `AccessXI.PolNative.asi`. The ASI resolves a private dependency directory from its own module path, validates the loaded `app.dll`, starts one native Prism worker with a bounded speech queue, registers a versioned callback on the existing hook DLL, and initializes hooks only after speech is ready. Hook callbacks copy verified UTF-8 labels into the bounded queue and never call Prism or write files.

**Tech Stack:** C++20, Win32 x86, CMake/Visual Studio 2022, Prism C ABI loaded dynamically, PowerShell regression/deployment tests, existing Ghidra-backed `accessxi_pol.cpp` hooks.

## Global Constraints

- Do not modify `PlayOnlineViewer\pol.exe` or `PlayOnlineViewer\viewer\com\app.dll`.
- Recognize only `app.dll` size `4335104` and FNV-1a 64-bit `0x07E88E8067FEF6CC`; fail closed before hook writes for every other build.
- Preserve password and one-time-password suppression in the hook engine. Do not add OCR, guessed labels, wildcard offsets, or broader pointer scans.
- The producer callback may copy text, acquire a short queue lock, and signal the worker; it may not invoke Prism, wait on Prism, or perform file I/O.
- Only the speech worker may create, call, reset, or destroy a Prism context/backend.
- Keep `DllMain` loader-lock work to saving the ASI module, disabling thread callbacks, and scheduling the idempotent bootstrap worker. No waits, dependency loads, Prism calls, or teardown in `DllMain`.
- The prototype deployment must be reversible and must leave the Reloaded files installed but inactive.
- Do not stage or commit `ACCESSXI_HANDOFF_2026-07-12_ROUTE_RECORDER.md`.
- Installer migration is outside this prototype plan and begins only after live acceptance.

---

### Task 1: Add the hook-engine speech ABI and status-returning initializer

**Files:**

- Modify: `src/accessxi_pol.cpp:36-42, 767-816, 3158-3263`
- Modify: `src/accessxi_pol.def`
- Create: `tools/test_pol_native_hook_abi.ps1`

- [ ] **Step 1: Write the failing ABI regression test**

Create `tools/test_pol_native_hook_abi.ps1` to assert that:

- `src/accessxi_pol.def` exports decorated x86 names for `AccessXI_POL_SetSpeechSinkV1@8` and `AccessXI_POL_InitializeV2@0` while retaining `AccessXI_POL_ReloadedInitialize@0`.
- `src/accessxi_pol.cpp` declares `AccessXiPolSpeechSinkV1` with `__stdcall` and exactly `(const char*, int, void*)`.
- `speak_prelogin_label` dispatches the registered sink with `interrupt=1` before considering the legacy file queue.
- `AccessXI_POL_InitializeV2` verifies the loaded `app.dll` against the known size/FNV before calling any `install_*hook*` function.
- The compatibility initializer enables the legacy queue and delegates to V2.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_hook_abi.ps1
```

Expected: FAIL because the two new exports and direct sink dispatch do not exist.

- [ ] **Step 2: Implement the versioned nonblocking sink**

In `src/accessxi_pol.cpp`, add:

```cpp
using AccessXiPolSpeechSinkV1 = void (__stdcall *)(
    const char* utf8_text,
    int interrupt,
    void* context);

std::atomic<AccessXiPolSpeechSinkV1> g_speech_sink_v1{nullptr};
std::atomic<void*> g_speech_sink_context_v1{nullptr};
```

Export:

```cpp
extern "C" __declspec(dllexport) int __stdcall
AccessXI_POL_SetSpeechSinkV1(AccessXiPolSpeechSinkV1 sink, void* context);
```

The setter stores context then publishes the sink with release ordering, supports `(nullptr, nullptr)`, rejects `sink == nullptr && context != nullptr`, and returns `1` on acceptance or `0` on invalid arguments. Add a small no-throw dispatch helper that loads the sink with acquire ordering and catches all C++ exceptions. `speak_prelogin_label` must call it with `interrupt=1`; only if no sink is registered may the existing Reloaded queue fallback run.

- [ ] **Step 3: Add an idempotent V2 initializer with explicit results**

Add stable result constants:

```cpp
constexpr int AccessXiPolInitializeOk = 1;
constexpr int AccessXiPolInitializeAlreadyReady = 2;
constexpr int AccessXiPolInitializeAppDllMissing = -1;
constexpr int AccessXiPolInitializeUnsupportedBuild = -2;
```

`AccessXI_POL_InitializeV2` must:

1. Return `AlreadyReady` after a successful earlier call.
2. get `app.dll` with `GetModuleHandleW` and return `AppDllMissing` when absent;
3. call `app_module_matches_known_updated_pol_build` before any hook installer and return `UnsupportedBuild` on mismatch;
4. reset runtime speech state, install the three existing hook groups, start the existing worker, mark ready, and return `Ok`.

Keep `AccessXI_POL_ReloadedInitialize` as a `void` compatibility export. It sets `g_reloaded_speech_queue_enabled=true`, logs the legacy marker, and delegates to V2 without duplicating installation.

- [ ] **Step 4: Export the ABI and run focused tests**

Add to `src/accessxi_pol.def`:

```text
AccessXI_POL_SetSpeechSinkV1=_AccessXI_POL_SetSpeechSinkV1@8
AccessXI_POL_InitializeV2=_AccessXI_POL_InitializeV2@0
```

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_hook_abi.ps1
cmake --build .\build --config Release --target accessxi_pol_nvda
dumpbin /exports .\build\bin\Release\accessxi_pol_nvda.dll
```

Expected: test passes, x86 build succeeds, and all legacy plus V1/V2 exports are present.

- [ ] **Step 5: Run existing native-hook regressions**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_prelogin_native_focus.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_reloaded_split.ps1
```

Expected: PASS; update only assertions that deliberately assumed the disk queue was the sole speech path, while preserving every label, password, fingerprint, and no-guessing assertion.

- [ ] **Step 6: Commit the ABI slice**

```powershell
git add src/accessxi_pol.cpp src/accessxi_pol.def tools/test_pol_native_hook_abi.ps1 tools/test_pol_reloaded_split.ps1
git commit -m "Add native PlayOnline speech sink ABI"
```

---

### Task 2: Build and test the bounded native speech queue

**Files:**

- Create: `src/pol_native/speech_queue.h`
- Create: `src/pol_native/speech_queue.cpp`
- Create: `tests/pol_native_queue_tests.cpp`
- Modify: `CMakeLists.txt`

- [ ] **Step 1: Write failing queue tests**

Add a no-framework test executable covering:

1. FIFO output for noninterrupting items;
2. exact consecutive duplicate coalescing;
3. an interrupting item removing older pending focus items;
4. capacity 128 never being exceeded;
5. overflow retaining the newest visible focus item and incrementing a dropped counter;
6. empty/invalid UTF-8 input being rejected;
7. four producer threads enqueueing while one consumer drains without corruption;
8. `stop()` waking a blocked consumer and rejecting later input.

Add the `pol_native_queue_tests` target and register it with CTest.

Run:

```powershell
cmake -S . -B build -A Win32
cmake --build build --config Release --target pol_native_queue_tests
ctest --test-dir build -C Release -R pol_native_queue_tests --output-on-failure
```

Expected: compile/link FAIL because `SpeechQueue` is not implemented.

- [ ] **Step 2: Implement `SpeechQueue`**

Expose only this producer/consumer contract:

```cpp
struct SpeechItem { std::string text; bool interrupt; uint64_t sequence; };
struct SpeechQueueStats { uint64_t accepted; uint64_t deduplicated; uint64_t dropped; };

class SpeechQueue {
public:
    explicit SpeechQueue(size_t capacity = 128);
    bool enqueue(std::string_view utf8_text, bool interrupt) noexcept;
    bool wait_pop(SpeechItem& item);
    void stop() noexcept;
    SpeechQueueStats stats() const noexcept;
};
```

Use `std::mutex`, `std::condition_variable`, and `std::deque`. Validate UTF-8 without interpreting menu content. Strip CR/LF to spaces, reject empty text, coalesce identical pending/current text, and keep all queue policy inside this class.

- [ ] **Step 3: Make queue tests pass under repetition**

Run:

```powershell
cmake --build build --config Release --target pol_native_queue_tests
1..20 | ForEach-Object { ctest --test-dir build -C Release -R pol_native_queue_tests --output-on-failure; if ($LASTEXITCODE) { exit $LASTEXITCODE } }
```

Expected: all 20 runs pass.

- [ ] **Step 4: Commit the queue slice**

```powershell
git add CMakeLists.txt src/pol_native/speech_queue.h src/pol_native/speech_queue.cpp tests/pol_native_queue_tests.cpp
git commit -m "Add bounded native PlayOnline speech queue"
```

---

### Task 3: Add the dynamically loaded Prism runtime and worker

**Files:**

- Create: `src/pol_native/diagnostics.h`
- Create: `src/pol_native/diagnostics.cpp`
- Create: `src/pol_native/prism_runtime.h`
- Create: `src/pol_native/prism_runtime.cpp`
- Create: `src/pol_native/speech_worker.h`
- Create: `src/pol_native/speech_worker.cpp`
- Create: `tests/fakes/fake_prism.cpp`
- Create: `tests/fakes/fake_prism.def`
- Create: `tests/pol_native_speech_worker_tests.cpp`
- Modify: `CMakeLists.txt`

- [ ] **Step 1: Write the fake Prism DLL and failing worker tests**

The fake DLL must export the real C ABI names used by shipped Prism and write calls to a path provided by `ACCESSXI_FAKE_PRISM_LOG`. Environment flags must independently force context, backend initialization, and first-output failure.

Test that the worker:

- loads `prism.dll` only from the supplied absolute dependency directory;
- calls `prism_init` and tries NVDA, then JAWS, then UIA, then `prism_registry_create_best`;
- waits for a real visible top-level window belonging to the current process before UIA;
- signals ready only after a backend initializes;
- calls `prism_backend_output` only on its worker thread;
- passes the queue's interrupt flag unchanged;
- resets the context/backend and retries exactly once after output failure;
- fails cleanly after the bounded initialization deadline;
- writes escaped diagnostics without speech text in fatal/startup records.

Run:

```powershell
cmake --build build --config Release --target pol_native_speech_worker_tests fake_prism
ctest --test-dir build -C Release -R pol_native_speech_worker_tests --output-on-failure
```

Expected: FAIL because the runtime and worker do not exist.

- [ ] **Step 2: Implement thread-safe diagnostics**

`Diagnostics` resolves `%USERPROFILE%\AccessXI\logs`, creates directories outside loader lock, appends timestamped UTF-8 records using a mutex, and provides separate startup and speech log methods. Speech diagnostics may log sequence/result/backend but must not include label text.

- [ ] **Step 3: Implement dynamic Prism loading**

`PrismRuntime` uses `LoadLibraryExW(absolute_path, nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS)` and resolves these required exports:

```text
prism_init
prism_shutdown
prism_registry_create
prism_registry_create_best
prism_backend_initialize
prism_backend_free
prism_backend_name
prism_backend_output
prism_backend_stop
```

Use the exact types and `__cdecl` calling convention from `third_party/prism/include/prism.h`. Do not link the ASI to `prism.lib`, and do not fall back to `%PATH%` or the current directory.

- [ ] **Step 4: Implement the single-owner worker**

`SpeechWorker` owns `SpeechQueue`, `PrismRuntime`, and one `std::thread`. Its initialization order is NVDA (`0x89CC19C5C4AC1A56`), JAWS (`0x0AC3D60E9BD84B53E`), UIA (`0x6238F019DB678F8E`) after a real process window is available, then create-best. It exposes `start`, bounded `wait_until_ready`, `enqueue`, `stop_for_tests`, and `stats`. A failed output triggers one full Prism reset/recreate and one retry of the newest item; a second failure is logged and dropped.

- [ ] **Step 5: Run worker and queue tests**

```powershell
cmake --build build --config Release --target pol_native_speech_worker_tests pol_native_queue_tests
ctest --test-dir build -C Release -R "pol_native_(speech_worker|queue)_tests" --output-on-failure
```

Expected: PASS with the fake DLL; no audible output occurs.

- [ ] **Step 6: Commit the Prism worker slice**

```powershell
git add CMakeLists.txt src/pol_native tests/fakes tests/pol_native_speech_worker_tests.cpp
git commit -m "Add native Prism speech worker"
```

---

### Task 4: Add the idempotent ASI host and fail-closed bootstrap

**Files:**

- Create: `src/pol_native/native_host.h`
- Create: `src/pol_native/native_host.cpp`
- Create: `src/pol_native/pol_native_asi.cpp`
- Create: `src/pol_native/pol_native_asi.def`
- Create: `tests/fakes/fake_pol_hook.cpp`
- Create: `tests/fakes/fake_pol_hook.def`
- Create: `tests/pol_native_host_tests.cpp`
- Modify: `CMakeLists.txt`

- [ ] **Step 1: Write failing path, fingerprint, and host tests**

Cover:

- dependency root is `<ASI directory>\AccessXI.PolNative` even when the current directory differs;
- file FNV-1a matches known vectors and reports exact size;
- the installed `app.dll` fixture matches `4335104` / `07E88E8067FEF6CC`;
- wrong size/hash never loads the fake hook DLL;
- missing Prism, missing hook DLL, missing sink export, and missing V2 initializer fail closed;
- the sink is registered before the V2 initializer is called;
- a V2 result other than `1` or `2` fails startup;
- concurrent calls to the startup entry schedule exactly one worker;
- the callback copies text before returning and remains bounded under stress;
- fatal initialization schedules at most one `MessageBoxW` notification outside `DllMain`.

Run:

```powershell
cmake --build build --config Release --target pol_native_host_tests fake_pol_hook
ctest --test-dir build -C Release -R pol_native_host_tests --output-on-failure
```

Expected: FAIL because the native host is absent.

- [ ] **Step 2: Implement `NativeHost`**

The bootstrap worker must:

1. derive its ASI directory via `GetModuleFileNameW(asi_module)`;
2. wait up to 30 seconds for loaded `app.dll`;
3. hash the module file and reject every profile except the exact known build;
4. construct absolute private paths for `prism.dll` and `accessxi_pol_native.dll`;
5. start `SpeechWorker` and wait up to 20 seconds for readiness;
6. load the hook DLL with safe absolute-path flags;
7. resolve `AccessXI_POL_SetSpeechSinkV1` and `AccessXI_POL_InitializeV2`;
8. register a `__stdcall` callback that only enqueues a copied UTF-8 label;
9. call V2 and accept only `1` (ready) or `2` (already ready);
10. log a stable `ACCESSXI_POL_NATIVE ready` marker.

On failure, log the stage and Windows/ABI result, stop before the next step, and show one standard Windows error dialog naming `%USERPROFILE%\AccessXI\logs\pol-native-startup.log`. Never log label text in fatal diagnostics.

- [ ] **Step 3: Implement the ASI entry points**

`pol_native_asi.cpp` stores the module handle and exposes both:

```cpp
extern "C" __declspec(dllexport) void InitializeASI();
BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved);
```

Both process-attach and `InitializeASI` call one atomic `schedule_startup_once`. The scheduler creates one bootstrap thread and returns immediately. Process detach only flips a stopping atomic; it does not wait, unload DLLs, unhook, call Prism, or write logs.

`pol_native_asi.def` exports undecorated `InitializeASI` and names the library `AccessXI.PolNative`.

- [ ] **Step 4: Make host tests pass and stress startup**

```powershell
cmake --build build --config Release --target pol_native_host_tests
1..20 | ForEach-Object { ctest --test-dir build -C Release -R pol_native_host_tests --output-on-failure; if ($LASTEXITCODE) { exit $LASTEXITCODE } }
```

Expected: all 20 runs pass and fake-hook logs show sink registration before initialization exactly once per process.

- [ ] **Step 5: Commit the host slice**

```powershell
git add CMakeLists.txt src/pol_native tests/fakes tests/pol_native_host_tests.cpp
git commit -m "Add native PlayOnline ASI host"
```

---

### Task 5: Add reproducible x86 build and structural verification

**Files:**

- Modify: `CMakeLists.txt`
- Create: `tools/build_pol_native_asi.ps1`
- Create: `tools/test_pol_native_asi_structure.ps1`
- Create: `tools/test_pol_native_offline.ps1`

- [ ] **Step 1: Write the failing structural test**

Assert that the staged prototype contains exactly:

```text
stage\pol-native\AccessXI.PolNative.asi
stage\pol-native\AccessXI.PolNative\accessxi_pol_native.dll
stage\pol-native\AccessXI.PolNative\prism.dll
```

Also assert:

- all three PE files are x86 (`Machine 14C`);
- the ASI exports undecorated `InitializeASI`;
- hook DLL exports the V1 sink and V2 initializer;
- `dumpbin /dependents` for the ASI has no CLR, Reloaded, `prism.dll`, or hook-DLL import;
- `corflags`/PE inspection finds no CLR header in the ASI or hook DLL;
- source/build outputs contain no machine-specific `C:\Users\buu42` path;
- Prism staged hash matches the selected local 32-bit Prism source.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_asi_structure.ps1
```

Expected: FAIL because the stage/build helper does not exist.

- [ ] **Step 2: Add the CMake ASI target**

Add a Win32-only shared-library target from the production native-host sources, compile as C++20, link `user32`, and set:

```cmake
PREFIX ""
OUTPUT_NAME "AccessXI.PolNative"
SUFFIX ".asi"
RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
```

Fail CMake configuration when `CMAKE_SIZEOF_VOID_P` is not 4 for this target.

- [ ] **Step 3: Add the build/stage helper**

`tools/build_pol_native_asi.ps1` must accept `RepoRoot`, `Configuration`, and optional `PrismDll`; configure `build` as Win32, build the hook DLL, ASI, and native tests, run CTest, clean only the verified repo-local `stage\pol-native` directory, and stage the three-file layout. Default Prism selection is the verified x86 `C:\Users\buu42\AccessXI\external\Reloaded-II\Mods\AccessXI.PolReloaded\prism.dll`, but the absolute user path must remain in the script parameter default only until installer migration; it must never be compiled into binaries.

- [ ] **Step 4: Add the offline integration runner**

`tools/test_pol_native_offline.ps1` builds fake dependencies, runs queue/worker/host tests, verifies startup ordering from fake logs, and confirms forced failures never reach fake hook initialization.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_pol_native_asi.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_asi_structure.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_offline.ps1
```

Expected: all pass and print hashes for the staged ASI, hook DLL, and Prism.

- [ ] **Step 5: Run the complete existing POL regression set**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_prelogin_native_focus.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_reloaded_split.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_reloaded_portable_diagnostics.ps1
```

Expected: PASS.

- [ ] **Step 6: Commit the reproducible build slice**

```powershell
git add CMakeLists.txt tools/build_pol_native_asi.ps1 tools/test_pol_native_asi_structure.ps1 tools/test_pol_native_offline.ps1
git commit -m "Build native PlayOnline Prism prototype"
```

---

### Task 6: Add and validate reversible local deployment

**Files:**

- Create: `tools/deploy_pol_native_asi.ps1`
- Create: `tools/rollback_pol_native_asi.ps1`
- Create: `tools/test_pol_native_deployment.ps1`
- Create: `docs/playonline-native-prototype.md`

- [ ] **Step 1: Write failing deployment tests against a temporary fake PlayOnline tree**

Test that deployment:

- rejects a running `pol.exe` process;
- requires existing `pol.exe`, `viewer\com\app.dll`, and `ddraw.dll`;
- rejects the wrong `app.dll` size/FNV;
- refuses every destination outside the explicitly resolved PlayOnline root;
- records pre/post SHA-256 for `pol.exe` and `app.dll` and proves they do not change;
- preserves an existing native prototype in a timestamped backup;
- renames active `AccessXI.PolReloadedBootstrap.asi` to `.disabled` without deleting it;
- copies only the three staged prototype files;
- is idempotent;
- rollback disables the native ASI and restores exactly one Reloaded bootstrap;
- rollback is idempotent and does not touch Square Enix binaries.

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_deployment.ps1
```

Expected: FAIL because deployment scripts do not exist.

- [ ] **Step 2: Implement safe deployment**

`deploy_pol_native_asi.ps1` defaults to `C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer`, verifies `Get-Process pol` is empty, validates the exact app fingerprint, resolves and bounds every destination, writes a timestamped manifest under `%USERPROFILE%\AccessXI\backups\pol-native\`, disables the Reloaded ASI, deploys the staged layout, and verifies source/destination hashes plus unchanged Square Enix hashes. It must not launch PlayOnline.

- [ ] **Step 3: Implement rollback and operator notes**

`rollback_pol_native_asi.ps1` requires PlayOnline closed, renames `AccessXI.PolNative.asi` to `.disabled`, restores `AccessXI.PolReloadedBootstrap.asi.disabled` to active, leaves dependencies for inspection, and verifies Square Enix hashes. `docs/playonline-native-prototype.md` documents ordinary launch, log paths, success markers, password/OTP validation, rapid-navigation checks, and the one-command rollback.

- [ ] **Step 4: Pass deployment tests and dry run**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_deployment.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\deploy_pol_native_asi.ps1 -WhatIf
```

Expected: tests pass; `-WhatIf` reports bounded intended changes only.

- [ ] **Step 5: Commit the deployment slice**

```powershell
git add tools/deploy_pol_native_asi.ps1 tools/rollback_pol_native_asi.ps1 tools/test_pol_native_deployment.ps1 docs/playonline-native-prototype.md
git commit -m "Add reversible native PlayOnline deployment"
```

---

### Task 7: Deploy the prototype and verify the handoff boundary

**Files:**

- Runtime output: `%USERPROFILE%\AccessXI\logs\pol-native-startup.log`
- Runtime output: `%USERPROFILE%\AccessXI\logs\pol-native-speech.log`
- Deployment manifest: `%USERPROFILE%\AccessXI\backups\pol-native\<timestamp>\manifest.json`

- [ ] **Step 1: Run final pre-deployment verification**

```powershell
git status --short
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_pol_native_asi.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_asi_structure.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_offline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_deployment.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_prelogin_native_focus.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_reloaded_split.ps1
```

Expected: all tests pass; only intended files plus the user's untracked handoff appear in status.

- [ ] **Step 2: Capture immutable game-file evidence and deploy**

```powershell
Get-FileHash 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\pol.exe' -Algorithm SHA256
Get-FileHash 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\viewer\com\app.dll' -Algorithm SHA256
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\deploy_pol_native_asi.ps1
```

Expected: deployment succeeds only while PlayOnline is closed, disables the Reloaded bootstrap, stages the native prototype, and reports unchanged hashes.

- [ ] **Step 3: Verify deployed structure without launching**

Confirm exact source/deployed hashes, active `AccessXI.PolNative.asi`, inactive Reloaded bootstrap, unchanged `pol.exe`/`app.dll`, and no active `pol` process. Do not claim speech works before a real launch.

- [ ] **Step 4: Hand off ordinary-launch validation**

Tell the user the normal PlayOnline shortcut is ready. On their launch, inspect fresh logs for this ordered sequence:

```text
ACCESSXI_POL_NATIVE worker-start
ACCESSXI_POL_NATIVE app-fingerprint-ok
ACCESSXI_POL_NATIVE prism-ready
ACCESSXI_POL_NATIVE speech-sink-registered
ACCESSXI_POL_NATIVE hook-initialize-ok
ACCESSXI_POL_NATIVE ready
```

Then verify module state contains `AccessXI.PolNative.asi`, `accessxi_pol_native.dll`, and `prism.dll`, but no Reloaded bootstrap/mod/CLR modules. Live acceptance still requires member-list/menu speech, password and OTP silence, rapid arrowing without backlog, clean exit, and a second launch.

- [ ] **Step 5: Preserve rollback readiness**

If startup crashes, hangs, mismatches the fingerprint, speaks credentials, or produces unverified labels, stop testing, inspect fresh logs/crash records, and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\rollback_pol_native_asi.ps1
```

Do not widen hooks or guess labels to force speech. Installer migration remains blocked until all live acceptance checks pass.

