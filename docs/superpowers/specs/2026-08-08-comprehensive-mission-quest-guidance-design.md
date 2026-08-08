# Comprehensive Mission and Quest Guidance Design

## Purpose

AccessXI already exposes native `Missions` and `Quests` navigation categories and can safely route the three observable stages of Bastok Mission 1-2, `A Geological Survey`. This project expands that narrow registry into comprehensive, source-backed guidance for the missions and quests present in the installed FFXI client.

The feature must help a player make progress without pretending the client exposes server-only quest state or that a map grid reference is a walked route. Every native objective should have either usable guidance or an explicit unresolved status. Automatic stage selection and automatic navigation remain available only when the evidence is strong enough.

## Non-negotiable safety rules

- Installed-client DAT titles and live, current-session packets determine what the current character has active. Wiki categories do not determine the active list.
- Persisted packet caches may support menu display, but they never authorize objective routing.
- Objective state, manual step position, and active routes are owned by a World-qualified character identity. Switching characters cancels only mission- or quest-owned routes and cannot leak state between characters with the same name on different Worlds.
- A wiki coordinate, grid square, image, or prose direction is not evidence of a walkable path.
- AccessXI never fabricates a direct route when the navmesh, recorded-route graph, live entity data, or zone graph cannot prove one.
- A source disagreement is preserved as a disagreement. It is never silently averaged, merged, or resolved by whichever page was fetched last.
- A displayed `???` is not considered identified merely because another `???` exists at a nearby coordinate.
- Nonmovement steps such as fighting, farming, trading, waiting, choosing a menu option, or standing on a timed trigger are spoken as instructions. They are not misrepresented as navigation.
- False positives fail closed: guide-only or unavailable is preferable to a route to the wrong target.

## Scope and coverage definition

The valid, displayable objectives in the installed native mission and quest tables are the coverage universe. Header rows, known placeholders, empty records, and protocol sentinels are excluded by the same reviewed rules that protect the live menus. Wiki categories are discovery aids, not the completeness authority. The build pipeline extracts a native manifest first, then attempts to match each valid native row against both guide sources.

On the 2026-08-08 research snapshot:

- BG Wiki's namespace-zero `Missions` category contains 505 pages and its `Quests` category contains 1,032 pages.
- FFXIclopedia's namespace-zero `Missions` category contains 521 pages and its `Quests` category contains 1,116 pages.

Those counts do not prove complete parity with the client because redirects, subcategories, combined pages, aliases, and category omissions differ. A release coverage report therefore starts with the native manifest and assigns every native row one of these outcomes:

- `guide`: one or more ordered, source-backed steps are available;
- `verified-navigation`: at least one step also has a verified target and safe route path;
- `automatic-stage`: current-session native evidence can select the current step without guessing;
- `source-missing`: neither source produced a unique usable match;
- `ambiguous-match`: multiple source pages could match and no deterministic discriminator resolved them;
- `source-conflict`: the sources disagree on a fact required for the requested action.

Comprehensive coverage means no native row disappears silently. It does not mean every row receives automatic routing.

## Evidence hierarchy

Evidence is evaluated by claim rather than assigning one global score to an entire page.

1. **Native client state:** installed DAT identities and titles, live `0x056` mission and quest state, live `0x055` key-item state, inventory state, current zone, and other current-session packet evidence.
2. **Live world state:** currently loaded entity IDs, entity coordinates, names, targetability, movement, and observed interaction state.
3. **AccessXI route evidence:** recorded walked routes, current navmesh paths, verified zone transitions, same-zone re-entry handling, door metadata, and known one-way or drop constraints.
4. **Retail guide agreement:** independently parsed claims from BG Wiki and FFXIclopedia.
5. **LandSandBoat corroboration:** internal aliases, entity IDs, trigger geometry, script predicates, and possible stage structure. This is implementation evidence from a server emulator, not retail authority, and it cannot override live retail evidence or a material retail-guide disagreement.

A higher item in this list may establish identity or current state, but no item bypasses route verification. For example, a live NPC server ID proves which entity is loaded; it does not prove a safe path exists from the player's current shelf or ravine.

## Source acquisition and provenance

### Supported guide APIs

The offline importer uses the official MediaWiki APIs:

- BG Wiki: `https://www.bg-wiki.com/api.php`
- FFXIclopedia: `https://ffxiclopedia.fandom.com/api.php`

Requests use a descriptive AccessXI user agent, MediaWiki `maxlag`, batched title queries, conditional cache reuse, bounded retry with backoff, and conservative request pacing. The game addon performs no web requests. Source refreshes happen in a developer tool and the generated snapshot is shipped with the addon.

Discovery combines recursive mission/quest category traversal, redirects, aliases found in mission and quest templates, and title searches seeded from the native manifest. Fetching records page ID, canonical title, revision ID, revision timestamp, source URL, fetch timestamp, and a content hash. A later source refresh produces a deterministic diff rather than silently replacing reviewed data.

Raw downloaded wikitext is build cache only and is excluded from release artifacts. Generated source claims are emitted into two source-specific data packages, while the AccessXI-authored reconciliation layer references their claim IDs. Runtime guidance contains concise original instructions, normalized factual fields, and claim-level provenance. It does not copy guide articles or images.

### Licensing and attribution boundary

BG Wiki states that non-Square-Enix text is available under CC BY-NC-SA 3.0. FFXIclopedia reports `CC-BY-SA` through its API, and Fandom's licensing policy identifies that as CC BY-SA 3.0 Unported. These licenses are tracked separately because their ShareAlike terms must not be treated as interchangeable.

The repository will include separate third-party notices for each guide source, links to the applicable license and source pages, the revision metadata used for every claim, and a notice that instructions were normalized and rewritten for screen-reader delivery. Source-specific generated claim packages remain separate under their applicable terms; the project-authored reconciliation data does not concatenate or republish expressive source text. No combined verbatim guide text will be distributed. Source-specific raw caches remain excluded from commits and release packages.

LandSandBoat remains separately attributed under GPLv3 and is a build-time corroboration source. Its scripts and generated source tree are not copied into the addon. Any independently verified factual identifier or coordinate retained by AccessXI records its provenance without incorporating LandSandBoat executable code.

## Native manifest and source matching

The importer reuses the addon's installed-client mission and quest parsing rules to generate stable native keys:

- mission: native context plus one-based ROM row ordinal, with the packet progress ID retained separately because later mission tables reuse progress IDs for consecutive display rows;
- quest: native quest-area key plus corrected `0x056` packet-bit ID.

Quest DAT sources are section-aware. In the current English client, Adoulin quest titles come primarily from `ROM/293/70.DAT`, Coalition assignments come from `ROM/293/71.DAT`, and two Mog Garden blocks displayed from the tail of `ROM/176/64.DAT` are tracked by the Adoulin packet. The first supplemental block requires the client-observed `+24` packet-ID correction. Raw embedded DAT bytes are therefore retained as provenance but are not assumed to be globally unique identifiers.

Each key includes its native title and relevant aliases. Source matching is deterministic:

- Missions prefer an exact context and mission-number match from the source template, then require a compatible native title or declared alias.
- Quests prefer an exact normalized title and use quest area, client/start NPC, and source category only to disambiguate duplicate titles.
- Redirects are retained as aliases but resolve to one canonical source page.
- Fuzzy title search can propose candidates for the coverage report, but it cannot publish a match automatically.
- One source page cannot map to multiple native keys unless an explicit reviewed split says that the page intentionally covers multiple objectives.

Ambiguous and unmatched candidates remain visible in the coverage report and are not routed.

## Canonical objective model

Generated runtime files are Lua 5.1 modules, split by source, mission context, and quest area so the addon can load only the selected category and objective. The conceptual reconciliation schema is:

```text
objective
  kind, native_context, native_id, native_title, aliases
  source_matches[]
  ordered_steps[]
  coverage_status

step
  stable_step_id, order, instruction, action
  stage_predicate
  target
  arrival_instruction
  source_claims[]
  comparison
  evidence_level
  route_mode

source_claim
  source_site, page_url, page_id, revision_id, revision_timestamp
  claim_hash, source_location, normalized_fact

comparison
  status: corroborated | compatible | single-source | conflict
  agreed_fields[], conflicting_fields[], missing_fields[]

target
  zone_id, spoken_label, display_name
  live_server_id, internal_alias
  exact_xyz, candidate_xyz[], map_grid
  dynamic, interaction, arrival_radius
```

The `spoken_label` describes the objective, such as `Acting in Good Faith incense brazier`, while `display_name` preserves what a sighted player sees, such as `???`. Internal aliases are lookup evidence and are never spoken as if they were visible in game.

## Dual-wiki comparison rules

Both source pages are parsed independently into normalized claims. Comparison occurs only after parsing, never by concatenating walkthrough prose.

Normalization covers zone aliases, punctuation, capitalization, mission numbers, NPC names, map numbers, grid notation, action verbs, nesting, and ordered-step structure. It does not erase meaningful distinctions such as north versus south, map 1 versus map 2, one entrance versus another, or static versus randomly moving targets.

Claims are compared field by field:

- objective order;
- action type;
- zone and map number;
- target identity and visible name;
- NPC or object interaction;
- exact coordinate or map grid;
- entrance or traversal constraint;
- required key item, item, trade, fight, wait, or menu action;
- completion or stage-transition condition.

The outcomes are:

- `corroborated`: both sources independently assert the same material fact;
- `compatible`: the claims differ in detail but do not contradict one another;
- `single-source`: only one source supplies the claim;
- `conflict`: both sources address the claim and materially disagree.

Corroboration raises guide confidence but never creates a route by itself. A single-source step can be spoken, and it can route only when independent native, live-entity, LandSandBoat identity, or AccessXI route evidence verifies the target and path. A conflict blocks any automatic behavior that depends on the conflicting field. The runtime speaks a concise `Sources disagree about this step; automatic navigation is unavailable` message and keeps both variants in provenance for review.

### Research examples

For `A Geological Survey`, both sources agree on the material sequence: accept the mission, talk to Cid, enter Dangruf Wadi, use the I-8 geyser, and return to Cid. They differ on whether Cid is described at G-8 or H-8. That grid conflict does not affect Cid's identity; AccessXI resolves the existing exact Cid entity from current navigation data rather than routing to either grid square.

For `Acting in Good Faith`, both sources agree that the Eldieme `???` can occupy four braziers and that the player returns to Gantineux, then Eperdur. They disagree about whether lighting the incense always fails or can rarely report success. The moving objective is represented as a live entity or four-candidate set, and the result-text disagreement is preserved without affecting the target identity.

## Stage selection

### Automatic stage

Automatic stage selection is allowed only when all required predicates are available from the current session and owned by the current World-qualified character. Supported predicates may include:

- exact active mission or quest ID;
- owned or absent key item with the required complete key-item table;
- owned item and quantity from current inventory state;
- current zone;
- presence and identity of a live target entity;
- an explicitly captured native progress field whose semantics are verified.

Persisted cache values, elapsed-time guesses, presumed cutscene completion, and LandSandBoat-only server variables cannot select an automatic stage.

### Manual stage

Many retail quest stages are stored only on the server. Those objectives provide an ordered step browser. The player can select the step they are currently on, and AccessXI labels it as `manual step` whenever it is spoken or used to start a route.

Manual selection is stored per World-qualified character and native objective key. It does not mark the game objective complete, alter game state, or claim to be detected automatically. It is revalidated against the active native objective list before use and is discarded if the native key no longer matches.

When native predicates later prove a stage, the automatic stage takes precedence and the manual selection is retained only as dormant history.

## Target identity and `???` handling

Target resolution supports four evidence-safe forms:

1. **Live entity:** an exact verified server ID is resolved from the current entity list and continuously retargeted if the entity moves.
2. **Static exact point:** a verified interaction point with an arrival radius and current route evidence.
3. **Candidate set:** multiple independently verified positions for a random or rotating target. AccessXI chooses only a candidate whose matching live entity is present; otherwise it speaks the candidate list as guide information and does not choose one blindly.
4. **Map-grid only:** spoken as guide information with no point route.

LandSandBoat internal aliases such as `qm1` are useful for distinguishing otherwise identical `???` objects during data preparation. A LandSandBoat ID becomes a retail route identity only after it matches current AccessXI nav data or live retail observation. Nearby name and distance alone are insufficient when multiple identical objects exist.

Dynamic targets remain live targets for the life of the route. The destination beacon and route are refreshed from the current entity position without converting the first observed coordinate into a permanent static point.

## Route construction and arrival behavior

A step receives `verified-navigation` only when all of the following are true:

- the target's zone and identity are exact enough for the action;
- the current AccessXI nav data can resolve the destination;
- the existing route engine proves a walkable path from the current player position or a verified zone-transition chain;
- recorded-path constraints, doors, one-way drops, shelves, ravines, geysers, elevators, and same-zone re-entry rules are honored;
- arrival behavior matches the interaction rather than stopping at a convenient but wrong nearby point.

The route engine continues to live-track the player's position and rematch after detours. Wiki steps never insert speculative straight segments into the route graph. If the player is on an unconnected shelf or the target is behind an unresolved door, AccessXI gives the instruction but reports that no verified walkable route is available.

Arrival speech states the sighted action: talk to the NPC, examine the object, open the named door, trade the listed item, wait on the geyser, or prepare for a fight. A fight or trade instruction is never announced as completed merely because the player reached the coordinate.

## Navigation browser interaction

The existing keys remain the foundation:

- `U` and `O`: previous and next category;
- `J` and `L`: previous and next item;
- `K`: repeat the current item;
- `I`: enter, start, or stop navigation according to the current navigation state.

Within `Missions` or `Quests`:

1. `J` and `L` browse the native active objectives.
2. `I` on an objective opens its ordered steps, initially selecting the verified automatic stage when available, otherwise the saved manual step or the first step.
3. In step view, `J` and `L` move through steps and `K` repeats the selected instruction, evidence status, and whether navigation is available.
4. `I` on a verified movement step starts its route. On a guide-only or nonmovement step, it repeats the required action and explains why no route starts.
5. `U` exits step view back to the objective list. Outside step view, `U` retains its ordinary previous-category behavior.
6. `O` exits step view and advances to the next category; it never silently changes the selected step.
7. If objective navigation is already active, `I` retains the existing stop-navigation behavior before any new route can start.

Counts are always derived from the current list and current objective's actual step count. No menu uses fixed row counts.

## Offline build pipeline

The implementation is divided into independently testable stages but delivered as one coherent feature:

1. Extract the native objective manifest and fetch/cache both wiki inventories.
2. Parse source-specific templates and walkthrough structures into claim records.
3. Match source pages to native keys and produce a conflict/coverage report.
4. Generate Lua 5.1 runtime modules containing only normalized facts, authored instructions, provenance, and reviewed target evidence.
5. Add the nested runtime step browser and World-qualified manual-step store.
6. Add exact target resolution, live dynamic-entity handling, and fail-closed route preparation.
7. Package the generated modules and attribution notices in the addon and installer/update payload.

Generated output is deterministic: the same native files, importer version, source revisions, and reviewed overrides produce byte-identical runtime modules. Reviewed overrides are small, explicit records for ambiguous matches, target identities, or corrected parser output; they never contain guessed route geometry.

## Validation strategy

### Importer and data tests

- Recorded fixtures from both APIs cover redirects, mission and quest templates, numbered and bulleted walkthroughs, nested notes, map numbers, coordinates, multiple entrances, dynamic `???` targets, and malformed pages.
- Golden tests cover the two research examples and assert both agreement and disagreement at field level.
- Matching tests reject duplicate titles, ambiguous candidates, wrong mission context, and fuzzy-only matches.
- Provenance tests require source URL, page ID, revision ID, timestamp, claim hash, and license attribution for every imported claim.
- Coverage tests require every valid native manifest key to receive an explicit outcome and prevent counts from being hard-coded.
- Reproducibility tests generate byte-identical Lua modules from the same snapshot.

### Lua 5.1 runtime tests

- Active versus completed packet bits and all mission contexts retain existing behavior.
- Display caches remain readable while route starts require current-session evidence.
- Same-name characters on different Worlds cannot share manual steps, packet state, or routes.
- Step lists can change size and browse correctly without static row assumptions.
- Automatic predicates override manual selection only when their source state is complete and live.
- Conflicting, ambiguous, missing, and grid-only targets block automatic routing with accurate speech.
- Dynamic `???` targets follow the exact live entity and do not snap to a same-name neighbor.
- Candidate sets do not choose an absent target.
- Nonmovement steps never start a fabricated route.
- Ordinary navigation remains unchanged, including route stopping, categories, hotkeys, doors, zoning, same-zone re-entry, and recorded-route steering.

### Release validation

- Run the focused mission/quest harness and all affected navigation regression suites.
- Run the standalone Lua 5.1 syntax wrapper on every generated and modified Lua file.
- Run importer tests without network from committed fixtures, then run one explicit live-source refresh audit.
- Run `git diff --check`, inspect generated-file diffs, and verify the release archive contains attribution notices but no raw wiki cache.
- Deploy only after offline checks pass, byte-compare the deployed addon against the worktree, then publish through the existing installer auto-update release flow.

## Failure behavior

- API failure leaves the previous reviewed snapshot intact and fails the refresh command; it never emits a partial replacement dataset.
- A source-page revision change invalidates only affected claims and appears in the review report.
- Parser uncertainty produces `source-missing` or `ambiguous-match`, not a guessed step.
- Source disagreement produces `source-conflict` for the affected field and blocks dependent automatic behavior.
- Missing live packet state blocks stage-based routing while preserving readable objective and guide information.
- Missing live entity or safe path preserves the step instruction and reports that navigation is unavailable.
- A character identity transition tears down objective-owned route state before another objective can be resolved.

## Acceptance criteria

The feature is ready when:

- every valid, displayable native mission and quest row has a generated coverage outcome;
- both guide sources are independently represented with revision-level provenance;
- the runtime can browse ordered guidance for every uniquely matched objective;
- source conflicts and unsupported stages are spoken honestly and cannot start unsafe routes;
- verified targets route through existing safe navigation behavior, including live retargeting for moving entities;
- automatic stage selection uses only complete current-session evidence;
- manual selection is clearly labeled and isolated per character and World;
- no existing ordinary navigation, menu speech, route recorder, installer, or updater regression remains;
- the deployed addon and published update payload match the verified build.
