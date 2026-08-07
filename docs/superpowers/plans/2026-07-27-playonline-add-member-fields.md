# PlayOnline Add Member Native Fields Implementation Plan

**Goal:** Expose Set Password's native selected value, retained ordinary field
values, and safe password counts throughout the Add Member form.

**Architecture:** Read Set Password through its exact native
`CPulldown`/list/selection-model ownership chain, add a bounded native
text-field reader for the verified `CScrollTextField`, `CTextField`, and
`CPasswordField` object graphs, and compose those values with the existing Add
Member geometry labels at focus time.

**Tech stack:** C++20, Win32 x86, Ghidra-backed object layouts, CMake/CTest,
PowerShell deployment guards, Prism speech.

## Constraints

- Never copy or log password text; only a verified count may leave the reader.
- Do not infer select choices from row position.
- Do not scan unrelated objects or global PML text.
- Preserve all existing pre-login, post-login, popup, and member-name behavior.
- Keep the handoff file untracked.

### Task 1: Lock the behavior with failing tests

**Files:**

- Modify: `tests/pol_pml_selected_text_tests.cpp`
- Create: `tests/pol_pml_text_field_tests.cpp`
- Modify: `tests/pol_prelogin_semantics_tests.cpp`
- Modify: `CMakeLists.txt`

1. Add a selection test proving that only the exact pulldown/list/model
   ownership chain yields a single native Set Password index.
2. Add field-reader tests for inline and heap normal values, empty values,
   exact wrappers, malformed state, wrong vtables, and password count-only
   output.
3. Add speech-composition tests for labeled ordinary, selected, and secret
   values.
4. Build the focused targets and verify they fail before implementation.

### Task 2: Implement exact native readers

**Files:**

- Modify: `src/pol_pml/native_selected_text.h`
- Modify: `src/pol_pml/native_selected_text.cpp`
- Create: `src/pol_pml/native_text_field.h`
- Create: `src/pol_pml/native_text_field.cpp`

1. Resolve the exact `CPulldown` through its `CList`, `CComboBoxList`, and
   `CDefaultListSelectionModel`.
2. Resolve only exact direct fields or exact wrapper-owned inner fields.
3. Validate the field's model pointer and exact model vtable.
4. Decode normal native strings within fixed bounds and require their native
   ETX sentinel.
5. Return only a bounded logical count for password models.
6. Run the focused unit tests to green.

### Task 3: Integrate Add Member focus speech

**Files:**

- Modify: `src/pol_accessibility/prelogin_semantics.h`
- Modify: `src/pol_accessibility/prelogin_semantics.cpp`
- Modify: `src/accessxi_pol.cpp`
- Modify: the relevant PowerShell integration guard

1. Add pure helpers that compose `label, value`, `label, empty`, and
   label-specific secret counts.
2. Resolve the Add Member geometry label first, then accept a value only from
   the exact currently focused native control.
3. Compose `Set Password` with its exact native single-selection value.
4. Replace the stale masked-model constants with the exact reader.
5. Keep insertion feedback driven by changes in the verified native count.

### Task 4: Verify and deploy

1. Run all CTest and PowerShell offline/integration suites.
2. Build the Win32 release and stage the installer payload.
3. Deploy to the shared PlayOnline installation.
4. Verify staged/installed hashes and unchanged Square Enix binaries.
5. Launch PlayOnline and validate Add Member focus and Set Password behavior
   from live speech/log evidence.
6. Commit the intentional files and push the existing private branch.
