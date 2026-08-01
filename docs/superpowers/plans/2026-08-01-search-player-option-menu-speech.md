# Search Player Option Menu Speech Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Speak the current native action in the conditional player popup opened from a `/sea` result.

**Architecture:** A small pure Lua resolver reads only the proven selected-entry help pointer. The existing native-menu dispatcher supplies the exact `+0x4C` cursor and `+0x08` entry, owns speech state, and stays silent on ambiguous data.

**Tech Stack:** Lua 5.1, Ashita v4 memory APIs, PowerShell test wrapper, local Ghidra 12.0.4 evidence.

## Global Constraints

- Do not hardcode menu rows, player names, character names, or a fixed row count.
- False positives are worse than silence.
- Preserve the complete existing addon behavior outside `menu    scoption`.
- Deploy the verified files to `C:\Users\buu42\Ashita\addons\accessxi_reader`.

---

### Task 1: Native search-player option resolver

**Files:**
- Create: `ashita/addons/accessxi_reader/modules/menus/search_player_options.lua`
- Create: `tools/test_search_player_option_menu.lua`
- Create: `tools/test_search_player_option_menu.ps1`

**Interfaces:**
- Consumes: `resolve_native_help(menu_name, selected, entry, is_pointer, read_u32, read_string)` arguments supplied by the caller.
- Produces: `resolve_native_help(...) -> text, reason`, where `text` is nonempty only for a verified current native row.

- [ ] **Step 1: Write the failing behavioral test**

Use the captured row fixtures `0x18DAD3C0 -> 0x047C5EE4`,
`0x18DAD7D0 -> 0x047C2ED0`, and `0x18DAD0E8 -> 0x047D1F64`. Assert their
literal native text and assert silence for unsupported menus, zero cursors,
invalid entries, invalid help pointers, and empty strings.

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
& .\tools\test_search_player_option_menu.ps1
```

Expected: FAIL because `modules\menus\search_player_options.lua` does not
exist.

- [ ] **Step 3: Implement the minimal resolver**

Read exactly `entry + 0x40` after validating the menu, cursor, entry, and help
pointer. Return the callback-provided native text or a specific quiet reason.

- [ ] **Step 4: Run the focused test to verify GREEN**

Run:

```powershell
& .\tools\test_search_player_option_menu.ps1
```

Expected: `Search player option native-help checks passed`.

### Task 2: Native-menu dispatch integration

**Files:**
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Modify: `ashita/addons/accessxi_reader/modules/menus/native_menus.lua`
- Modify: `tools/test_search_player_option_menu.ps1`

**Interfaces:**
- Consumes: Task 1's `resolve_native_help(...)`.
- Produces: `accessxi.search_player_option_menu_speech(menu_name, selected, entry)` and a `menu    scoption` branch in `accessxi.native_known_menu_speech`.

- [ ] **Step 1: Extend the failing integration test**

Run the reader integration fixture and assert that `menu    scoption` selects
`object + 0x4C`, dispatches to `search_player_option_menu_speech`, and returns
the resolver's native text without a static row-count gate.

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
& .\tools\test_search_player_option_menu.ps1
```

Expected: FAIL because the known-menu dispatcher has no `scoption` branch.

- [ ] **Step 3: Implement minimal integration**

Load the resolver table, admit `menu    scoption` through the known-menu title
map, force its cursor from `+0x4C`, dispatch it before search-condition menus,
set the existing native speech state fields, and log the proven pointer source.

- [ ] **Step 4: Run focused and regression checks**

Run:

```powershell
& .\tools\test_search_player_option_menu.ps1
& .\tools\test_search_results_native_focus.ps1 -SourcePath .\ashita\addons\accessxi_reader\accessxi_reader.lua
& .\tools\check_lua51_syntax.ps1 .\ashita\addons\accessxi_reader\accessxi_reader.lua
```

Expected: all commands pass.

### Task 3: Live deployment and verification

**Files:**
- Deploy: `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Deploy: `ashita/addons/accessxi_reader/modules/menus/native_menus.lua`
- Deploy: `ashita/addons/accessxi_reader/modules/menus/search_player_options.lua`

**Interfaces:**
- Consumes: Task 2's completed reader.
- Produces: live Prism speech and `state search-player-option` log evidence.

- [ ] **Step 1: Copy the three verified files to the live addon**

Use exact source-to-live paths and compare SHA-256 hashes afterward.

- [ ] **Step 2: Reload AccessXI**

Send `/axi console reload` through the existing external-control file.

- [ ] **Step 3: Reopen and navigate the popup without activating an action**

Use `/sea all stirlock`, open the result, and move only with Up/Down. Confirm
the log reports the live cursor, selected entry, help pointer, and native text.

- [ ] **Step 4: Run the final verification suite and commit**

Run the focused test, search-result regression test, syntax wrapper, deployed
hash comparison, and `git diff --check`. Commit only intended tracked files;
leave `ACCESSXI_HANDOFF_2026-07-12_ROUTE_RECORDER.md` untouched.

