# Ashita addon distribution notes

Last reviewed: 2026-08-07

AccessXI is distributed as its own project rather than as edits to Ashita's bundled addon sources.

Repository policy:

- Keep the canonical addon in `ashita/addons/accessxi_reader` and use that tree as the installer input.
- Keep installer scripts, tests, native PlayOnline source, navigation data, sounds, and player documentation in Git.
- Keep runtime logs, screenshots, generated installers, build outputs, reverse-engineering workspaces, local Ghidra projects, redistributable installers, and machine-specific profiles out of Git.
- Keep large third-party payloads local unless their license and repository size have been reviewed.
- Prefer live/native state and verified walked navigation data. False positive menu labels and unsafe routes are worse than silence.

The release package contains the current AccessXI addon, controlled Ashita boot profiles, native PlayOnline components, prerequisites, navigation resources, and the setup guide. It excludes runtime logs, backups, screenshots, update caches, unrelated addons, and machine-specific boot profiles.

Sources:

- [Ashita features](https://docs.ashitaxi.com/features/)
- [Ashita Git installation](https://docs.ashitaxi.com/installation/install_git/)
- [Ashita ZIP installation](https://docs.ashitaxi.com/installation/install_zip/)
- [Ashita v4 beta repository](https://github.com/AshitaXI/Ashita-v4beta)
- [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader)
