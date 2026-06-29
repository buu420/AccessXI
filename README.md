# AccessXI

AccessXI is an accessibility project for Final Fantasy XI and PlayOnline. It combines an Ashita v4 in-game reader addon, Reloaded-II PlayOnline support, installer tooling, route/navigation data, and setup documentation for blind players.

This repository is private while the project is being cleaned up for broader distribution.

## Player Setup Guide

For a detailed first-time setup walkthrough, including account creation, dependencies, PlayOnline registration, PlayOnline updates, and the first Final Fantasy XI launch flow, see [setup-guide.md](setup-guide.md).

## Repository Layout

- `ashita/addons/accessxi_reader`: repository copy of the AccessXI Ashita addon source.
- `src`: Reloaded-II PlayOnline support projects.
- `installer`: installer scripts, profiles, and WinForms installer source.
- `tools`: build, packaging, validation, and diagnostic scripts.
- `data`, `sounds`, `docs`: addon data, sound assets, and project documentation.

Generated installers, logs, reverse-engineering dumps, local Ghidra projects, Microsoft runtime installers, and large third-party payload mirrors are intentionally ignored.

See [docs/ashita-addon-distribution-notes.md](docs/ashita-addon-distribution-notes.md) for the current Ashita addon packaging notes and source-control policy.

## Build Notes

Native Ashita/POL support binaries must be built for 32-bit x86 where they load into PlayOnline or Final Fantasy XI.

Set `ASHITA4_SDK_PATH` to:

```powershell
C:\Users\buu42\Ashita\plugins\sdk
```

The output DLL should be copied to:

```powershell
C:\Users\buu42\Ashita\polplugins\accessxi_pol.dll
```

The current machine does not have CMake, `cl`, or MSBuild on PATH yet, so installing Visual Studio Build Tools and CMake is the next build step.

## Known Limitations

- Help Desk > Adventuring Primer: the category list, article titles, and short detail lines are readable from native/DAT-backed data, but the full article body pages are texture-backed resources (`cntguidecg_*`) rather than live text. AccessXI intentionally does not OCR or invent those paragraphs. The full primer is available online at https://www.playonline.com/ff11us/contguide/index.html.
- Communications > Friend List > Edit Friend List: native friend names are visible inside POL PML vectors, but no reliable native selected-row signal has been found. AccessXI intentionally leaves this list silent rather than guessing from visible vector slots or speaking the wrong friend name.
