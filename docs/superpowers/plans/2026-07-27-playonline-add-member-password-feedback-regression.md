# PlayOnline Add Member Password Feedback Regression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore safe password-field feedback and immediate native Set Password choice speech on the PlayOnline Add Member form.

**Architecture:** Seed trackers only from exact, geometry-owned Add Member controls received through the native current-child hook. Poll the retained native `CPasswordField` or `CPulldown` object while transient PlayOnline overlays own focus, and announce only verified state changes.

**Tech Stack:** C++20, Win32 32-bit ASI/DLL injection, Prism speech, Ghidra 12.0.4, CTest, PowerShell integration tests.

## Global Constraints

- Never copy or speak password character storage.
- Accept only the recognized `app.dll` fingerprint and exact native vtables.
- Require exact Add Member geometry before assigning a password label.
- Accept Set Password indexes only when the complete native ownership chain and both selection endpoints agree.
- False positives are worse than silence.
- Preserve the user-owned untracked route-recorder handoff.

---

### Task 1: Add failing tracker behavior tests

**Files:**
- Modify: `tests/pol_prelogin_semantics_tests.cpp`
- Modify: `tests/pol_pml_selected_text_tests.cpp`
- Modify: `tools/test_pol_native_selected_text_integration.ps1`

**Interfaces:**
- Consumes: `NativeTextFieldSnapshot`, `NativePulldownSelectionSnapshot`, `masked_focus_speech`, and `masked_delta_speech`.
- Produces: focused tests that fail while password wrappers are discarded and Set Password changes are not polled.

- [ ] **Step 1: Write the failing tests**

Add literal expectations for:

```cpp
"Member Password, empty"
"Member Password, 6 characters entered"
"Set Password, Not set"
"Set Password, Save"
```

Use native fake-memory fixtures whose password character-storage ranges are
forbidden. Add a production-facing tracker transition API whose tests prove
unchanged state is silent and changed state requests speech.

- [ ] **Step 2: Run the focused tests to verify RED**

Run:

```powershell
cmake --build build --config Release --target pol_prelogin_semantics_tests pol_pml_selected_text_tests
.\build\Release\pol_prelogin_semantics_tests.exe
.\build\Release\pol_pml_selected_text_tests.exe
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_selected_text_integration.ps1
```

Expected: at least one behavior test fails because the tracker API or
integration is absent.

### Task 2: Restore password focus and edit feedback

**Files:**
- Modify: `src/pol_accessibility/prelogin_semantics.h`
- Modify: `src/pol_accessibility/prelogin_semantics.cpp`
- Modify: `src/accessxi_pol.cpp`

**Interfaces:**
- Consumes: exact password snapshots and geometry-owned labels.
- Produces: a retained masked-field tracker that speaks focus once and count deltas thereafter.

- [ ] **Step 1: Implement the minimal tracker transition logic**

The transition must distinguish first focus, unchanged state, changed state,
and invalid state without inspecting secret text.

- [ ] **Step 2: Seed the tracker from the labeled wrapper**

In `process_current_child_candidate`, use the exact password snapshot plus the
verified Add Member geometry label. Speak `masked_focus_speech(label, count)`
and retain the decoded field pointer. Do not assign a label to an inner field
whose geometry is absent.

- [ ] **Step 3: Poll the retained field**

Replace the ineffective `CPolWinApp + 0x164` lookup in
`poll_masked_field_state` with a safe reread of the already-verified retained
field. Clear on mismatch or known form/surface exit.

- [ ] **Step 4: Run focused tests to verify GREEN**

Run the commands from Task 1. Expected: all pass.

### Task 3: Announce live Set Password choice changes

**Files:**
- Modify: `src/pol_accessibility/prelogin_semantics.h`
- Modify: `src/pol_accessibility/prelogin_semantics.cpp`
- Modify: `src/accessxi_pol.cpp`

**Interfaces:**
- Consumes: exact `CPulldown` live-highlight and committed-selection
  snapshots, plus the verified index map.
- Produces: a retained Set Password tracker that speaks only native row
  changes.

- [ ] **Step 1: Retain exact focus state**

When the geometry-owned Set Password pulldown matches, speak its current
committed value and retain its object pointer and index.

- [ ] **Step 2: Poll the native live highlight**

Reread the retained `CPulldown -> CComboBoxList -> CList` ownership chain each
worker iteration. While the list is open, read the Ghidra-proven signed
16-bit highlight cursor at `CList + 0x21A`; after it closes, fall back to the
separately validated committed selection model. Speak only when the accepted
index changes. Clear on mismatch, invalid index, known focus departure, form
exit, or post-login transition. Never infer a row from Up/Down input.

- [ ] **Step 3: Run focused and full offline tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_pol_native_asi.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_pol_native_offline.ps1
git diff --check
```

Expected: build succeeds, all CTests and integration contracts pass, and the
diff has no whitespace errors.

### Task 4: Deploy and verify the installed client

**Files:**
- Deploy: `build\Release\accessxi_pol_native.asi`
- Deploy: `build\Release\accessxi_pol_nvda.dll`
- Deploy: Prism runtime dependencies through the existing deployment script

**Interfaces:**
- Consumes: verified Release artifacts.
- Produces: installed Add Member behavior and matching staged/installed hashes.

- [ ] **Step 1: Deploy with the existing elevated script**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\deploy_pol_native_asi.ps1
```

- [ ] **Step 2: Verify installed hashes**

Compare every staged native artifact against its installed counterpart and
verify the unchanged Square Enix `pol.exe` and `app.dll` fingerprints.

- [ ] **Step 3: Run a live Add Member pass**

Verify:

- Set Password focus speaks its current value;
- changing between Not set and Save speaks immediately;
- all three password fields speak their exact label and safe count;
- count feedback continues while the software keyboard is open;
- no password contents or diagnostic probe text reaches speech.

- [ ] **Step 4: Commit and push**

Stage only the intended source, tests, tools, and documentation. Leave
`ACCESSXI_HANDOFF_2026-07-12_ROUTE_RECORDER.md` untracked. Commit and push the
existing private branch, then compare the remote branch hash to local `HEAD`.
