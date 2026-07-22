# PlayOnline Pre-Login Structured Capture Design

Date: 2026-07-22

## Objective

Extend AccessXI's native PlayOnline capture across the pre-login flow and use that evidence to repair inaccessible or incorrect speech without guessing from nearby memory. The immediate priorities are:

1. speak the actual highlighted PlayOnline member name instead of unrelated name-like strings;
2. capture enough native state to repair the remaining pre-login screens with the same evidence-first workflow used post-login;
3. expose the masked state of password and one-time-password fields without exposing their underlying contents; and
4. preserve the working post-login reader and stock PlayOnline binaries.

## Confirmed User Experience

- Highlighting the member entry usually speaks `Rich` or another unrelated value rather than the visible member name.
- The remaining pre-login screens contain controls that are silent or read incorrectly.
- Password and one-time-password controls visibly show stars. AccessXI should provide equivalent feedback by speaking `star` for an accepted character and, when the field receives focus, announcing its label plus either `empty` or the number of masked characters entered.
- The user will perform a continuous walkthrough after deployment; the capture must not require repeated confirmations between screens.

## Existing Evidence

- The current native Prism path works without Reloaded-II.
- Ghidra-backed focus, current-child, selected-index, and indexed-child paths already provide stable native event boundaries.
- The current member-name filter proves only that text looks like a plausible name. It does not prove that the text belongs to the highlighted member row.
- Startup member recovery currently consults linked model fields and a global accessor after seeing a Member List focus shape. Nearby strings such as `Rich` can pass the lexical name filter even when they do not belong to the selected row.
- Live logs have shown a dynamic `Rich` candidate near a separate static `Member List` event, as well as internal or resource strings in broad probe output. This makes arbitrary pointer scanning unsafe as a speech source.
- The existing post-login capture has a bounded in-memory queue, worker-thread serialization, source-tagged text candidates, opt-in activation, and stable PML event hooks that can be extended instead of creating another independent hook stack.
- The crash-prone PML text-setter hook remains disabled and is not required for this design.

## Root Cause

The pre-login reader currently conflates lexical plausibility with object ownership. A string can be short, printable, and shaped like a member name while still coming from an unrelated object or stale global value. Focus on the Member List container does not prove that such a string is the value of its selected member row.

The fix must establish a native relationship chain:

```text
focused member-list control -> selected index -> indexed selected child -> child-owned visible value
```

Only a value recovered through that chain may be spoken as the selected member name. A plausible string found elsewhere is diagnostic evidence, not accessible output.

## Approaches Considered

### Selected: role-aware structured capture and relationship-backed speech

Extend the existing stable-event snapshot pipeline to classify native controls and preserve parent, manager, selection, and child relationships. Speech is authorized by the control role and relationship proof, not merely by a string filter. This requires more careful native analysis but prevents unrelated strings from becoming user-facing output and generalizes to other pre-login screens.

### Re-score broad memory candidates

The existing probe could assign higher scores to strings near known rectangles or member-list objects. This would be quick, but it cannot prove ownership and would continue allowing convincing false positives. It is rejected for speech.

### OCR or global drawing capture

OCR or a global text-render hook could recover some visible strings but would lose native focus, selection, and control-role semantics. It would also increase noise and make secret-field handling riskier. It remains a last-resort diagnostic comparison, not the primary reader.

## Architecture

### Unified PlayOnline capture session

Generalize the current opt-in post-login trace into a PlayOnline UI capture that may start on pre-login or post-login screens. `Ctrl+Shift+F10` remains the explicit start/stop control. Capture stops automatically when `FFXiMain.dll` loads.

The existing hook callbacks continue to copy bounded snapshots into an in-memory queue. File serialization stays on the native worker thread so focus and selection callbacks do not perform disk I/O or Prism calls.

Each snapshot records only bounded, safely copied fields:

- sequence and timestamp;
- screen phase and native event kind;
- manager, parent, focused object, requested child, current child, selected index, and resolved selected child identities;
- object vtable RVA, verified rectangle, and resource identifier when available;
- inferred control role and the evidence used for that role;
- source-tagged sanitized text candidates; and
- the final trust decision and rejection reason.

The trace remains local under `%USERPROFILE%\AccessXI\logs`. The schema is versioned and records the recognized `app.dll` fingerprint.

### Control-role resolver

Introduce a small resolver that classifies only evidence-backed roles:

- member-list container;
- selected member row;
- ordinary list row;
- button or command;
- static label or image caption;
- editable value field; and
- masked password or one-time-password field.

Role evidence may come from verified native resource identifiers, vtable identity, rectangles within a proven screen context, and parent/selected-child relationships. No role may be inferred from row order alone. Unknown objects remain `unknown` and are captured silently.

### Trusted speech resolver

The resolver evaluates candidates in this order:

1. selected-child text with a proven container/index/child relationship;
2. direct focused-control text from a verified native getter;
3. verified static resource or geometry label within a proven screen context;
4. sanitized masked-field state; and
5. no speech.

Broad linked-field and global-accessor results may be retained as tightly bounded diagnostic candidates, but they cannot authorize speech or override a relationship-backed value. The current startup path that promotes a merely name-like value must be removed from user-facing speech.

### Member-name behavior

When the Member List has native focus, AccessXI resolves its selected index through the Ghidra-verified indexed-child helper. It then reads only text owned by that selected child or by a verified value child beneath it. The selected member name is spoken once when the selected child changes or when focus enters the row.

If the relationship cannot be proven, AccessXI does not speak a member name. The trace records why resolution failed so the next live capture can identify the missing native link without substituting another nearby string.

### Masked-field behavior

Masked fields expose state, never content:

- On focus with no masked characters: `Password, empty` or `One-time password, empty`.
- On focus with masked characters: for example, `Password, 6 characters entered`.
- When one accepted input increases the masked length by one: `star`.
- When a single action inserts multiple characters, announce the resulting count rather than repeating many stars.

A masked-state tracker runs only while a control has first been proven to be a password or one-time-password field. It observes the focused control's native displayed length through a Ghidra-verified value path and compares only the sanitized count with the previous count. This makes feedback follow accepted edits rather than raw keypresses: a rejected key produces no announcement, a one-character increase produces `star`, and a larger increase produces the resulting count.

The sanitizer runs before queue insertion. In a proven secret-field context it retains only the field role, empty/non-empty state, and masked character count. Raw field contents are neither copied into snapshots, queued, logged, nor sent to Prism. Diagnostic records use a structured masked-state value and never include the underlying text.

### Remaining pre-login screens

The same capture records focus and selection transitions throughout the user's walkthrough. New speech is enabled only when the trace and Ghidra evidence identify a stable native role and value relationship. Dynamic labels are not hardcoded to the text observed in a single session, and guessed row tables are not introduced.

## Data Flow

```text
native focus/selection/value event
    -> role and relationship proof
    -> secret-field sanitizer when applicable
    -> bounded sanitized snapshot copied in hook callback
    -> worker-thread trace serialization
    -> role-aware trust resolver
    -> deduplicated Prism speech, or silence with a rejection reason
```

The diagnostic trace never feeds untrusted text directly into Prism. Speech and evidence logging share the same snapshot, but the trust resolver is an explicit gate between them.

## Safety and Error Handling

- Unknown, stale, ambiguous, or relationship-free candidates remain silent.
- Invalid native pointers or failed guarded reads produce a rejection reason rather than a fallback scan.
- Snapshot collection is bounded, duplicate-suppressed, and non-blocking. Queue overflow is summarized by the worker.
- Secret-field sanitization occurs before queue insertion.
- The disabled PML text-setter hook remains disabled.
- No OCR, arbitrary recursive pointer traversal, network upload, or modification of Square Enix binaries is introduced.
- Capture and speech are active only for the recognized PlayOnline `app.dll` build.

## Testing Strategy

### Offline and unit tests

- A plausible unrelated value such as `Rich` near a member-list object must be rejected when it is not owned by the resolved selected child.
- A value owned by the indexed selected child must be accepted and retain its selected-member role.
- Selection changes must update the spoken member exactly once; duplicate native events must not repeat it.
- Unknown objects and failed relationship chains must produce silence plus a diagnostic rejection reason.
- Secret-field tests must prove that raw sample secrets never appear in queued records, trace output, or Prism messages.
- Masked fields must announce `empty`, the correct count on focus, `star` for a one-character increase, and the resulting count for a multi-character increase.
- Pre-login capture activation, stop behavior, queue bounds, escaping, deduplication, and automatic FFXI shutdown must remain deterministic.

### Integration and regression tests

- Build the 32-bit hook DLL and native ASI.
- Run the existing native host, ABI, focus, selected-text, queue, trace, and deployment suites.
- Preserve all working post-login image-caption and selected-row behavior.
- Verify the staged and installed hook hashes match after deployment.
- Verify Square Enix `pol.exe` and `app.dll` are unchanged.

### Live validation

After deployment, the user starts capture before navigating the pre-login flow, visits each affected screen, moves through the member list and other lists one item at a time, exercises empty and masked secret fields with non-sensitive test input, stops capture, and then continues into the already-working post-login flow. AccessXI correlates the trace with native object relationships before enabling any additional uncertain labels.

## Acceptance Criteria

1. The highlighted member speaks its visible member name and never substitutes `Rich` or another unrelated nearby value.
2. Member speech requires the selected container/index/child relationship; lexical name shape alone is insufficient.
3. Password and one-time-password fields announce their label and masked count on focus and speak `star` for each accepted single-character insertion.
4. Raw password and one-time-password contents never appear in logs, queued snapshots, or Prism output.
5. The capture spans the full pre-login and post-login PlayOnline flow and remains explicitly opt-in.
6. Other pre-login controls gain speech only from captured, Ghidra-verified native evidence.
7. Existing post-login speech remains correct, the capture adds no noticeable navigation lag, and PlayOnline remains stable.
8. All offline, integration, build, deployment, hash, and live smoke checks pass before the change is declared complete.
