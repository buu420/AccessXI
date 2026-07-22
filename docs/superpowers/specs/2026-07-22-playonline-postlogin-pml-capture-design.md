# PlayOnline Post-Login PML Capture Design

Date: 2026-07-22

## Objective

Prepare a diagnostic AccessXI native build that can record the real PlayOnline UI state needed to repair two post-login accessibility failures:

1. focusable options that are silent or speak an unrelated label; and
2. a vertically navigated list whose rows do not speak at all.

The diagnostic build will be deployed before the user opens PlayOnline. During one guided login walkthrough it will record bounded, structured evidence from PlayOnline's native PML focus and selection paths. It will not enable new speech from unverified text.

## Confirmed User Workflow

- The target begins after signing into PlayOnline.
- The user will open PlayOnline only after AccessXI reports that the diagnostic build is installed.
- The user will then log in, press `Ctrl+Shift+F10` once to start the post-login capture, and navigate through all affected screens and rows in one pass.
- The capture must not require the user to stop for repeated confirmations.

## Existing Evidence

- The installed native ASI and Prism speech path are already working in stock PlayOnline without Reloaded-II.
- Ghidra proves that post-login resources are converted into native PML components. The server origin of the page does not prevent local capture after PlayOnline parses it.
- The Ghidra-backed focus path emits event code `0x400001` and carries the focused object at event offset `+0x30`.
- The current hook already observes:
  - shared and selection focus events;
  - current-child changes;
  - selected-index changes and the selected child lookup.
- The current speech trust policy is pre-login-specific. `semantic` candidates are accepted only when their text is in the pre-login atlas, so legitimate post-login labels are commonly rejected.
- The previous broad text scan produced junk such as `h5GV`. Therefore arbitrary pointer scanning cannot be promoted to speech.
- The older PML text-setter inline hook is disabled for crash stability and must remain disabled during this capture.

## Root-Cause Hypothesis to Test

The native events identify the correct focused or selected PML object, but the current reader either:

1. finds the correct native label and rejects it because the trust policy only recognizes pre-login labels;
2. reads a help/wrapper string instead of following the proven wrapper-to-component relationship; or
3. receives a selected child whose label is stored in a PML inline string or linked native field that the current strict reader does not record.

The capture must distinguish these cases for every user-driven focus or selected-index transition. No speech fix will be chosen until the trace identifies which case occurs.

## Selected Approach

### Structured event snapshots on already-stable hooks

Add a bounded diagnostic event queue to the hook DLL. Existing hook callbacks will create small snapshots for:

- shared PML focus gain;
- selection PML focus gain;
- current-child changes; and
- selected-index changes.

Each snapshot will contain only values that can be copied safely at the event boundary:

- monotonic sequence and `GetTickCount()` timestamp;
- event kind and event code;
- manager/model, requested child, resolved current/selected child, and focused object pointers;
- manager focus pointers at `+0x160`, `+0x164`, and `+0x1C0` when readable;
- object vtable pointer and vtable RVA relative to `app.dll` when applicable;
- object rectangle when the existing verified rectangle reader succeeds;
- strict PML inline text and strict direct candidates, including their exact source kinds and offsets;
- the current resolver result and whether the existing trust filter accepts it.

The hook callback will enqueue the snapshot in memory. The existing 20 ms native worker will drain and serialize it to a separate log, so the diagnostic path does not add file I/O to the hook callback.

### Separate append-only trace

Write capture records to:

```text
%USERPROFILE%\AccessXI\logs\pol-postlogin-pml-trace.tsv
```

The trace starts with a schema/version record and the already-verified `app.dll` size and FNV-1a fingerprint. Records use escaped UTF-8 tab-separated fields so rows can be parsed without confusing label content with metadata.

Capture is opt-in for each PlayOnline process. The existing 20 ms worker detects a rising edge of `Ctrl+Shift+F10`. The first press starts a new trace session and speaks the fixed AccessXI status message `Post-login capture started`; the next press stops capture and speaks `Post-login capture stopped`. These status messages are authored by AccessXI and contain no captured UI text.

The normal `pol-monitor.log` remains unchanged and continues to show speech decisions. The separate trace is evidence only and never feeds Prism.

### Bounded and deduplicated capture

- Queue capacity: 1024 snapshots.
- Text field limit: 240 UTF-8 bytes per captured candidate.
- Per-object linked-field candidates: only the existing proven field set; no arbitrary recursive pointer walk.
- Duplicate suppression: identical event kind, manager/model, object, index, resolver label, and trust result within 50 ms collapse into one record.
- Queue overflow writes a summarized dropped-record count from the worker; callbacks never block waiting for disk.
- Events before the explicit start hotkey are discarded, preventing login and credential screens from entering the trace.
- Capture stops automatically when `FFXiMain.dll` loads because the trace concerns PlayOnline, not in-game FFXI.

## Candidate Text Boundaries

The capture may record untrusted candidates for diagnosis, but each candidate is tagged with its source. Candidate collection is limited to readers already present and guarded by structured exception handling:

- proven short inline PML thiscall string layout;
- strict native PML object text fields;
- current component semantic resolver output;
- selected child returned by the Ghidra-verified indexed-child helper;
- verified object rectangle and focus relationship fields.

The capture will not:

- re-enable the crash-prone `PmlTextSetterRva` inline hook;
- hook global `DrawTextA` or scrape every rendered string;
- use OCR;
- traverse arbitrary pointer graphs;
- synthesize labels from row order;
- send captured data over the network; or
- speak candidate text merely because it looks readable.

## Privacy and Safety

- Password and one-time-password contexts retain the existing suppression rules.
- The trace remains disabled throughout login and starts only after the user explicitly presses the capture hotkey on the post-login surface.
- Candidate text matching password or one-time-password field context is stored as `<redacted>` even after activation.
- The log contains local object addresses and UI text; it remains under the user's AccessXI log directory.
- Only the recognized `app.dll` build (`4335104` bytes, FNV-1a `07E88E8067FEF6CC`) may install the diagnostic hooks.
- Square Enix binaries are not modified.
- Deployment uses the existing reversible ASI deployment script and preserves the prior installed build.

## Alternatives Considered

### Re-enable the PML text-setter inline hook

Rejected for this capture because the existing source explicitly records that it was disabled for crash stability. Its calling convention and patch boundary can be revisited only after stable-event evidence is exhausted.

### Hook `DrawTextA`

Useful as a later fallback for confirming final visible strings and rectangles, but it loses PML focus, role, and parent/child semantics and may capture unrelated drawing. It is unnecessary until the stable PML events are traced.

### OCR or screenshots as the primary reader

Rejected. OCR can help compare a saved screenshot to a trace, but it cannot be the authoritative runtime source because false positives and missed text are unacceptable.

## Capture Walkthrough

After deployment, the user will:

1. start the normal PlayOnline Viewer;
2. sign in;
3. press `Ctrl+Shift+F10` and wait for `Post-login capture started`;
4. pause briefly on the first post-login screen;
5. move through every option that currently reads incorrectly;
6. enter the silent vertical list and move one row at a time from top to bottom and back up;
7. visit the remaining affected post-login screens;
8. press `Ctrl+Shift+F10` and wait for `Post-login capture stopped`; and
9. close PlayOnline or launch FFXI.

AccessXI will then correlate the trace by sequence and object identity, verify the native label path in Ghidra, and design the smallest speech fix supported by the live evidence.

## Acceptance Criteria for the Diagnostic Build

1. Offline tests prove opt-in session gating, queue bounds, FIFO ordering, duplicate suppression, escaping, truncation, and overflow reporting.
2. Source guards prove the disabled PML text-setter hook remains disabled and diagnostic records never call the speech sink.
3. The 32-bit hook DLL and native ASI build successfully.
4. Existing native host, speech worker, queue, ABI, focus, structure, and deployment tests remain green.
5. The staged and installed hook hashes match.
6. A launch smoke test shows the schema header and recognized `app.dll` fingerprint without hook-install or Prism errors.
7. No claim about repaired post-login speech is made until the user's live walkthrough has been analyzed.
