# PlayOnline Popup and Notice Speech Design

Date: 2026-07-26

## Objective

Speak player-facing text that PlayOnline displays outside the currently focused
control:

1. the body sentence of confirmation and warning dialogs, before or alongside
   their focused buttons; and
2. transient notice text, such as a friend coming online, even when the notice
   does not take keyboard focus.

The feature must communicate only text that a sighted player can see. Unknown
objects, malformed state, secret fields, and unsupported PlayOnline builds stay
silent.

## Confirmed User Behavior

- Clicking an action such as Exit should announce the confirmation sentence,
  not only `Yes` or `No`.
- Notices that appear while a page or game is loading should be noticed even
  when focus remains somewhere else.
- The solution must be automatic. The user should not have to start a capture
  session or review a diagnostic trace for ordinary use.
- Existing focused-control speech remains available.

## Root Cause

The current accessibility bridge follows PlayOnline's focus, current-child, and
selected-index events. That correctly announces buttons and menu rows, but a
dialog's body is a sibling label owned by the modal window, not the focused
button. Likewise, a transient notice can update a persistent window without
emitting a focus event.

Live logs confirm this separation: selecting Exit announces `Yes` and `No`, but
not the sentence in the modal body. Ghidra confirms that each supported modal
class stores its body in one exact `CLabel*` member and that the two notice
classes own fixed text components.

## Ghidra-Verified Native Ownership

All addresses below are RVAs for the installed, fingerprint-gated `app.dll`.

### Visible `CLabel` text

- `CLabel` vtable: `0x003300A4`
- UTF-16 buffer begin: `CLabel + 0x184`
- UTF-16 buffer allocation end: `CLabel + 0x188`
- visible character count: `CLabel + 0x21A`
- native setter: `0x00066BCD`
- native effective-visibility state: both bits `0x0C` at component `+0x18`

The setter writes exactly `length` UTF-16 characters followed by a terminator.
The reader can therefore require the proven vtable, a positive bounded length,
an allocation large enough for `length + 1`, a terminating null, valid UTF-16,
and visible non-control content.

### System modal owners

| Owner class | Owner vtable RVA | Constructor RVA | Body `CLabel*` field |
| --- | ---: | ---: | ---: |
| `CASysModalWarning_M_Ok` | `0x00368CA4` | `0x000D1842` | `+0x2B8` |
| `CASysModalWarning_M_YN` | `0x00368EFC` | `0x000D1B45` | `+0x2BC` |
| `CASysModalWarning_M_YNC` | `0x00369154` | `0x000D1E5E` | `+0x2C0` |
| `CASysModalWarning_M_OkC` | `0x00369CF4` | `0x000D2B16` | `+0x2BC` |
| `CASysModalWarning_M_RF` | `0x0036A1A4` | `0x000D32FB` | `+0x2BC` |

Each body field is created by the proven `CLabel` factory. Adjacent fields are
buttons or panel state and are not eligible as body text.

These are base classes, not final runtime owners. Ghidra call references and
decompilation prove that direct derived constructors replace the base vtable
while retaining the inherited label fields:

| Base kind | Exact directly derived owner vtable RVAs |
| --- | --- |
| M_Ok | `0x00323D24`, `0x00336434`, `0x0033829C`, `0x003C816C`, `0x003CA074`, `0x003CA2D4`, `0x003CB0F4`, `0x003D492C`, `0x003E7F54` |
| M_YN | `0x00322394`, `0x00338524`, `0x003D3F54`, `0x003DCBC4`, `0x003E2A9C`, `0x003E81BC` |
| M_YNC | `0x003283D4`, `0x003387A4`, `0x003E8424` |
| M_OkC | `0x003E868C` |
| M_RF | `0x00324744`, `0x003CA534` |

Every derived destructor reaches the same Ghidra-proven non-deleting base
destructor. Exact base-destructor RVAs, in the same row order, are
`0x000BD4F0`, `0x000BD55E`, `0x000BD5CC`, `0x000BDA4E`, and `0x000BDB2A`.

### Notice owners

- `CNotice_Window`
  - vtable `0x0033FCDC`
  - constructor `0x000A6485`
  - directly derived vtables `0x003CE96C` and `0x003CF074`
  - shared base destructor `0x000A6668`
  - exact `CLabel*` fields `+0x2A8`, `+0x2AC`, and `+0x2B0`
- `CNotice_Important_Wnd`
  - primary vtable `0x0034069C`
  - constructor `0x000A9CCB`
  - directly derived vtable `0x003CF2CC`
  - shared base destructor `0x000A6AC0`
  - exact `CLabel*` fields `+0x2AC` and `+0x2B0`
  - an additional rich text component at `+0x2B4` remains unsupported until
    its own exact text representation is proven

The implementation may speak only the fields whose child type, effective
visibility, and storage are proven. It must not recursively search neighboring
pointers to compensate for the unsupported rich component.

## Selected Architecture

### Exact owner registry

Install base-constructor hooks only for the fingerprinted `app.dll` build.
Each hook calls its original constructor first, then publishes the completed
base-owner pointer into one of 32 bounded live slots for its kind. Each slot
packs a 32-bit pointer and monotonically increasing 32-bit generation into one
aligned lock-free atomic value. A second live popup never replaces the first,
and a worker cannot pair a new pointer with an older generation. Capacity
exhaustion fails silent. The callback does not read text, call Prism, write a
log, allocate a container, or traverse an object tree.

Each original-function trampoline is also release-published before its
constructor entry is replaced with a jump. A callback therefore cannot observe
a null trampoline after the patched entry becomes callable. Other process
threads are suspended for the bounded seven-byte patch, and installation is
retried if any thread is already executing those entry bytes.

Each shared non-deleting base destructor is inline-hooked at its
Ghidra-proven complete instruction boundary. This catches every derived
vtable, atomically invalidates all matching live slots before native
destruction begins, then calls the original base destructor. Constructor
patching does not begin until all seven base-destructor hooks are installed,
so no published owner can outlive its invalidation coverage.

The existing 20 ms worker consumes every live registry slot. It validates the
owner against the exact base-or-directly-derived vtable set and native
effective-visibility bits on every poll, follows only the inherited fixed
member offsets for that registered kind, validates each child as a visible
`CLabel`, and reads its bounded visible text. Each live owner has independent
stability and deduplication state. An unreadable, hidden, or changed owner or
child clears only that owner's observation and produces no speech.

### Stable text and deduplication

Native UI code can populate a label shortly after its owner constructor
returns. A candidate must therefore be identical on two worker polls before it
is eligible for speech. This avoids partial or intermediate strings.

Deduplication is keyed by owner kind, constructor generation, label slot, and
text:

- the first stable nonempty body for a new modal generation is spoken;
- an unchanged label is not repeated on subsequent polls;
- a changed notice label is spoken once without requiring focus;
- the same text is eligible again when a new owner generation is published;
- unknown or malformed reads preserve deduplication and produce no speech;
- one confirmed absent poll cannot make unchanged text repeat; and
- two confirmed absent polls clear the slot so a later reappearance is a real
  event.

Modal body text uses interrupting speech because it explains the focused
decision. Notice text uses queued/non-interrupting speech so it is noticed
without repeatedly cutting off menu navigation.

### Speech order

The worker resolves modal body text before draining ordinary queued focus
speech in the same iteration. A focus event that PlayOnline emits immediately
inside the dialog construction path can still announce its button first; the
stable body then interrupts it so the missing decision context is not lost.
Existing focus speech is never suppressed when the modal body is empty,
hidden, or invalid.

## Text and Privacy Boundaries

Eligible text must:

- come from an exact owner field and an exact `CLabel` instance;
- contain 1 to 512 UTF-16 code units plus a terminator inside the native
  allocation;
- be valid UTF-16 with no embedded nulls or control characters other than
  normalized whitespace;
- contain at least one visible non-whitespace character; and
- not contain PML resource markers, local resource paths, or URLs.

The feature remains disabled once `FFXiMain.dll` loads. It never inspects
password controls, one-time-password controls, edit fields, arbitrary PML
trees, global draw calls, or pixels. The existing `PmlTextSetterRva` hook stays
disabled.

## Failure Behavior

- Unknown `app.dll` fingerprint: install no popup hooks.
- Unsupported owner or mismatched base/derived owner vtable: silence.
- More than 32 simultaneously live owners of one kind: leave the excess owner
  unregistered and silent.
- Null, unreadable, mismatched, malformed, or overlong child label: silence.
- A transient unknown read: preserve prior deduplication; never reinterpret it
  as disappearance.
- Multiple distinct candidate strings in one modal body slot: wait for
  stability; never guess.
- Notice rich component not yet proven: leave it silent while still announcing
  independently proven labels.
- Hook installation failure: retry incomplete base-destructor hooks before any
  constructor patching begins. Once every destructor is covered, keep every
  successfully installed constructor tracked by its non-null trampoline, log
  any constructor failure, and retry only the remaining fingerprint- and
  prologue-validated constructors. Never reject an entry merely because this
  feature already replaced it with its own jump.

## Validation

Offline tests cover every Ghidra-proven directly derived owner vtable,
inherited owner/slot relationships, multiple simultaneous live owners, strict
`CLabel` parsing, malformed memory, tri-state absence versus unknown reads,
stability, deduplication, text changes without focus, new and invalidated
owner generations, concurrent pointer/generation publication, and
modal-versus-notice interrupt policy.

PowerShell integration checks ensure:

- all hooks are exact-build gated;
- callbacks only call their trampoline and publish the owner;
- worker-side code performs text reads and speech;
- popup processing runs before ordinary focus speech;
- `PmlTextSetterRva` remains disabled; and
- popup state resets when FFXI loads.

After build and deployment verification, the first live check is the reversible
Exit confirmation: the body sentence must speak once, although PlayOnline can
focus and announce `Yes` or `No` just before the worker's two-poll-stable body
interrupt. A subsequent real transient notice validates the no-focus update
path.
