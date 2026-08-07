# PlayOnline Add Member Password Feedback Regression Design

## Goal

Restore complete, safe speech on the PlayOnline Add Member form:

- speak the exact visible label and empty/character-count state for every
  password field;
- announce the live native choice when the visible `Set Password` control
  changes between `Not set` and `Save`;
- never read or copy password character storage;
- remain silent when the native owner, field type, geometry, or selection is
  ambiguous.

## Verified evidence

The installed PlayOnline Viewer visibly labels the control `Set Password` and
shows exactly two choices, `Not set` and `Save`. Square Enix's official setup
instructions use the same label and values.

The live current-child trace shows that opening the control moves focus into a
native 115-by-48 list that produces no label. The closed `CPulldown` exposes
its committed selection through:

`CPulldown -> CComboBoxList -> CList -> CDefaultListSelectionModel`

Ghidra proves that the committed selection model does not change while the
player arrows through the open list. `CList` instead stores the live,
keyboard-highlighted row as a signed 16-bit value at `+0x21A`; Enter later
copies that row into the selection model. The previous poll therefore remained
on the old committed value until selection closed.

The password regression was introduced when the current-child handler began
returning for both the inner `CPasswordField` and its labeled wrapper. The
worker poll was expected to replace that speech. A live elevated probe proves
that `app.dll + 0x4E13C8` resolves to `CPolWinApp`, not a focused password
control, and its `+0x164` value is null. The poll therefore cannot produce a
label or count.

## Design

### Password fields

When the exact current-child decoder resolves a password wrapper and its
Add Member geometry identifies `PlayOnline Password`, `Member Password`, or
`Confirm Password`, the handler will:

1. compose `Label, empty` or `Label, N characters entered`;
2. retain only the verified wrapper/field pointer, label, role, and count;
3. poll that retained exact native field while PlayOnline's software keyboard
   owns UI focus;
4. announce only count deltas;
5. clear the tracker when another verified form control receives focus, the
   field stops matching, the form closes, or the post-login surface begins.

An unlabeled inner `CPasswordField` event remains silent. Password text is
never copied; the existing decoder reads only the model's logical length after
validating the password vtable, owned model, length getter, and 32-star mask
template.

### Set Password choices

When the exact Add Member `Set Password` `CPulldown` receives focus, the
handler speaks its current committed selection and retains the verified
pulldown pointer and index. The worker validates the exact
`CPulldown -> CComboBoxList -> CList` ownership chain, then reads the live
`CList + 0x21A` cursor while the menu is open. Once the cursor returns to
`-1` after close, it falls back to the separately validated committed
selection model. It announces only a changed accepted index and never tries
to label the transient list object.

The only accepted indexes remain:

- `0` -> `Not set`
- `1` -> `Save`

Any other index or broken ownership chain clears the tracker and stays silent.

## Testing

Tests must fail against the regressed build before implementation. They will
exercise state transitions using real native decoder fixtures:

- labeled password wrapper focus returns safe count speech;
- unlabeled inner password objects remain silent;
- a retained password field reports count changes while a transient overlay
  owns UI focus;
- a retained `Set Password` pulldown reports its live highlighted row even
  while the committed selection model still contains the previous value;
- unchanged indexes/counts remain silent;
- invalid pointers, vtables, ownership, selection endpoints, or password mask
  templates remain silent;
- password character storage is marked forbidden and must never be read.

The full native CTest suite, PowerShell integration contracts, installed-file
hash comparison, and a final live Add Member pass are required before
deployment is considered complete.
