# Comprehensive Mission and Quest Guidance Implementation Plan

> Execute in `C:\Users\buu42\Documents\Codex\2026-08-08\accessxi-comprehensive-objectives\work\repo` on branch `agent/comprehensive-mission-quest-guidance`.

Execution mode is the current task, sequential and test-first, matching the user's request to continue without per-objective confirmation stops.

## Goal

Generate source-backed ordered guidance for every valid native FFXI mission and quest, compare BG Wiki and FFXIclopedia claim by claim, expose that guidance through the existing navigation browser, and start a route only when the exact step target and walkable path are independently safe.

## Architecture

An offline Python importer reads the installed FFXI DATs, fetches revisioned MediaWiki source snapshots, parses source-specific walkthrough steps, matches pages to native IDs, reconciles claims, and generates deterministic Lua 5.1 modules plus a coverage report. Raw wiki pages stay in an ignored local cache. The live addon loads only the selected native objective's generated chunks, maintains a World-qualified manual step, and hands only reviewed exact targets to the existing route engine.

The initial bulk generation may classify unresolved entries as source-missing, ambiguous, conflicting, or guide-only. It must never raise those entries to route-ready merely to improve a coverage percentage.

## Tooling

- Python 3.12 with `mwparserfromhell==0.7.2` for offline MediaWiki parsing.
- Python standard-library `unittest`, `urllib`, `json`, `hashlib`, `difflib`, and `pathlib` for tests and acquisition.
- Existing Lua 5.1 runtime and `tools\check_lua51_syntax.ps1` for addon validation.
- Existing AccessXI navigation harnesses and installer/update packaging scripts.

## Task 1: Lock the native manifest decoder with failing tests

**Files:**

- Create `tools/objective_guides/__init__.py`
- Create `tools/objective_guides/model.py`
- Create `tools/objective_guides/native_manifest.py`
- Create `tools/test_objective_guides.py`
- Create `tools/test_objective_guides.ps1`
- Create `tools/bootstrap_objective_guides.ps1`
- Create `tools/requirements-objective-guides.txt`
- Modify `.gitignore`

1. In `tools/test_objective_guides.py`, construct small in-memory `d_msg` mission and quest records using the same byte inversion and offsets as the live Lua reader.
2. Assert mission decoding reads layout offsets `0x18`, `0x20`, and `0x28`, title data at record offset `0x3C`, and mission ID at `0x1C`.
3. Assert quest decoding uses title offset `0x7C`, inverted ID byte at `0x5C`, stride `0x280`, and rejects blank, `Client:`, `Summary:`, `G<number>`, `AS~`, `ATV`, and `ZL` placeholders.
4. Assert mission native keys use the stable one-based ROM row ordinal while retaining the possibly repeated packet progress ID, and quest native keys use the area plus corrected `0x056` packet-bit ID. Retain native title, source DAT, record offset, and optional mission orders/quest detail.
5. Assert duplicate final native keys fail generation instead of overwriting rows. Cover repeated mission progress IDs, non-English placeholder rejection, section-bounded quest DAT decoding, the Adoulin Mog Garden supplemental sections, and the corrected Adoulin/Coalition DAT paths.
6. Add a bootstrap wrapper that accepts `-Python`, defaults to `ACCESSXI_PYTHON`, then `python`, then `py -3`, creates the ignored `tools\.objective-guides-venv`, and installs the exact requirements file.
7. Add a test wrapper that uses the bootstrapped virtual-environment Python by default, accepts an explicit `-Python` for recovery, and runs `python -m unittest tools.test_objective_guides` without performing network installation during the test.
8. Ignore `/tools/.objective-guides-venv/`.
9. Run the test and confirm it fails because the package does not exist.
10. Implement immutable dataclasses in `model.py` and byte-oriented decoder functions in `native_manifest.py`.
11. Add the current mission context/DAT and quest area/DAT tables from the live reader as declarative constants, with the FFXI root supplied by CLI argument rather than hard-coded.
12. Bootstrap once, then run:

```powershell
& .\tools\bootstrap_objective_guides.ps1 -Python 'C:\Users\buu42\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
& .\tools\test_objective_guides.ps1
```

13. Commit: `test: lock native objective manifest decoding`.

## Task 2: Add transactional MediaWiki acquisition

**Files:**

- Create `tools/objective_guides/mediawiki.py`
- Create `tools/testdata/objective_guides/bg-api-pages.json`
- Create `tools/testdata/objective_guides/ffxiclopedia-api-pages.json`
- Modify `tools/test_objective_guides.py`
- Modify `.gitignore`

1. Add tests for MediaWiki continuation, redirects, canonical page titles, page/revision IDs, revision timestamps, missing pages, and duplicate canonical pages.
2. Assert requests include the AccessXI user agent, `formatversion=2`, `rvslots=main`, `maxlag=5`, and bounded batch sizes.
3. Assert a failed page or truncated continuation keeps the prior reviewed snapshot intact and never writes a partial replacement.
4. Assert cache keys include site, page ID, revision ID, and content SHA-256.
5. Add fixture responses for the researched `A Geological Survey` and `Acting in Good Faith` pages from both sites. Keep only the API fields required by the parser and record their source/license in the fixture header metadata.
6. Implement `MediaWikiClient`, `PageRevision`, category traversal, title lookup, batched revision fetch, exponential backoff, and atomic JSON cache writes.
7. Ignore `/tools/objective_guides_cache/` and temporary snapshot files while preserving the virtual-environment rule from Task 1.
8. Run the offline importer tests twice and assert the second pass reads fixtures/cache without network.
9. Commit: `feat: add revisioned objective source acquisition`.

## Task 3: Parse ordered walkthrough claims from both wiki dialects

**Files:**

- Create `tools/objective_guides/wikitext.py`
- Modify `tools/test_objective_guides.py`
- Modify both source fixtures as needed to cover real syntax

1. Write failing tests for BG `Mission Header`/`Quest Header` and FFXIclopedia `Mission`/`Quest` templates.
2. Cover `Walkthrough` heading discovery, `#`, `*`, `#*`, nested notes, tables surrounding lists, links, bold text, redirects, and common location templates.
3. Add explicit template renderers for `Location`, `Location Tooltip`, key-item/item markers, and harmless display wrappers. Unknown templates retain readable parameter text when that is unambiguous; otherwise they produce a parser warning rather than guessed prose.
4. Extract each step's source list marker, depth, order, cleaned source-specific text, linked entities, zone candidates, map number, grid coordinates, action type, item/key-item mentions, and warning list.
5. Reject image captions, navigation templates, category links, reward tables, plot details, and page furniture from runtime steps.
6. Assert `A Geological Survey` produces the same material sequence from both sources while retaining the G-8/H-8 coordinate difference.
7. Assert `Acting in Good Faith` retains four candidate braziers and the result-text disagreement.
8. Cap each spoken step to a reviewed screen-reader-safe length without truncating coordinates, entity names, or required action; overflow remains in provenance but not automatic speech.
9. Run all importer tests.
10. Commit: `feat: parse dual-wiki objective walkthroughs`.

## Task 4: Match pages to native IDs and reconcile claims

**Files:**

- Create `tools/objective_guides/matching.py`
- Create `tools/objective_guides/reconcile.py`
- Create `data/mission-quest-guides/reviewed-overrides.json`
- Modify `tools/test_objective_guides.py`

1. Add tests for exact mission context/number matching, exact quest-title matching, redirect aliases, punctuation normalization, and duplicate-title disambiguation by quest area/start NPC.
2. Assert fuzzy matching can appear only in the review report and cannot publish a runtime mapping.
3. Assert one page cannot map to multiple native keys without an explicit reviewed split.
4. Add ordered step alignment tests using action, zone, entity, item, map, and coordinate fields rather than raw prose similarity alone.
5. Classify paired fields as corroborated, compatible, single-source, or conflicting. A coordinate or map conflict must not be erased because the target name agrees.
6. Assert conflicts block dependent route metadata but leave guide variants readable.
7. Assert a four-position dynamic target remains a candidate set and cannot collapse to the first coordinate.
8. Seed reviewed overrides only for already verified identities and mappings, including the existing `A Geological Survey` native key and its three native key-item stages. Do not add a target override merely to eliminate an unresolved report row.
9. Run importer tests and inspect the JSON serialization for deterministic key and step ordering.
10. Commit: `feat: reconcile objective guide evidence`.

## Task 5: Generate license-separated Lua chunks and coverage artifacts

**Files:**

- Create `tools/objective_guides/generate_lua.py`
- Create `tools/objective_guides/cli.py`
- Create `tools/build_objective_guides.ps1`
- Create `ashita/addons/accessxi_reader/modules/mission_quest_guide_index.lua` (generated)
- Create generated `ashita/addons/accessxi_reader/modules/mission_quest_bg_<kind>_<context>.lua` chunks
- Create generated `ashita/addons/accessxi_reader/modules/mission_quest_ffxiclopedia_<kind>_<context>.lua` chunks
- Create generated `ashita/addons/accessxi_reader/modules/mission_quest_reconcile_<kind>_<context>.lua` chunks
- Create `data/mission-quest-guides/native-manifest.json` (generated)
- Create `data/mission-quest-guides/source-snapshot.json` (generated)
- Create `data/mission-quest-guides/coverage.json` (generated)
- Create `data/mission-quest-guides/coverage.md` (generated)
- Create `third-party-notices/BG-Wiki-objective-guides-CC-BY-NC-SA-3.0.txt`
- Create `third-party-notices/FFXIclopedia-objective-guides-CC-BY-SA-3.0.txt`
- Modify `tools/test_objective_guides.py`

1. Write failing tests for Lua string escaping, stable module names, deterministic ordering, source separation, revision provenance, and byte-identical regeneration.
2. Require every valid native key to appear once in the index with guide, source-missing, ambiguous-match, or source-conflict coverage.
3. Generate source-specific step text only into the applicable source module. Generate project-authored pairing/status/target records separately.
4. Add license headers to every source-specific generated module and keep raw wikitext out of generated output.
5. Make the CLI support `manifest`, `fetch`, `build`, `report`, and `all`, with `--offline` refusing network and `--refresh` explicitly replacing a complete cached snapshot.
6. Make the PowerShell build wrapper require/use the bootstrapped ignored virtual environment, pass the installed FFXI root, and fail if any phase returns nonzero. Dependency installation remains an explicit bootstrap action rather than hidden test behavior.
7. Run generator tests, Lua 5.1 syntax checks for every generated module, and `git diff --check`.
8. Commit: `feat: generate objective guide runtime data`.

## Task 6: Perform and audit the full dual-wiki refresh

**Files:**

- Modify generated data and Lua modules from Task 5
- Modify `data/mission-quest-guides/reviewed-overrides.json` only for evidence-backed corrections
- Modify `data/mission-quest-guides/coverage.md`

1. Run the live refresh with the descriptive AccessXI user agent against both APIs and the installed client at `C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI`.
2. Seed discovery from every native title, both top-level categories, recursive subcategories, redirects, and template aliases.
3. Record exact source revisions and counts. Do not silently discard category-only pages; list them as source-only rows in the report.
4. Review all automatically matched duplicate titles, all conflicts affecting zone/entity/coordinate/action/order, and every proposed target link.
5. Leave unresolved matches unresolved. The report must distinguish parser failure, no page, ambiguous page, and source disagreement.
6. Run an offline rebuild from the completed cache and assert byte-identical output.
7. Record final valid-native, guide, dual-source, conflict, guide-only, verified-target, and automatic-stage counts in `coverage.md`.
8. Commit: `data: add dual-wiki objective guide snapshot`.

## Task 7: Add a lazy Lua guide loader and character-safe step state

**Files:**

- Create `ashita/addons/accessxi_reader/modules/mission_quest_guides.lua`
- Modify `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- Modify `ashita/addons/accessxi_reader/modules/mission_quest_objectives.lua`
- Modify `tools/lua_tests/test_mission_quest_navigation.lua`
- Modify `tools/test_mission_quest_navigation.ps1`

1. Extend the Lua harness with generated mini index/source/reconciliation modules loaded from a temporary addon root.
2. Assert only the selected context chunks load and missing/corrupt chunks fail one objective closed without removing other active objectives.
3. Add APIs to resolve a native key, open/close step view, move/repeat a step, report step count, select an automatic stage, and expose the selected route descriptor.
4. Pair source steps through reconciliation records. Speak one concise primary instruction when claims agree; on conflict speak that sources disagree and expose both short variants without starting a route.
5. Store manual selection in append-only `data\ffxi-objective-manual-steps.tsv` entries keyed by World-qualified identity plus native key. Validate each row and use the last valid value; malformed or legacy name-only rows are ignored.
6. Assert two same-name characters on different Worlds cannot share manual selections.
7. Assert a character change exits step view, clears loaded objective selection, and cancels only mission/quest-owned active or pending routes.
8. Add `guide_step_id` to the three existing Geological Survey stage definitions so live key-item evidence initially selects the appropriate guide step.
9. Preserve display from cached native packet data but require live packet evidence before an automatic stage or route is accepted.
10. Run focused Lua tests and syntax checks.
11. Commit: `feat: add character-safe objective step browser`.

## Task 8: Integrate nested objective steps with I/U/O/J/K/L

**Files:**

- Modify `ashita/addons/accessxi_reader/accessxi_reader.lua`
- Modify `tools/test_navigation_hotkeys.lua`
- Modify `tools/test_navigation_hotkeys_integration.ps1`
- Modify `tools/lua_tests/test_mission_quest_navigation.lua`

1. Add failing integration assertions for objective-list versus step-view behavior.
2. Load `mission_quest_guide_index` and the new guide code module beside the existing objective modules.
3. Make `I` on a mission/quest row enter step view. Make `I` on a verified movement step route; make it repeat an accurate reason on guide-only or nonmovement steps.
4. In step view, route J/K/L through previous/repeat/next step APIs without changing the native objective list index.
5. Make U exit step view to the same objective. Make O exit step view and advance one category. Preserve ordinary U/O behavior outside step view.
6. Ensure active or pending navigation still makes I stop the route before any menu action.
7. Reset step view on menu close, zone/character invalidation, and objective disappearance.
8. Derive all objective and step counts dynamically and preserve current speech phrasing without reintroducing the `Navigation` prefix.
9. Run hotkey unit/integration tests and the focused objective harness.
10. Commit: `feat: browse mission and quest steps with nav keys`.

## Task 9: Resolve only exact, independently safe step targets

**Files:**

- Modify `tools/objective_guides/reconcile.py`
- Modify `data/mission-quest-guides/reviewed-overrides.json`
- Modify generated reconciliation modules
- Modify `ashita/addons/accessxi_reader/modules/mission_quest_guides.lua`
- Modify `ashita/addons/accessxi_reader/modules/mission_quest_navigation.lua`
- Modify `tools/lua_tests/test_mission_quest_navigation.lua`
- Modify `tools/test_nav_live_entities.ps1`

1. Add failing tests for named static target references, exact live server IDs, multiple-candidate targets, map-grid-only guidance, nonmovement actions, and source conflicts.
2. Permit a static reference only when zone, visible target name, and kind uniquely match current nav data and the reviewed target record requires that exact point.
3. Permit a live target only when its verified server ID is currently present with the expected visible name/type. Preserve index/server ID/live kind in copied points so moving destinations retarget through existing live-route polling.
4. For `???`, require a reviewed internal identity plus a matching live server ID. Nearby same-name objects and LSB-only identity never suffice.
5. For candidate sets, route only to the candidate whose exact live entity is present. Otherwise announce all source-backed map positions as guide information.
6. Keep map-grid-only, fight, farm, trade, wait, menu, and unresolved-door steps guide-only unless a separate reviewed movement target exists.
7. Route through the existing same-zone, zone-search, recorded-route, door, elevator, geyser, and navmesh systems. Do not add a straight-line fallback.
8. Assert loss of a dynamic target stops the route instead of continuing to stale coordinates.
9. Generate a target-review report for exact named NPC candidates that are not yet approved; do not activate candidates automatically.
10. Run objective and live-entity tests.
11. Commit: `feat: route verified objective step targets`.

## Task 10: Package attribution and generated guide data

**Files:**

- Modify `tools/package_accessxi_installer.ps1`
- Modify `tools/test_accessxi_installer_package.ps1`
- Modify `tools/test_public_release_hygiene.ps1`
- Modify `README.md`

1. Add failing package assertions for the guide index, at least one chunk from each source, the coverage snapshot, and both source license notices.
2. Copy both new notices to the release-level `third-party-notices` folder and include their hashes in the package manifest.
3. Verify the addon tree copy includes all generated chunks and excludes raw source caches, local virtual environments, temporary files, and manual per-character step state.
4. Add a README section explaining automatic versus manual stages, source disagreement, guide-only behavior, and the nested I/U/O/J/K/L interaction.
5. Assert public release hygiene contains no raw wiki cache, hard-coded local paths, character names, or unreviewed target overrides.
6. Run installer package tests without creating a public release yet.
7. Commit: `build: package objective guides and attribution`.

## Task 11: Full regression, live deployment, and publication

1. Update any affected legacy navigation regression wrapper that still hard-codes `C:\Users\buu42\AccessXI` or the live Ashita addon so it accepts `-RepoRoot`, defaults to its historical path for compatibility, and can test this isolated worktree before deployment. This includes the live-entity, same-zone re-entry, zone-search, zoning/key blocking, door, Metalworks elevator, and Dangruf fount wrappers listed below.
2. Run the worktree-targeted forms of:

```powershell
& .\tools\test_objective_guides.ps1
& .\tools\test_mission_quest_navigation.ps1
& .\tools\test_navigation_hotkeys.ps1
& .\tools\test_navigation_hotkeys_integration.ps1
& .\tools\test_nav_live_entities.ps1
& .\tools\test_nav_same_zone_reentry.ps1
& .\tools\test_nav_zone_search_command.ps1
& .\tools\test_nav_zoning_and_key_blocking.ps1
& .\tools\test_nav_door_interaction_prompt.ps1
& .\tools\test_nav_metalworks_elevator.ps1
& .\tools\test_nav_dangruf_fount_drop.ps1
& .\tools\test_accessxi_installer_package.ps1
& .\tools\test_accessxi_installer_auto_update.ps1
& .\tools\test_public_release_hygiene.ps1
```

3. Run `tools\check_lua51_syntax.ps1` against every addon Lua file and `git diff --check`.
4. Inspect the coverage report, target-review report, generated diff, source revisions, and release notices. Search for guessed coordinates, fuzzy runtime matches, fixed counts, character names, raw wiki content, and local paths.
5. Copy only the verified addon tree into `C:\Users\buu42\Ashita\addons\accessxi_reader`, excluding runtime logs and per-character data. Byte-compare all deployed source/generated files with the worktree.
6. Rerun the historically live-path regression wrappers against the deployed addon, then reload the addon only when the user is ready for live validation. Confirm category speech, step browsing, existing Geological Survey stage selection, route stopping, and at least one guide-only objective.
7. Build the installer package and installer executable, run package/update tests against the built artifacts, and calculate SHA-256 hashes.
8. Push the feature branch, open a pull request, merge only after checks pass, build a new public release asset, and confirm GitHub's latest-release API exposes exactly one verified `AccessXI-Setup.exe` with a digest.
9. Run the installed setup executable once to confirm its auto-updater selects the new payload and the installed addon contains the same guide snapshot revision.

## Stop conditions

- Stop a source refresh if either API cannot complete all requested continuations.
- Stop generation if any valid native key disappears relative to the prior snapshot without an explicit reviewed reason.
- Stop runtime route activation for any ambiguous, conflicting, fuzzy-only, grid-only, or identity-unverified target.
- Stop deployment if the live addon contains user changes that overlap modified files.
- Stop publication if the package omits attribution, includes raw caches, fails Lua 5.1 syntax, or differs from the deployed/tested addon.
