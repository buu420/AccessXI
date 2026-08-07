# AccessXI External Control Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-shot addon-local file bridge that safely dispatches existing `/axi` commands when FFXI chat cannot be opened through Computer Use.

**Architecture:** Poll `logs\ffxi-accessxi-control.txt` from `d3d_present`, remove it before execution, reject anything that fails the existing AXI parser, and dispatch accepted commands through `dispatch_axi_command_text`. Keep source and live Lua identical.

**Tech Stack:** Lua 5.1, Ashita v4, PowerShell static regression tests, Computer Use.

## Global Constraints

- Accept only commands recognized by `is_axi_command_args`.
- Remove the file before dispatch.
- Do not expose arbitrary Ashita, Lua, shell, key, or network execution.
- Poll no faster than every 150 milliseconds.
- Keep source and live addon copies byte-identical.
- Do not send sustained movement until `/axi pos` works through the live bridge.

---

### Task 1: Add the failing bridge regression test

**Files:**
- Create: `C:\Users\buu42\AccessXI\tools\test_axi_external_control_bridge.ps1`

**Interfaces:**
- Consumes: source/live `accessxi_reader.lua`.
- Produces: static proof of path scoping, one-shot deletion, AXI validation, dispatcher reuse, polling order, and synchronized copies.

- [ ] Write assertions for `axi_external_control_path`, `poll_axi_external_control`, `os.remove`, `is_axi_command_args`, `dispatch_axi_command_text`, and the `d3d_present` call.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\buu42\AccessXI\tools\test_axi_external_control_bridge.ps1'` and confirm it fails because the path/function are absent.

### Task 2: Implement and verify the bridge

**Files:**
- Modify: `C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua`
- Modify: `C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua`

**Interfaces:**
- Produces: `accessxi.poll_axi_external_control(now) -> boolean`.

- [ ] Add state fields using `accessxi_paths.addon_path('logs', 'ffxi-accessxi-control.txt')` and a 150 millisecond poll interval.
- [ ] Read the whole file, close it, call `os.remove` before validation/dispatch, normalize one line, and reject non-AXI input.
- [ ] Call `dispatch_axi_command_text(command_text, 'external-control-file')` inside `pcall` and log accepted/rejected/failed outcomes.
- [ ] Poll before zone-settle and recorder logic in `d3d_present`.
- [ ] Run the focused test and both Lua 5.1 syntax checks.

### Task 3: Live proof and regression

**Files:**
- Runtime one-shot: `C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-accessxi-control.txt`

**Interfaces:**
- Consumes: `/axi pos`.
- Produces: live log evidence containing an accepted external command and current player position.

- [ ] Press `Ctrl+Shift+R` in the Zaltar window to reload the addon.
- [ ] Create the one-shot file containing `/axi pos` and verify it is consumed.
- [ ] Confirm the live log reports the command and current zone/x/z/y/yaw.
- [ ] Run route-recorder, both recorded-ravine, shelf-escape, and Lua regression checks.
- [ ] Only after position proof, test one short movement input and compare `/axi pos` before/after.
