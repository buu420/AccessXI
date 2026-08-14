# Home Point Native Row Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make native Home Point and query-menu speech stop exactly at the client-declared visible row length instead of appending stale buffer bytes.

**Architecture:** Add one bounded, schema-aware row decoder beside `native_query_phrase_from_ptr`, then make that function consume the bounded result before its existing context normalization. A focused Lua harness supplies captured native text-object bytes and metadata, so the production decoder is exercised without a live client.

**Tech Stack:** Lua 5.1, Ashita FFI-style memory readers, PowerShell test wrapper.

## Global Constraints

- Visible-glyph metadata is the byte at `text_ptr + 0x106`, accepted only from 1 through 63 inclusive.
- Decode no pair beyond that visible count; punctuation controls `0x0C` and `0x0E` each consume one glyph.
- Preserve existing cursor/list validation and context normalization; add no phrase-specific stale-suffix cleanup.
- Malformed metadata, unsupported controls, truncated reads, and decoded-count mismatch return an empty label.
- Production Lua must remain Lua 5.1 compatible.

---

### Task 1: Bounded native query-row decoder

**Files:**
- Create: `tools/lua_tests/test_native_query_visible_length.lua`
- Create: `tools/test_native_query_visible_length.ps1`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua:10078-10145`

**Interfaces:**
- Produces: `accessxi.native_query_visible_text_from_ptr(ptr) -> string`.
- Consumes: existing `accessxi.is_probe_pointer`, `read_u8`, `decode_ffxi_menu_text_fragment`, `survival_guide_text`, and native-query cleanliness helpers.
- `accessxi.native_query_phrase_from_ptr(ptr, context)` consumes the bounded visible text and retains its current context normalization.

- [ ] **Step 1: Write the captured-byte regression harness**

Create a Lua 5.1 harness that extracts the two production functions, backs `read_u8` with an address-indexed byte table, writes the visible length at `base + 0x106`, and asserts these exact cases:

```lua
assert(decode('NEVER MIND' .. byte(0x0E), 11, 'FAVORITES') == 'Never mind.')
assert(decode('NOWHERE' .. byte(0x0E), 8, 'SLES') == 'Nowhere.')
assert(decode('ON SECOND THOUGHT' .. byte(0x0C) .. ' NONE' .. byte(0x0E), 24) == 'On second thought, none.')
assert(decode('150-PT' .. byte(0x0E) .. ' ITEMS' .. byte(0x0E), 14) == '150-pt. Items.')
for _, bad in ipairs({ 0, 64, 255 }) do assert(decode('VALID', bad) == '') end
assert(decode_truncated('VALID', 5, 4) == '')
```

The wrapper accepts `-Root`, resolves the worktree reader and Lua 5.1 executable, runs the harness, and exits nonzero on failure.

- [ ] **Step 2: Run RED and record the genuine failure**

Run:

```powershell
& .\tools\test_native_query_visible_length.ps1 -Root $PWD
```

Expected: FAIL because the bounded production decoder does not exist or because the current fixed-window scan includes the stale suffix.

- [ ] **Step 3: Implement the minimal bounded decoder**

Read exactly `visible_count` UTF-16-like pairs. Accept printable FFXI bytes plus the existing supported punctuation/wrap controls, build the raw fragment, decode it through the existing FFXI fragment decoder, and verify the logical glyph count before returning. Replace the fixed `collect_probe_ffxi_utf16_entries(ptr, 0x48, ...)` assembly inside `native_query_phrase_from_ptr` with this result.

The implementation must follow this failure shape:

```lua
local count = tonumber(read_u8(ptr + 0x106));
if (count == nil or count < 1 or count > 63) then return ''; end
-- Decode exactly count visible glyphs. Any unreadable or unsupported pair returns ''.
```

- [ ] **Step 4: Run GREEN and adjacent query suites**

Run:

```powershell
& .\tools\test_native_query_visible_length.ps1 -Root $PWD
& .\tools\test_homepoint_windurst_waters_label.ps1
& .\tools\test_generic_query_wrapped_rows.ps1
& C:\Users\buu42\AccessXI\tools\check_lua51_syntax.ps1 -Path .\ashita\addons\accessxi_reader\accessxi_reader.lua -LuaDll C:\Users\buu42\AccessXI\tools\lua51\lua5.1.dll
git diff --check
```

Expected: all commands exit 0; syntax output contains `syntax ok`.

- [ ] **Step 5: Self-review and commit**

Verify the diff contains no new `gsub` for `Favorites`, `Sles`, `Halvung`, `Arrapago`, or other observed suffixes. Commit only the reader and focused tests:

```powershell
git add ashita/addons/accessxi_reader/accessxi_reader.lua tools/lua_tests/test_native_query_visible_length.lua tools/test_native_query_visible_length.ps1
git commit -m "fix: bound native query row decoding"
```
