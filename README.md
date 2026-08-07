# AccessXI

AccessXI adds accessibility support for Final Fantasy XI and PlayOnline. It includes an Ashita v4 in-game reader addon, native PlayOnline speech through Prism, installer and setup tooling, navigation data, sounds, and documentation for blind players.

## Download and setup

Download the newest installer from the repository's GitHub Releases page. Before running it, install Final Fantasy XI and finish the PlayOnline Viewer update. The first update screen may require screen-reader OCR.

For the complete first-time setup, account, update, and login walkthrough, see [setup-guide.md](setup-guide.md).

## Repository layout

- `ashita/addons/accessxi_reader`: the canonical addon source copied into an Ashita v4 `addons` directory and embedded by the installer.
- `src`: native PlayOnline accessibility source.
- `installer`: installer scripts, boot profiles, and installer application source.
- `tools`: build, package, validation, and diagnostic scripts.
- `data`, `sounds`, and `docs`: navigation data, audio assets, setup material, and development notes.
- `third-party-notices`: notices for third-party components used in release packages.

Generated installers, logs, captures, reverse-engineering workspaces, local Ghidra projects, Microsoft redistributables, and large third-party build inputs are intentionally ignored.

## Release boundary

AccessXI does not modify `pol.exe`, `app.dll`, or Final Fantasy XI executables. Native PlayOnline accessibility is loaded by the x86 [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader), then uses the private `AccessXI.PolNative` folder and Prism for speech. The installer backs up files before replacing its own loader-side deployment.

Ashita v4, PlayOnline, Final Fantasy XI, Microsoft runtime installers, navigation meshes, Prism build inputs, Windower resource tables, and other large dependencies are not stored in this repository. The release builder validates and packages locally reviewed copies. Ultimate ASI Loader is downloaded from a pinned official release and verified by SHA-256.

## Building

Native PlayOnline components must be built for 32-bit x86. Configure `ASHITA4_SDK_PATH` for the local Ashita v4 SDK and provide the reviewed x86 Prism build expected by `tools/build_pol_native_asi.ps1`.

Build and validate the complete installer with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build_accessxi_installer_exe.ps1
```

The build produces `dist\AccessXI Installer.exe`, `dist\AccessXI-Ashita-Installer.zip`, and `dist\setup-guide.md`. The package builder takes the addon from `ashita\addons\accessxi_reader`, not from a character-specific runtime cache.

See [docs/ashita-addon-distribution-notes.md](docs/ashita-addon-distribution-notes.md) for the source and packaging boundary.

## Known limitations

- Help Desk > Adventuring Primer: category and article titles and short detail lines are native/DAT-backed. The long article body pages are texture-backed, so AccessXI leaves them silent rather than inventing text.
- Communications > Friend List > Edit Friend List: friend names are visible in native data, but no reliable selected-row signal has been verified. AccessXI leaves that list silent rather than announce the wrong person.
