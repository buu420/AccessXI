# Ashita Addon Distribution Notes

Last reviewed: 2026-06-29

AccessXI should be distributed as its own project files, not as edits to Ashita's bundled addon sources or as a repackaged Ashita install.

Relevant Ashita guidance:

- Ashita v4 includes a core `Addons` plugin that lets developers extend Ashita with Lua scripting.
- The official Ashita v4 beta repository includes first-party addon source under an `addons` folder, so addon source living in a repository is a normal Ashita distribution model.
- Ashita's install/update documentation warns users not to directly edit bundled configuration files, default scripts, or included addon source. If edits are needed, users should make their own copy and rename it.

AccessXI repository policy:

- Keep AccessXI source, setup docs, installer scripts, tests, Reloaded/PlayOnline support source, and the repo copy of `accessxi_reader` in Git.
- Keep runtime logs, generated installers, build outputs, screenshots, reverse-engineering project dumps, local Ghidra output, and Microsoft redistributable installers out of Git.
- Keep the live installed addon under `C:\Users\buu42\Ashita\addons\accessxi_reader` as the runtime test copy. Sync it into `ashita/addons/accessxi_reader` before committing release work.
- Treat Ashita itself, third-party payloads, navmesh packs, Reloaded-II framework binaries, generated installer packages, and redistributables as local build/package dependencies unless their licenses and size are reviewed for repository inclusion.

Sources:

- Ashita feature documentation: https://docs.ashitaxi.com/features/
- Ashita Git install/update documentation: https://docs.ashitaxi.com/installation/install_git/
- Ashita Zip install/update documentation: https://docs.ashitaxi.com/installation/install_zip/
- Ashita v4 beta repository: https://github.com/AshitaXI/Ashita-v4beta
