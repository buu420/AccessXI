# PlayOnline Popup and Notice Speech Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Announce PlayOnline confirmation bodies and transient notice labels from exact Ghidra-proven native owners even when those labels never receive focus.

**Architecture:** Exact-build base-constructor hooks retain every completed
modal or notice owner in a bounded lock-free live-instance registry. Shared
base-destructor hooks invalidate derived instances safely. The existing native
worker validates exact Ghidra-proven base and derived vtables, follows only
inherited fixed `CLabel*` slots, requires two identical reads, deduplicates per
owner generation and slot, then sends modal bodies as interrupting speech and
notice changes as queued speech. Unsupported objects and malformed state stay
silent.

**Tech Stack:** C++20, Win32 x86, CMake/Visual Studio 2022, existing inline trampoline hooks, Prism speech sink, PowerShell structural regression tests, Ghidra 12.0.4 evidence for `app.dll`.

## Global Constraints

- Do not modify `PlayOnlineViewer\pol.exe` or `PlayOnlineViewer\viewer\com\app.dll`.
- Recognize only `app.dll` size `4335104` and FNV-1a 64-bit `0x07E88E8067FEF6CC`; fail closed on every other build.
- Do not hook `PmlTextSetterRva`, global drawing functions, or arbitrary label setters.
- Do not use OCR, guessed text, resource order, or recursive pointer scans.
- Constructor callbacks may call their trampoline and publish atomics only. They may not read text, allocate containers, log, call Prism, or perform file I/O.
- Publish each original-function trampoline before its patched entry can call
  the hook, retain up to 32 simultaneous owners per kind, and publish every
  owner pointer plus generation as one coherent atomic value.
- Quiesce other process threads for each constructor entry patch and refuse to
  patch while a thread is executing the seven-byte entry range.
- Invalidate registrations through each Ghidra-proven shared non-deleting base
  destructor so derived vtables cannot bypass lifetime tracking.
- Abort before constructor patching until every matching base-destructor
  invalidation hook is installed.
- Worker-side readers must require an exact base-or-derived owner vtable and an
  exact child vtable.
- Password, one-time-password, and edit-field content remain outside this feature.
- Stop and clear popup speech state when `FFXiMain.dll` loads.
- Do not stage or commit `ACCESSXI_HANDOFF_2026-07-12_ROUTE_RECORDER.md`.

---

### Task 1: Preserve exact Ghidra evidence for hook boundaries

**Files:**

- Create: `pol_re/scripts/PolPopupNoticeProbe.java`
- Create during research: `pol_re/out/popup_notice_probe_20260726.txt`

- [ ] **Step 1: Add a focused Ghidra report**

The script must emit:

- the installed image base and fingerprint context;
- RTTI names and vtables for the five modal owners, two notice owners,
  `CLabel`, and the important-notice rich component;
- the first complete instructions at every constructor entry until at least
  seven bytes are covered;
- decompilation of each constructor and the `CLabel` setter.

- [ ] **Step 2: Run the report against the analyzed installed binary**

Run:

```powershell
& 'C:\Users\buu42\AccessXI\tools\ghidra_12.0.4_PUBLIC\support\analyzeHeadless.bat' `
  'C:\Users\buu42\AccessXI\pol_re\projects_fresh_runtime_postlogin' `
  'PolFreshRuntimePostLogin' `
  -process '*' -recursive -noanalysis `
  -scriptPath 'C:\Users\buu42\AccessXI\pol_re\scripts' `
  -postScript 'PolPopupNoticeProbe.java' `
  'C:\Users\buu42\AccessXI\pol_re\out\popup_notice_probe_20260726.txt'
```

Expected: the unpacked live image that matches the installed fingerprint
resolves all supported owners and `CLabel`; every hook length ends on an
instruction boundary. Leave the important-notice rich component unsupported if
its visible text layout is not exact.

### Task 2: Add the strict native popup reader and decision-state tests

**Files:**

- Create: `src/pol_pml/native_popup_text.h`
- Create: `src/pol_pml/native_popup_text.cpp`
- Create: `tests/pol_pml_popup_text_tests.cpp`
- Modify: `CMakeLists.txt`

- [ ] **Step 1: Write failing tests for exact extraction**

Cover:

- all five modal vtables map only to their proven body field;
- both notice vtables map only to their proven `CLabel` fields;
- adjacent button pointers are ignored;
- an unknown owner vtable returns no candidate;
- a wrong child vtable returns no candidate;
- null, unreadable, unterminated, malformed UTF-16, control-containing, and
  overlong labels return no candidate;
- multiple valid notice labels retain their exact slot identity and order.

- [ ] **Step 2: Write failing tests for worker decisions**

Cover:

- a candidate must match across two polls before speech;
- the stable modal body emits once with interrupt policy;
- an unchanged candidate is deduplicated;
- a notice label change emits once without any focus event and uses queued
  policy;
- clearing and repopulating a slot creates a new notice event;
- unknown reads and one confirmed absence do not clear deduplication;
- two confirmed absences permit a real later reappearance;
- a new constructor generation permits the same text again;
- exact destructor invalidation publishes a tombstone generation;
- owner invalidation clears pending stability without emitting text.

- [ ] **Step 3: Configure and run the new test target to verify RED**

Run:

```powershell
cmake -S . -B build -A Win32
cmake --build build --config Release --target pol_pml_popup_text_tests
ctest --test-dir build -C Release --output-on-failure -R pol_pml_popup_text_tests
```

Expected: compilation or assertions fail because the production module does not
exist yet.

- [ ] **Step 4: Implement the minimum strict module**

Expose pure, dependency-free APIs for:

- exact owner classification and slot enumeration;
- bounded `CLabel` extraction through the existing `MemoryView`;
- stable/deduplicated per-slot observation; and
- modal versus notice speech policy.

- [ ] **Step 5: Run the focused tests to verify GREEN**

Run the same build and `ctest` commands. Expected: all popup text tests pass.

### Task 3: Add a failing runtime integration guard

**Files:**

- Create: `tools/test_pol_popup_notice_integration.ps1`
- Modify: `tools/test_pol_native_offline.ps1`

- [ ] **Step 1: Write structural assertions before runtime integration**

Assert that:

- every constructor RVA and supported vtable constant is present;
- popup hooks install only after `app_module_matches_known_updated_pol_build`;
- each hook calls its trampoline before publishing the owner;
- hook callbacks contain no text reader, speech, logging, file I/O, sleep, or
  object-tree scan;
- popup extraction and speech occur in the existing worker;
- popup processing precedes current-child/focus speech;
- reset clears owner registry and decision state;
- `PmlTextSetterRva` remains explicitly disabled.

- [ ] **Step 2: Run the guard to verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_pol_popup_notice_integration.ps1 -RepoRoot .
```

Expected: failure because runtime hooks and worker integration do not yet exist.

### Task 4: Integrate constructor registration and worker-side speech

**Files:**

- Modify: `src/accessxi_pol.cpp`
- Modify: `CMakeLists.txt`

- [ ] **Step 1: Add exact-build constructor and base-destructor hooks**

Add one trampoline and callback per supported constructor. Each callback:

1. invokes the original constructor;
2. retains `self`, owner kind, and an incremented generation in the bounded
   live-owner atomics;
3. returns without any other side effect.

Install the full set only after the existing `app.dll` fingerprint gate.

- [ ] **Step 2: Add worker-side processing**

In the 20 ms worker:

1. consume every live owner registration;
2. validate/extract exact candidates through `native_popup_text`;
3. pass each slot observation through the pure stability/dedup state;
4. speak eligible modal text with interruption and notice text without
   interruption;
5. log only bounded source/decision metadata, not pointer scans; and
6. process popup text before ordinary current-child/focus speech.

- [ ] **Step 3: Reset safely**

Clear registry, observed owner/generation, and decision state during existing
pre-login reset and when `FFXiMain.dll` loads.

- [ ] **Step 4: Run the integration guard to verify GREEN**

Run the Task 3 command. Expected: `ok`.

### Task 5: Add the new target to normal verification

**Files:**

- Modify: `tools/build_pol_native_asi.ps1`
- Modify: `tools/test_pol_native_offline.ps1`

- [ ] **Step 1: Include the popup tests and integration guard**

Add `pol_pml_popup_text_tests` to both build target lists and add the new
PowerShell guard to the offline test script.

- [ ] **Step 2: Run focused and regression verification**

Run:

```powershell
cmake --build build --config Release --target accessxi_pol_nvda pol_pml_popup_text_tests pol_pml_selected_text_tests pol_prelogin_semantics_tests pol_postlogin_trace_tests
ctest --test-dir build -C Release --output-on-failure -R "pol_pml_popup_text_tests|pol_pml_selected_text_tests|pol_prelogin_semantics_tests|pol_postlogin_trace_tests"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_pol_popup_notice_integration.ps1 -RepoRoot .
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_pol_native_offline.ps1
```

Expected: all commands exit zero.

### Task 6: Build, deploy, and verify the installed artifact

**Files:**

- Build: `build\bin\Release\accessxi_pol_nvda.dll`
- Deploy through: `tools/deploy_pol_native_asi.ps1`

- [ ] **Step 1: Confirm PlayOnline is closed**

Run:

```powershell
Get-Process pol -ErrorAction SilentlyContinue
```

Expected: no process. Do not replace an in-use DLL.

- [ ] **Step 2: Build and deploy**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build_pol_native_asi.ps1 -Configuration Release
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy_pol_native_asi.ps1
```

- [ ] **Step 3: Verify installed structure and hashes**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_pol_native_asi_structure.ps1 -RepoRoot .
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_pol_native_deployment.ps1 -RepoRoot .
```

Expected: both commands exit zero and the installed DLL hash matches the fresh
Release artifact.

### Task 7: Perform the reversible live check

- [ ] **Step 1: Open PlayOnline and trigger Exit**

Select Exit without confirming it. Expected: the visible confirmation sentence
speaks once. PlayOnline may announce the focused `Yes` or `No` first; after two
stable worker polls, the body interrupts so the decision context is not lost.

- [ ] **Step 2: Cancel Exit and inspect the monitor log**

Verify one popup-body speech decision for the modal generation, no repeated
body on subsequent worker polls, and no crash or UI stall.

- [ ] **Step 3: Observe a real transient notice when available**

Expected: a proven notice label speaks once when its native text changes even
though keyboard focus did not move.

- [ ] **Step 4: Commit only verified source, tests, tools, and documentation**

Review:

```powershell
git status --short
git diff --check
git diff --stat
```

Keep `ACCESSXI_HANDOFF_2026-07-12_ROUTE_RECORDER.md` untracked and unstaged.
