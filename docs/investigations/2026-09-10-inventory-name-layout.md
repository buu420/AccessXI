# September 2026 inventory name regression

After the September 10 FFXI update, inventory still supplied selected item IDs,
container slots, cursor rows and counts, but `GetSelectedItemName()` was empty.
The generic menu entry label/help fields were also zero in working pre-update
inventory sessions, so changing those fields would not address this failure.

The native selected-name pointer moved from `0xCC8` to `0x14C8`. The ID field
remains at `0xB0`; Ashita's name and ID chains share their first three offsets
(`0`, `0xC`, `0x1C`). Two independent x86 instruction signatures each occur
exactly once in both unpacked client images:

| Reader | Signature | Displacement | Old image VA | Updated image VA |
| --- | --- | --- | --- | --- |
| Native name getter | `8B410485C07501C38B80????????C3` | +10 | `10230230` | `102306D0` |
| Formatting caller | `8B86????????85C0741B0FBF4C2414556A005083C114` | +2 | `1013EDC3` | `1013EE93` |

The getter dereferences `[this+4]`, returns zero when absent, then loads the
pointer at the displaced field. Ghidra 12.1.2 decompilation of the updated
client confirms that operation and the `0x14C8` field. Its callers corroborate
the same change. Updated unpacked image SHA256:
`e47ddc426b1c84b643732e615390507c75e56da46c1afd8c4794b238f84a752a`.
No game binaries are distributed with this investigation.

Ashita 4.3.0.2 reads each selected-name offset from its offset manager on every
call: the name reader at preferred VA `1016EA40` calls cache lookup `10174C80`
for `inventory.selecteditem` / `name.offset4` at `1016EABB`, then follows the
chain. The SDK exposes `IOffsetManager:Add` as an update to this runtime cache.
AccessXI uses that API once during startup, without writing configuration files
or game memory. Both signatures must be unique and agree on one of the two
reviewed layouts. Unknown current offsets are preserved. Lookup, write and
read-back errors are contained and logged.

Official Ashita main at
[`2e4b9c86de538ecfedabab918537c550d6378aaa`](https://github.com/AshitaXI/Ashita-v4beta/tree/2e4b9c86de538ecfedabab918537c550d6378aaa)
contains core 4.3.1.2 and Addons 4.20. The latest published tag is behind that
binary. The official offsets file still specifies `name.offset4=0xCC8`; updating
Ashita alone does not supply this correction. The AccessXI installer includes
the updated official runtime while retaining AccessXI's existing startup and
library compatibility changes.

`tools/test_inventory_name_layout.lua` exercises the real inventory reader with
a native-memory boundary fixture: the stale-offset failure, restored names,
cursor changes, older clients, duplicate/missing/disagreeing signatures,
unreviewed layouts, custom offsets, and cache/scanner failures. It deliberately
does not replace missing native labels with resource names. Runtime acceptance
still requires opening inventory after loading the new reader and checking
the visible selection against the spoken label and diagnostic log.
