# AccessXI External Control Bridge Design

Date: 2026-07-12

## Goal

Allow the local survey operator to issue existing `/axi` commands when FFXI DirectInput prevents Computer Use from opening chat. The bridge exists only to start and stop route recording, request position, and invoke other commands already validated by AccessXI's AXI dispatcher.

## Interface

AccessXI polls one addon-local file:

`logs\ffxi-accessxi-control.txt`

The file contains one plaintext command. Only text parsed by the existing `is_axi_command_args` check is accepted. Non-AXI content is removed, logged as rejected, and never sent to FFXI, Ashita, the shell, or another process.

The bridge removes the file before dispatching so an interrupted frame cannot execute the command twice. It uses the existing `dispatch_axi_command_text` function, so command validation and behavior remain identical to chat-issued `/axi` commands.

## Polling

Poll at most once every 150 milliseconds from `d3d_present`, before navigation position and recorder polling. This lets a `record start` command capture its start point on the same or next frame. Commands remain available during zone-settle handling so `record stop` can fail closed instead of being stranded.

## Safety

- Accept only `/axi` commands recognized by the existing parser.
- Delete the one-shot command file before execution.
- Execute at most one command per file.
- Log accepted, rejected, and failed commands.
- Do not expose arbitrary Ashita commands, Lua evaluation, shell execution, key injection, or network access.
- Keep source and live addon copies byte-identical.

## Live Bootstrap

The currently loaded addon already binds `Ctrl+Shift+R` to `/addon reload accessxi_reader`. After source and live files are updated and Lua 5.1 syntax passes, Computer Use can press that chord once. The control file can then issue `/axi pos` to prove the bridge before any forward movement.

## Verification

- Add a focused source/static regression test before implementation and observe it fail.
- Verify the focused test passes after implementation.
- Run Lua 5.1 syntax checks on source and live copies.
- Run route-recorder and navigation regression tests.
- Reload live addon, write one `/axi pos` control file, and confirm the live log reports the command and position.
- Do not send sustained movement until live position reporting works.
