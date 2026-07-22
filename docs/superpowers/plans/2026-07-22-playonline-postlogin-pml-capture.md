# PlayOnline Post-Login PML Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy an opt-in diagnostic build that records bounded native PML focus and selected-row evidence for the user's post-login PlayOnline walkthrough without speaking unverified text.

**Architecture:** Existing Ghidra-backed focus, current-child, and selected-index hooks create fixed-size snapshots and enqueue them into a dedicated in-memory trace buffer. The existing 20 ms worker owns hotkey/session state and file I/O, drains snapshots into an escaped TSV log, and emits only fixed AccessXI start/stop status speech. The crash-prone PML text-setter hook remains disabled.

**Tech Stack:** C++20, Win32 x86, CMake/Visual Studio 2022, existing native ASI and hook DLL, Prism speech sink for fixed status messages, PowerShell structural regressions, Ghidra-verified PML offsets.

## Global Constraints

- Do not modify `PlayOnlineViewer\pol.exe` or `PlayOnlineViewer\viewer\com\app.dll`.
- Recognize only `app.dll` size `4335104` and FNV-1a 64-bit `0x07E88E8067FEF6CC`; fail closed on every other build.
- Capture is disabled by default and starts only on a rising edge of `Ctrl+Shift+F10` after login.
- Do not re-enable `PmlTextSetterRva`, hook `DrawTextA`, use OCR, add guessed labels, or synthesize labels from row order.
- Hook callbacks may perform bounded safe memory reads and a short in-memory enqueue; they may not perform file I/O, call Prism, or wait on disk.
- Captured text never enters the speech sink. Only fixed AccessXI capture-started and capture-stopped messages may be spoken.
- Stop capture when `FFXiMain.dll` loads.
- Preserve password and one-time-password suppression and redact an entire snapshot when its captured context contains either term.
- Do not stage or commit `ACCESSXI_HANDOFF_2026-07-12_ROUTE_RECORDER.md`.
- Preserve all existing native ASI, Prism, Reloaded compatibility, and rollback behavior.

---

### Task 1: Add a bounded PML trace buffer and formatter

**Files:**

- Create: `src/pol_trace/postlogin_trace.h`
- Create: `src/pol_trace/postlogin_trace.cpp`
- Create: `tests/pol_postlogin_trace_tests.cpp`
- Modify: `CMakeLists.txt`
- Modify: `tools/test_pol_native_offline.ps1`
- Modify: `tools/build_pol_native_asi.ps1`

**Interfaces:**

- Produces: `accessxi::pol_trace::TraceBuffer`, `Snapshot`, `Candidate`, `EventKind`, `copy_utf8_bounded`, `format_schema`, `format_session`, `format_event`, and `format_dropped`.
- Consumes: only the C++ standard library. The module must not include Prism, Ashita, or PlayOnline headers.

The public header exposes these exact signatures:

```cpp
void copy_utf8_bounded(char* destination, size_t capacity, std::string_view value);
const char* event_kind_name(EventKind kind) noexcept;
std::string escape_tsv(std::string_view value);
std::string format_schema(uint64_t app_size, uint64_t app_fnv64);
std::string format_session(std::string_view action, uint64_t session, uint32_t tick, std::string_view reason);
std::string format_event(const Snapshot& value);
std::string format_dropped(uint64_t count);

class TraceBuffer
{
public:
    explicit TraceBuffer(size_t capacity);
    EnqueueResult enqueue(Snapshot value);
    bool try_dequeue(Snapshot& value);
    uint64_t take_dropped_count() noexcept;
    void reset();
};
```

- [ ] **Step 1: Write the failing trace-buffer tests**

Create `tests/pol_postlogin_trace_tests.cpp` with one test per required behavior:

```cpp
#include "pol_trace/postlogin_trace.h"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>

namespace
{
    using namespace accessxi::pol_trace;

    void require(bool condition, const char* message)
    {
        if (!condition)
        {
            std::cerr << "FAIL: " << message << '\n';
            std::exit(1);
        }
    }

    Snapshot event(EventKind kind, uint32_t tick, uintptr_t object, const char* label)
    {
        Snapshot value{};
        value.kind = kind;
        value.tick = tick;
        value.manager = 0x1000;
        value.object = object;
        value.requested_index = 2;
        value.stored_index = 2;
        value.trusted = true;
        copy_utf8_bounded(value.resolver_text, sizeof(value.resolver_text), label);
        return value;
    }

    void test_fifo_and_sequences()
    {
        TraceBuffer queue(4);
        require(queue.enqueue(event(EventKind::focus_shared, 10, 0x2000, "First")) == EnqueueResult::queued, "first event rejected");
        require(queue.enqueue(event(EventKind::focus_select, 20, 0x3000, "Second")) == EnqueueResult::queued, "second event rejected");
        Snapshot first{}, second{};
        require(queue.try_dequeue(first) && queue.try_dequeue(second), "queued events missing");
        require(first.sequence == 1 && second.sequence == 2, "sequence mismatch");
        require(first.object == 0x2000 && second.object == 0x3000, "FIFO mismatch");
    }

    void test_duplicate_window()
    {
        TraceBuffer queue(4);
        require(queue.enqueue(event(EventKind::selected_index, 100, 0x2000, "Row")) == EnqueueResult::queued, "initial event rejected");
        require(queue.enqueue(event(EventKind::selected_index, 149, 0x2000, "Row")) == EnqueueResult::duplicate, "49 ms duplicate not coalesced");
        require(queue.enqueue(event(EventKind::selected_index, 151, 0x2000, "Row")) == EnqueueResult::queued, "51 ms event incorrectly coalesced");
    }

    void test_capacity_drops_new_event_without_blocking()
    {
        TraceBuffer queue(2);
        require(queue.enqueue(event(EventKind::current_child, 1, 1, "A")) == EnqueueResult::queued, "A rejected");
        require(queue.enqueue(event(EventKind::current_child, 2, 2, "B")) == EnqueueResult::queued, "B rejected");
        require(queue.enqueue(event(EventKind::current_child, 3, 3, "C")) == EnqueueResult::full, "overflow not reported");
        require(queue.take_dropped_count() == 1, "drop count mismatch");
        require(queue.take_dropped_count() == 0, "drop count did not reset");
    }

    void test_utf8_truncation_preserves_code_points()
    {
        char output[5]{};
        copy_utf8_bounded(output, sizeof(output), "A\xE2\x82\xAC" "B");
        require(std::string(output) == "A\xE2\x82\xAC", "UTF-8 truncation split a code point");
    }

    void test_tsv_escaping_and_schema()
    {
        Snapshot value = event(EventKind::focus_select, 55, 0x2000, "A\tB\nC\\D");
        value.has_rect = true;
        value.rect = {1, 2, 3, 4};
        const std::string line = format_event(value);
        require(line.find("focus-select") != std::string::npos, "event kind missing");
        require(line.find("A\\tB\\nC\\\\D") != std::string::npos, "TSV escaping mismatch");
        require(line.find("1,2,3,4") != std::string::npos, "rectangle missing");
        require(format_schema(4335104, 0x07E88E8067FEF6CCull).find("07E88E8067FEF6CC") != std::string::npos, "fingerprint missing");
    }

    void test_reset_starts_new_sequence()
    {
        TraceBuffer queue(4);
        require(queue.enqueue(event(EventKind::focus_shared, 1, 1, "A")) == EnqueueResult::queued, "event rejected");
        queue.reset();
        require(queue.enqueue(event(EventKind::focus_shared, 2, 2, "B")) == EnqueueResult::queued, "post-reset event rejected");
        Snapshot value{};
        require(queue.try_dequeue(value) && value.sequence == 1, "reset did not restart sequence");
    }
}

int main()
{
    test_fifo_and_sequences();
    test_duplicate_window();
    test_capacity_drops_new_event_without_blocking();
    test_utf8_truncation_preserves_code_points();
    test_tsv_escaping_and_schema();
    test_reset_starts_new_sequence();
    std::cout << "ok: post-login PML trace bounds, ordering, dedupe, UTF-8, and TSV formatting\n";
    return 0;
}
```

Add a `pol_postlogin_trace_tests` target to `CMakeLists.txt`, add it to `ctest`, and include it in both native PowerShell build helpers.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
$env:ASHITA4_SDK_PATH='C:\Users\buu42\Ashita\plugins\sdk'
cmake -S . -B build -A Win32
cmake --build build --config Release --target pol_postlogin_trace_tests
```

Expected: FAIL because `pol_trace/postlogin_trace.h` and its implementation do not exist.

- [ ] **Step 3: Implement the minimal trace module**

Create a fixed-size `Snapshot` with the exact fields defined by the design:

```cpp
enum class EventKind : uint8_t { focus_shared, focus_select, current_child, selected_index };
enum class EnqueueResult : uint8_t { queued, duplicate, full };

struct Rect { int32_t left, top, right, bottom; };
struct Candidate { uint32_t offset{}; char source[32]{}; char text[241]{}; };
struct Snapshot
{
    uint64_t sequence{};
    uint32_t tick{};
    EventKind kind{};
    uint32_t event_code{};
    uintptr_t manager{}, requested_child{}, object{};
    uint32_t requested_index{}, stored_index{};
    uintptr_t focus_160{}, focus_164{}, focus_1c0{}, vtable{}, vtable_rva{};
    Rect rect{};
    bool has_rect{}, trusted{}, redacted{};
    char resolver_text[241]{};
    uint8_t candidate_count{};
    Candidate candidates[24]{};
};
```

`TraceBuffer::enqueue` must use `std::try_to_lock`; lock contention and full capacity increment one atomic dropped counter and return `full`. Assign sequence numbers only to queued records. Coalesce only when kind, manager, object, requested/stored index, resolver text, and trust result are identical and unsigned tick subtraction is at most 50 ms. `reset` clears queue, sequence, duplicate state, and drop count.

`copy_utf8_bounded` must null-terminate and back up to the start of a partially copied UTF-8 code point. `format_event` must escape backslash, tab, carriage return, newline, and other ASCII controls. It must serialize one record with stable columns:

```text
EVENT sequence tick kind event_code manager requested_child object requested_index stored_index focus160 focus164 focus1c0 vtable vtable_rva rect trusted redacted resolver candidates
```

`format_schema`, `format_session`, and `format_dropped` must produce records with the same escaping rules and no local timestamps; event ticks and session identifiers provide ordering.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```powershell
cmake --build build --config Release --target pol_postlogin_trace_tests
ctest --test-dir build -C Release -R pol_postlogin_trace_tests --output-on-failure
```

Expected: build succeeds and `1/1` test passes.

- [ ] **Step 5: Commit the independently tested trace module**

```powershell
git add -- src/pol_trace/postlogin_trace.h src/pol_trace/postlogin_trace.cpp tests/pol_postlogin_trace_tests.cpp CMakeLists.txt tools/test_pol_native_offline.ps1 tools/build_pol_native_asi.ps1
git commit -m "test: add bounded PlayOnline PML trace buffer"
```

---

### Task 2: Integrate opt-in snapshots with stable PML hooks

**Files:**

- Modify: `src/accessxi_pol.cpp`
- Create: `tools/test_pol_postlogin_trace_integration.ps1`
- Modify: `tools/test_pol_native_offline.ps1`

**Interfaces:**

- Consumes: `accessxi::pol_trace::TraceBuffer` and formatting functions from Task 1.
- Produces: `%USERPROFILE%\AccessXI\logs\pol-postlogin-pml-trace.tsv` and the `Ctrl+Shift+F10` start/stop workflow.

- [ ] **Step 1: Write the failing integration guard**

Create `tools/test_pol_postlogin_trace_integration.ps1`. It must load `src/accessxi_pol.cpp`, `src/pol_trace/postlogin_trace.cpp`, and `CMakeLists.txt` and assert all of the following:

```text
DefaultPostLoginTraceFileName is pol-postlogin-pml-trace.tsv
g_postlogin_trace_active is initialized false
Ctrl, Shift, and VK_F10 are required by poll_postlogin_trace_hotkey
start_postlogin_trace writes format_schema and format_session before publishing active=true
stop_postlogin_trace publishes active=false before draining
FFXiMain.dll causes an automatic stop
capture_postlogin_focus_event is called by both PML focus hooks
capture_postlogin_current_child is called by the current-child hook
capture_postlogin_selected_index is called after the original selected-index setter
PmlTextSetterRva remains followed by hook-disabled and crash-stability
no file-open function exists inside a function named capture_postlogin_*
src/pol_trace/postlogin_trace.cpp contains no speech, Prism, sink, or output call
accessxi_pol_nvda links src/pol_trace/postlogin_trace.cpp
```

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_postlogin_trace_integration.ps1
```

Expected: FAIL because the integration does not exist.

- [ ] **Step 2: Add session state and worker-owned file output**

In `src/accessxi_pol.cpp`, include the new header and add:

```cpp
constexpr const wchar_t* DefaultPostLoginTraceFileName = L"pol-postlogin-pml-trace.tsv";
std::atomic<bool> g_postlogin_trace_active{false};
accessxi::pol_trace::TraceBuffer g_postlogin_trace(1024);
bool g_postlogin_trace_hotkey_down = false;
uint64_t g_postlogin_trace_session = 0;
```

Add `src/pol_trace/postlogin_trace.cpp` to the existing `accessxi_pol_nvda` target in `CMakeLists.txt`; the ASI host target does not link this module.

Add `postlogin_trace_path`, a worker-only batch append function, `drain_postlogin_trace`, `start_postlogin_trace`, `stop_postlogin_trace`, and `poll_postlogin_trace_hotkey`. The start order must be:

```cpp
g_postlogin_trace.reset();
++g_postlogin_trace_session;
append(format_schema(KnownUpdatedAppDllSize, KnownUpdatedAppDllFnv64));
append(format_session("START", g_postlogin_trace_session, GetTickCount()));
g_postlogin_trace_active.store(true, std::memory_order_release);
dispatch_speech_sink_v1("Post-login capture started", 1);
```

The stop order must first publish `false`, then drain, write a `STOP` session record and any dropped count, and speak the fixed stop status. `poll_postlogin_trace_hotkey` must detect a rising edge only while Control, Shift, and F10 are all down. If capture is active and `native_post_login_surface_active()` reports `FFXiMain.dll`, stop with reason `ffxi-loaded`.

- [ ] **Step 3: Add bounded native evidence collection**

Add one helper that exits immediately unless `g_postlogin_trace_active` is true. Populate the pointer, focus relation, vtable/RVA, rectangle, resolver, and trust fields with the existing safe readers.

Candidate collection is restricted to the object itself and these Ghidra/current-reader fields:

```cpp
constexpr uintptr_t PmlTraceTextOffsets[] = {
    0x004u, 0x014u, 0x018u, 0x0C4u, 0x114u, 0x124u, 0x128u,
    0x154u, 0x158u, 0x160u, 0x164u, 0x188u, 0x18Cu,
    0x190u, 0x194u, 0x198u, 0x19Cu
};
```

For the object itself, try the proven inline narrow and wide PML string readers. For each listed field, record readable inline string fields, direct narrow/wide string pointers, and at most one linked object's inline PML string. Deduplicate identical source/offset/text triples and stop at 24 candidates. Do not walk any other offset or recursively follow links.

After candidate collection, lower-case a joined context consisting of the resolver and candidates. If it contains `password`, `one-time password`, or `one time password`, replace the resolver and every candidate text with `<redacted>`, set `redacted=true`, and set `trusted=false`.

- [ ] **Step 4: Connect snapshots without changing speech decisions**

Call diagnostic capture at these stable boundaries:

```cpp
// After focus_event_matches succeeds, before remember_focus_candidate.
capture_postlogin_focus_event(EventKind::focus_shared, self, event_info, focused_object);
capture_postlogin_focus_event(EventKind::focus_select, self, event_info, focused_object);

// After the original current-child setter and after reading manager+0x164.
capture_postlogin_current_child(self, new_child, reinterpret_cast<void*>(current_child));

// After the original selected-index setter and after resolving stored index and selected child.
capture_postlogin_selected_index(self, index, stored_index, selected_child);
```

Do not alter `remember_focus_candidate`, `remember_current_child_candidate`, `remember_selected_index_candidate`, `prelogin_pml_focus_candidate_label_allowed`, or `speak_prelogin_label` in this task. Add `poll_postlogin_trace_hotkey()` and `drain_postlogin_trace()` to `run_reloaded_native_hook_iteration()` on the worker thread.

- [ ] **Step 5: Run the integration guard and focused native tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_postlogin_trace_integration.ps1
cmake --build build --config Release --target accessxi_pol_nvda pol_postlogin_trace_tests
ctest --test-dir build -C Release -R pol_postlogin_trace_tests --output-on-failure
```

Expected: guard passes, hook DLL builds, and the trace test passes.

- [ ] **Step 6: Commit the diagnostic integration**

```powershell
git add -- src/accessxi_pol.cpp tools/test_pol_postlogin_trace_integration.ps1 tools/test_pol_native_offline.ps1
git commit -m "feat: capture opt-in PlayOnline post-login PML evidence"
```

---

### Task 3: Run full verification, build, deploy, and smoke-test

**Files:**

- Modify only if a regression is found: the file responsible for that regression
- Generated/staged: `build/bin/Release/*`, `stage/pol-native/*`
- Deploy: `C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\scripts\AccessXI.PolNative*`

**Interfaces:**

- Consumes: the diagnostic hook DLL from Task 2 and existing native ASI deployment scripts.
- Produces: a reversible installed diagnostic build ready for the user walkthrough.

- [ ] **Step 1: Run the complete offline regression suite**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_offline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_prelogin_native_focus.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_asi_structure.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_deployment.ps1
```

Expected: every command exits zero. If any fails, stop deployment, diagnose the failing layer, add or correct its regression test first, then make the smallest fix.

- [ ] **Step 2: Build the release stage**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_pol_native_asi.ps1
```

Expected: Win32 configure/build and all CTest cases succeed; staged ASI, hook, and Prism hashes are printed.

- [ ] **Step 3: Verify PlayOnline is closed and deploy reversibly**

Run:

```powershell
Get-Process -Name pol -ErrorAction SilentlyContinue
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\deploy_pol_native_asi.ps1
```

Expected: no `pol.exe` process before deployment; deployment creates a new backup manifest, preserves Square Enix binary hashes, disables the Reloaded bootstrap, and reports success.

- [ ] **Step 4: Verify staged and installed hashes**

Run:

```powershell
$stage='C:\Users\buu42\AccessXI\stage\pol-native'
$installed='C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\scripts'
Get-FileHash "$stage\AccessXI.PolNative.asi","$installed\AccessXI.PolNative.asi" -Algorithm SHA256
Get-FileHash "$stage\AccessXI.PolNative\accessxi_pol_native.dll","$installed\AccessXI.PolNative\accessxi_pol_native.dll" -Algorithm SHA256
Get-FileHash "$stage\AccessXI.PolNative\prism.dll","$installed\AccessXI.PolNative\prism.dll" -Algorithm SHA256
```

Expected: each staged hash equals its installed counterpart.

- [ ] **Step 5: Launch only for a pre-login smoke test if safe automation is available**

Launch the ordinary PlayOnline shortcut, wait for the viewer, and inspect:

```text
%USERPROFILE%\AccessXI\logs\pol-native-startup.log
%USERPROFILE%\AccessXI\logs\pol-native-speech.log
%USERPROFILE%\AccessXI\logs\pol-monitor.log
```

Expected: recognized fingerprint, native hook initialization result `1` or already-ready `2`, Prism ready, and no hook-install failure. Do not log in, do not press the capture hotkey, and do not claim the post-login capture works from this smoke test alone. Close PlayOnline afterward.

- [ ] **Step 6: Give the user the one-pass capture instructions**

Tell the user the build is installed only after Steps 1-5 have fresh evidence. The walkthrough instructions are exactly:

```text
Open PlayOnline and log in normally. Once you reach the first post-login screen, press Ctrl+Shift+F10 and wait for “Post-login capture started.” Go through every option that reads incorrectly, then move through the silent vertical list one row at a time from top to bottom and back up. Visit any other affected post-login screens. When finished, press Ctrl+Shift+F10 again and wait for “Post-login capture stopped,” then tell me you are done.
```

Do not ask for intermediate confirmations while the capture is active.
