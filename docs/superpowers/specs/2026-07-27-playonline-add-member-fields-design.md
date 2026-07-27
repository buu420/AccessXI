# PlayOnline Add Member Native Field Accessibility Design

Date: 2026-07-27

## Objective

Make the PlayOnline Add Member form behave like an accessible native form:

- `Set Password` announces its current visible choice so the user can select
  `Save` and reveal the PlayOnline Password field.
- Returning to an ordinary text field announces the value retained by
  PlayOnline.
- Password fields announce only `empty` or the number of characters entered.
- The implementation remains shared across members and characters.

## Confirmed Native Evidence

The recognized `app.dll` uses these exact native types:

- `CLoginRegistryFrame`, vtable RVA `0x003CD564`, is the exact Add Member
  owner.
- `CScrollTextField`, vtable RVA `0x003327F4`, owns its exact inner
  `CTextField` or `CPasswordField` at offset `0x228`.
- `CTextField`, vtable RVA `0x00333A94`, owns a normal text model through the
  matching active/owned model links at offsets `0x1BC` and `0x1E8`.
- The normal text model has vtable RVA `0x00333F7C` and stores a bounded
  `std::basic_string<wchar_t>` at model offset `0x30`. Its final logical code
  unit is the native ETX sentinel `U+0003`; the sighted field value ends just
  before it.
- `CPasswordField`, vtable RVA `0x00333CD4`, owns a password model with vtable
  RVA `0x0033400C`.
- Both model classes expose their visible logical length through virtual slot
  `+0x30`, whose implementation is RVA `0x00079061`.
- `CPulldown`, vtable RVA `0x0032F0EC`, owns a `CList` at `+0x1DC` and a
  `CComboBoxList` at `+0x1E0`; both converge on that same list, whose exact
  `CDefaultListSelectionModel` at `+0x210` supplies Set Password's current
  native selection.

The previous password-model vtable and length-getter constants do not describe
the current recognized `app.dll`, so the masked-state reader fails closed.

## Selected Design

Add a small native-field reader with a pure, bounded memory interface. It
accepts only the exact field or wrapper vtables listed above, verifies the
field-to-model relationship, and then returns one of:

- an ordinary retained UTF-16 value;
- a secret character count with no text; or
- no result when any relationship is missing, malformed, or ambiguous.

Normal text uses the native string's length/capacity and inline-or-heap storage
rules, requires the exact ETX model sentinel and trailing terminator, enforces a
small maximum, and rejects control characters or invalid UTF-16. Password
handling reads only the verified logical length. It never reads, copies,
queues, logs, or speaks the password buffer.

Read Set Password through the exact pulldown/list/selection-model ownership
chain. The only accepted single-selection indices map to the two native rows
confirmed in the Add Member constructor: `0` is `Not set` and `1` is `Save`.
Any ownership mismatch, split selection, or other index stays silent.

The Add Member speech path combines a verified geometry label with the exact
native value:

- `Set Password, Save`
- `Member Name, Example`
- `PlayOnline ID, ABCD1234`
- `Member Password, 6 characters entered`
- `Confirm Password, empty`

Unknown controls, unsupported derived types, invalid strings, and mismatched
models remain silent.

## Safety Boundaries

- No OCR, global PML scans, neighbor scans, guessed row tables, or character-
  specific state.
- Never dereference or copy password character storage.
- Require the recognized `app.dll` fingerprint and exact vtables.
- Require the exact wrapper-to-inner and field-to-model links when wrappers are
  involved.
- Bound every pointer addition, string length, capacity, and UTF-16 copy.
- Keep the Square Enix executables and DLLs unchanged.

## Verification

Unit tests cover exact pulldown selection, normal inline and heap strings,
wrapper ownership, the ETX sentinel, malformed strings, mismatched
vtables/models, exact pulldown ownership, and proof that secret snapshots
contain only a count. Integration guards must reject the stale password
constants, require the exact field reader, and preserve the conditional
PlayOnline Password geometry. The full Win32 test suite, deployment hash
checks, and a live Add Member smoke pass must succeed before completion.
