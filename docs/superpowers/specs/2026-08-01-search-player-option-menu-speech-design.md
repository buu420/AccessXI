# Search Player Option Menu Speech Design

## Goal

Make the player-action popup opened from a `/sea` result speak the currently
selected action on every character, while remaining silent when the native row
cannot be verified.

## Verified Native Contract

- The live popup is `menu    scoption`.
- The live object stores the actual one-based cursor at `object + 0x4C` and the
  selected entry pointer at `object + 0x08`.
- The selected entry stores its native, localized help string pointer at
  `entry + 0x40`.
- Live captures correlated cursor and entry changes for rows 1, 2, and 4. The
  game skipped disabled rows 3 and 5 rather than exposing them as selectable.
- Ghidra decompilation of `FFXiMain.unpacked.dll` proves that
  `FUN_1020C0F0` assigns conditional native resource strings to the same menu
  row numbers that `FUN_1020C550` dispatches. The row set therefore changes
  with party, request, and target state.
- Square Enix's September 2015 update notes independently document the
  conditional search submenu actions. They are corroborating context, not a
  source for hardcoded runtime rows:
  <https://forum.square-enix.com/ffxi/archive/index.php/t-48564.html>

## Design

Add a focused resolver module that accepts the menu name, selected cursor,
selected entry, and memory-reader callbacks. It returns text only when all of
these conditions hold:

1. the menu name is exactly `menu    scoption`;
2. the cursor is a positive native row number;
3. the selected entry is a valid process pointer;
4. `entry + 0x40` contains a valid process pointer; and
5. the referenced native string survives the existing menu-text sanitizer.

The main dispatcher will force this menu's selection from `object + 0x4C`, as
the generic query resolver incorrectly treats unrelated `8` fields as a row
count. It will pass the current entry from `object + 0x08` to the resolver,
announce the returned native text, and key speech by menu, cursor, entry, and
text. It will not use a fixed row count, character name, player name, action
table, or inferred label.

The internal fixed title `Search` only admits `menu    scoption` to the known
native-menu dispatcher. The spoken result is the native action help itself;
the synthetic title is not prefixed.

## Failure Behavior

Invalid pointers, empty native strings, unexpected menu names, and nonpositive
cursors return no speech. Disabled rows remain governed by the game and are
never invented by AccessXI.

## Verification

- A Lua 5.1 behavioral test uses literal fixtures captured from the live menu
  to verify row 1, row 2, and row 4 native text resolution.
- The same test verifies silence for unsupported menus, invalid entries,
  invalid help pointers, empty text, and nonpositive cursors.
- The Lua 5.1 syntax wrapper validates the complete addon.
- The changed files are copied into the live Ashita addon, reloaded, and
  verified from `ffxi-menu-reader.log` while moving through the open popup.

