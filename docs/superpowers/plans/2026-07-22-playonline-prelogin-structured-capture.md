# PlayOnline Pre-Login Structured Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace unowned pre-login member-name guesses with selection-backed native text, extend the opt-in PlayOnline capture across pre-login, and provide masked-field state feedback without exposing secret contents.

**Architecture:** Keep PlayOnline hooks thin: they copy stable focus/selection relationships and sanitized metadata into the existing bounded queue. A new pure C++ semantics module decides whether member text is relationship-backed and converts proven masked display lengths into fixed speech; `accessxi_pol.cpp` supplies only Ghidra-verified native evidence. Unknown or ambiguous controls are captured silently.

**Tech Stack:** C++20, Win32 x86 hooks, Prism speech sink, CMake/CTest, PowerShell integration guards, local Ghidra evidence for the recognized PlayOnline `app.dll`.

## Global Constraints

- Target Win32 only and preserve the recognized `app.dll` size `4335104` and FNV-1a `0x07E88E8067FEF6CC` fail-closed gate.
- Do not modify Square Enix `pol.exe` or `app.dll`.
- False positives are worse than silence: member text requires selected-index and selected-child ownership proof.
- Do not use OCR, guessed row tables, arbitrary recursive pointer walks, or keyboard-direction inference.
- Keep the crash-disabled `PmlTextSetterRva` hook disabled.
- Keep callbacks free of file I/O, Prism calls, and blocking waits; serialize traces on the existing worker.
- `Ctrl+Shift+F10` remains the explicit capture start/stop chord, and capture stops when `FFXiMain.dll` loads.
- A password or one-time-password context may retain only its field role and masked display count. Raw secret text must not enter snapshots, queues, logs, or Prism.
- Preserve the current uncommitted selected-image/post-login work and do not stage `ACCESSXI_HANDOFF_2026-07-12_ROUTE_RECORDER.md`.

---

### Task 1: Add pure relationship and masked-state semantics

**Files:**

- Create: `src/pol_accessibility/prelogin_semantics.h`
- Create: `src/pol_accessibility/prelogin_semantics.cpp`
- Create: `tests/pol_prelogin_semantics_tests.cpp`
- Modify: `CMakeLists.txt`
- Modify: `tools/test_pol_native_offline.ps1`
- Modify: `tools/build_pol_native_asi.ps1`

**Interfaces:**

- Produces: `ControlRole`, `MemberEvidence`, `MemberDecision`, `decide_member_candidate`, `masked_display_count`, `masked_focus_speech`, and `masked_delta_speech`.
- Consumes: standard C++ only; no Windows, Prism, or PlayOnline headers.

- [ ] **Step 1: Write the failing semantics tests**

Create `tests/pol_prelogin_semantics_tests.cpp` with explicit cases for ownership and secret handling:

```cpp
#include "pol_accessibility/prelogin_semantics.h"

#include <cstdlib>
#include <iostream>
#include <limits>

using namespace accessxi::pol_accessibility;

static void require(bool condition, const char* message)
{
    if (!condition) { std::cerr << "FAIL: " << message << '\n'; std::exit(1); }
}

int main()
{
    MemberEvidence unrelated{"Rich", true, true, false, false};
    require(!decide_member_candidate(unrelated).trusted,
        "name-like text without selected-child ownership was trusted");

    MemberEvidence owned{"Actual Member", true, true, true, true};
    const auto member = decide_member_candidate(owned);
    require(member.trusted && member.text == "Actual Member",
        "selected child-owned member text was rejected");

    require(masked_display_count(u"******") == 6,
        "asterisk display length was not preserved");
    require(masked_display_count(u"\u2022\u2022\u2022") == 3,
        "bullet display length was not preserved");
    require(masked_display_count(u"secret") == InvalidMaskedCount,
        "unmasked content was accepted as a masked display");

    require(masked_focus_speech(ControlRole::password, 0) == "Password, empty",
        "empty password focus speech mismatch");
    require(masked_focus_speech(ControlRole::one_time_password, 6) ==
            "One-time password, 6 characters entered",
        "one-time-password count speech mismatch");
    require(masked_delta_speech(ControlRole::password, 5, 6) == "star",
        "single accepted character did not speak star");
    require(masked_delta_speech(ControlRole::password, 2, 6) ==
            "Password, 6 characters entered",
        "multi-character insertion did not speak the resulting count");
    require(masked_delta_speech(ControlRole::password, 6, 6).empty(),
        "unchanged masked state produced speech");

    std::cout << "ok: pre-login ownership and masked-state semantics\n";
}
```

Add the test target to CMake and both native build helpers.

- [ ] **Step 2: Run the focused target and verify RED**

Run:

```powershell
$env:ASHITA4_SDK_PATH='C:\Users\buu42\Ashita\plugins\sdk'
cmake -S . -B build -A Win32
cmake --build build --config Release --target pol_prelogin_semantics_tests
```

Expected: compilation fails because `pol_accessibility/prelogin_semantics.h` does not exist.

- [ ] **Step 3: Implement the pure semantics module**

Expose this contract in the header:

```cpp
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <string_view>

namespace accessxi::pol_accessibility
{
    inline constexpr size_t InvalidMaskedCount = std::numeric_limits<size_t>::max();

    enum class ControlRole : uint8_t {
        unknown, member_list, selected_member, list_row, button,
        static_label, editable, password, one_time_password
    };

    struct MemberEvidence {
        std::string_view text;
        bool member_list_focused;
        bool selected_index_resolved;
        bool exact_selected_child;
        bool text_owned_by_selected_child;
    };

    struct MemberDecision { bool trusted; std::string text; const char* reason; };

    MemberDecision decide_member_candidate(const MemberEvidence& evidence);
    size_t masked_display_count(std::u16string_view displayed) noexcept;
    std::string masked_focus_speech(ControlRole role, size_t count);
    std::string masked_delta_speech(ControlRole role, size_t before, size_t after);
}
```

`decide_member_candidate` returns `trusted=true` only when all four relationship booleans are true and text is non-empty. `masked_display_count` accepts only `*`, U+2022 BULLET, or U+25CF BLACK CIRCLE and otherwise returns `InvalidMaskedCount`. Speech functions accept only the two secret roles; `after == before + 1` returns `star`, `after > before + 1` returns the labeled count, and unchanged or decreasing counts return empty.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```powershell
cmake --build build --config Release --target pol_prelogin_semantics_tests
ctest --test-dir build -C Release -R pol_prelogin_semantics_tests --output-on-failure
```

Expected: the target builds and `1/1` test passes.

- [ ] **Step 5: Commit the isolated semantics module**

```powershell
git add -- src/pol_accessibility/prelogin_semantics.h src/pol_accessibility/prelogin_semantics.cpp tests/pol_prelogin_semantics_tests.cpp CMakeLists.txt tools/test_pol_native_offline.ps1 tools/build_pol_native_asi.ps1
git commit -m "test: add PlayOnline pre-login accessibility semantics"
```

---

### Task 2: Require native selected-child ownership for member speech

**Files:**

- Modify: `src/accessxi_pol.cpp`
- Modify: `tools/test_pol_prelogin_native_focus.ps1`

**Interfaces:**

- Consumes: `accessxi::pol_accessibility::decide_member_candidate` from Task 1 and the existing Ghidra-backed `selected_child_from_native_index(void*, uint32_t)`.
- Produces: `SelectedMemberResolution` and `resolve_selected_member(void*, uint32_t)` plus a selected-member-only speech path.

- [ ] **Step 1: Change the integration guard to fail on unowned startup speech**

Update `tools/test_pol_prelogin_native_focus.ps1` so it requires:

```powershell
$selectedMember = Get-FunctionBody $source 'SelectedMemberResolution resolve_selected_member'
Assert-Contains $selectedMember 'decide_member_candidate' 'Selected member text must pass the pure ownership decision.'
Assert-Contains $selectedMember 'selected_child_from_native_index' 'Selected member text must use the native indexed child.'

$currentChildResolver = Get-FunctionBody $source 'void process_current_child_candidate'
if ($currentChildResolver -match 'native_prelogin_startup_member_name_from_(focus|atlas_member_list_focus|static_member_list_focus)') {
    throw 'Current-child focus must not promote startup member guesses to speech.'
}
if ($currentChildResolver -match 'startup-member-dynamic') {
    throw 'The unowned startup-member-dynamic speech source must be removed.'
}
```

Keep the existing requirement that selected-index lookup uses `PmlIndexedChildAtRva`. Remove prior assertions that require global/model/child-slot fallback calls from the speech resolver; retain diagnostic-only probe assertions separately.

- [ ] **Step 2: Run the guard and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_prelogin_native_focus.ps1
```

Expected: failure because `process_current_child_candidate` still promotes `startup-member-dynamic` values.

- [ ] **Step 3: Implement selected-child-only member resolution**

Add this result type and resolver beside the existing native index helper:

```cpp
struct SelectedMemberResolution
{
    uint32_t stored_index = 0;
    void* selected_child = nullptr;
    std::string label;
    const char* source = "selected-index";
};

SelectedMemberResolution resolve_selected_member(void* model, uint32_t requested_index);
```

The resolver must:

1. read the stored index from `model + 0x2A4`;
2. resolve the exact child with `selected_child_from_native_index`;
3. read direct selected text first, then dynamic text only from that same selected child when its verified member-value rectangle matches;
4. call `decide_member_candidate` with all ownership evidence; and
5. return empty on any missing or ambiguous link.

Use that single result in `remember_selected_index_candidate` for capture and speech so the selected child is not looked up twice. Preserve source `selected-member-dynamic` only for the exact selected-child result.

Remove all three startup-member fallback calls from `process_current_child_candidate`. When the Member List container receives focus, speak its verified static `Member List` label if available; otherwise remain silent. Keep bounded probe functions available only while the opt-in trace is active, and never call `read_native_prelogin_member_name()` from a speech decision.

- [ ] **Step 4: Run the guard and focused regression tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_prelogin_native_focus.ps1
cmake --build build --config Release --target accessxi_pol_nvda pol_prelogin_semantics_tests pol_pml_selected_text_tests
ctest --test-dir build -C Release -R 'pol_prelogin_semantics_tests|pol_pml_selected_text_tests' --output-on-failure
```

Expected: the guard passes, the hook DLL builds, and both CTest cases pass.

- [ ] **Step 5: Commit the member ownership fix without staging unrelated files**

```powershell
git add -- src/accessxi_pol.cpp tools/test_pol_prelogin_native_focus.ps1
git commit -m "fix: require selected member ownership in PlayOnline"
```

---

### Task 3: Generalize capture and sanitize secret fields before collection

**Files:**

- Modify: `src/pol_trace/postlogin_trace.h`
- Modify: `src/pol_trace/postlogin_trace.cpp`
- Modify: `tests/pol_postlogin_trace_tests.cpp`
- Modify: `src/accessxi_pol.cpp`
- Modify: `tools/test_pol_postlogin_trace_integration.ps1`

**Interfaces:**

- Consumes: `ControlRole`, masked display validation, stable focus/current-child/selected-index hooks, and the existing 1024-entry `TraceBuffer`.
- Produces: `%USERPROFILE%\AccessXI\logs\pol-ui-native-trace.tsv`, role/relationship/rejection metadata, and safe masked-state records.

- [ ] **Step 1: Extend trace tests and integration guards first**

Add unit assertions that formatted snapshots contain:

```text
role=selected-member
relation=indexed-child
rejection=none
masked_count=6
```

Add a `make_masked_snapshot(ControlRole role, uint32_t count)` test using a sentinel secret and assert the sentinel is absent from `format_event`.

Update `tools/test_pol_postlogin_trace_integration.ps1` to require:

- `DefaultPolUiTraceFileName = L"pol-ui-native-trace.tsv"`;
- fixed status speech `PlayOnline capture started` and `PlayOnline capture stopped`;
- role classification before `collect_pol_ui_trace_candidates`;
- a secret-role branch that skips generic candidate collection;
- secret sanitization before `g_pol_ui_trace.enqueue(snapshot)`;
- member selected-index snapshots use relation `indexed-child`; and
- `FFXiMain.dll` still triggers automatic stop.

- [ ] **Step 2: Run both guards and verify RED**

Run:

```powershell
cmake --build build --config Release --target pol_postlogin_trace_tests
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_postlogin_trace_integration.ps1
```

Expected: failure because the trace schema has no role/relationship/masked fields and still uses post-login naming.

- [ ] **Step 3: Extend the bounded snapshot schema**

Add fixed-size fields to `Snapshot`:

```cpp
accessxi::pol_accessibility::ControlRole role = ControlRole::unknown;
Relationship relation = Relationship::none;
uint32_t masked_count = 0;
bool has_masked_count = false;
char rejection_reason[48]{};
```

Define `Relationship` as `none`, `focused`, `current_child`, `indexed_child`, or `nested_child`, add stable name functions, and include the new fields in duplicate comparison and `format_event`. The trace module may depend on the pure semantics header but must remain independent of Windows and Prism.

- [ ] **Step 4: Rename the session as a full PlayOnline capture**

Mechanically rename only the capture state and helpers from `postlogin` to `pol_ui`, change the trace filename to `pol-ui-native-trace.tsv`, and change fixed status speech to `PlayOnline capture started/stopped`. Preserve the hotkey, worker-thread writer, queue bound, and FFXI auto-stop behavior.

- [ ] **Step 5: Classify roles before reading candidates**

In `capture_pol_ui_snapshot`, establish relationship from the event itself. Classify a selected-index event as `selected_member` only when its exact selected child matches the verified member-value shape; otherwise classify it as `list_row`. Classify focused/current-child secret roles only from a proven login or Add Member screen context plus the existing Ghidra-backed password/one-time-password geometry.

For secret roles:

1. do not call the generic resolver or candidate collector;
2. read only the bounded visible display associated with the exact focused child;
3. pass it through `masked_display_count` immediately;
4. store only role and count when the display consists exclusively of mask glyphs; and
5. use rejection `masked-display-unverified` with no candidates when it does not.

For non-secret roles, retain the existing bounded candidate collection and tag every snapshot with its relationship and rejection reason. Broad probe candidates remain trace-only.

- [ ] **Step 6: Add the masked-state worker tracker**

Track the exact focused secret object, role, and last verified count on the existing 20 ms worker. On focus entry, dispatch `masked_focus_speech`. While the same object stays focused, dispatch `masked_delta_speech` only after a newly verified display count differs. Reset the tracker immediately when focus leaves the proven secret object, the display becomes unverified, or FFXI loads.

Do not infer accepted input from keyboard state. A rejected key must not speak because the native masked count did not change.

- [ ] **Step 7: Run focused tests and guards**

Run:

```powershell
cmake --build build --config Release --target accessxi_pol_nvda pol_postlogin_trace_tests pol_prelogin_semantics_tests
ctest --test-dir build -C Release -R 'pol_postlogin_trace_tests|pol_prelogin_semantics_tests' --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_postlogin_trace_integration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_prelogin_native_focus.ps1
```

Expected: both CTest cases and both PowerShell guards pass.

- [ ] **Step 8: Commit the capture integration**

```powershell
git add -- src/pol_trace/postlogin_trace.h src/pol_trace/postlogin_trace.cpp tests/pol_postlogin_trace_tests.cpp src/accessxi_pol.cpp tools/test_pol_postlogin_trace_integration.ps1
git commit -m "feat: capture structured PlayOnline pre-login state"
```

---

### Task 4: Verify, build, deploy, and collect the live evidence pass

**Files:**

- Modify only for a diagnosed regression: the responsible source or test file
- Generated/staged: `build/bin/Release/*`, `stage/pol-native/*`
- Deploy: `C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\scripts\AccessXI.PolNative*`

**Interfaces:**

- Consumes: Tasks 1-3 and existing reversible build/deployment scripts.
- Produces: a verified installed build and one structured pre-login trace for any remaining silent controls.

- [ ] **Step 1: Run the complete offline suite**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_offline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_prelogin_native_focus.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_selected_text_integration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_postlogin_trace_integration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_asi_structure.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_deployment.ps1
```

Expected: every command exits zero. Diagnose any failure at its source and add the smallest regression test before changing implementation.

- [ ] **Step 2: Build the release stage**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_pol_native_asi.ps1
```

Expected: Win32 configure/build succeeds and all CTest cases pass.

- [ ] **Step 3: Deploy reversibly after confirming PlayOnline is closed**

Run:

```powershell
Get-Process -Name pol -ErrorAction SilentlyContinue
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\deploy_pol_native_asi.ps1
```

Expected: deployment creates a new backup manifest and does not alter Square Enix binary hashes.

- [ ] **Step 4: Verify staged and installed hashes**

Run:

```powershell
$stage='C:\Users\buu42\AccessXI\stage\pol-native'
$installed='C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\scripts'
Get-FileHash "$stage\AccessXI.PolNative.asi","$installed\AccessXI.PolNative.asi" -Algorithm SHA256
Get-FileHash "$stage\AccessXI.PolNative\accessxi_pol_native.dll","$installed\AccessXI.PolNative\accessxi_pol_native.dll" -Algorithm SHA256
Get-FileHash "$stage\AccessXI.PolNative\prism.dll","$installed\AccessXI.PolNative\prism.dll" -Algorithm SHA256
```

Expected: every staged/installed pair has the same SHA-256 value.

- [ ] **Step 5: Perform a pre-login smoke launch**

Launch normal PlayOnline:

```powershell
$pol='C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\viewer\pol.exe'
Start-Process -FilePath $pol
```

Verify native initialization and Prism readiness in `%USERPROFILE%\AccessXI\logs\pol-native-startup.log`, `pol-native-speech.log`, and `pol-monitor.log`, then close PlayOnline through its normal UI. Do not enter credentials during automated smoke testing.

- [ ] **Step 6: Run one uninterrupted user capture**

The user starts PlayOnline, presses `Ctrl+Shift+F10` on the first pre-login screen, traverses the member list and every affected pre-login screen, enters non-sensitive test characters into masked fields, signs in, verifies the post-login screen still reads, and lets capture stop automatically when FFXI loads or presses the hotkey again. No intermediate confirmations are required.

- [ ] **Step 7: Analyze only relationship-backed records**

Parse `pol-ui-native-trace.tsv`, correlate event sequence, role, relation, resource, rectangle, and selected child, and compare unresolved controls with the local Ghidra project. Enable any remaining label only when the trace identifies a stable native role/value path. Leave unresolved controls silent and record their rejection reason.

- [ ] **Step 8: Re-run verification after any evidence-backed adjustment**

Repeat Steps 1-5 and deploy the final verified build. Do not declare the member name, masked feedback, or other pre-login screens fixed until the live speech log confirms the visible value and the trace contains no secret text.
