# Mission Farming Navigation Design

## Purpose

AccessXI currently imports mission walkthroughs, but automatic navigation only accepts a narrow class of reviewed `talk` steps. A farming step such as Bastok Mission 1-3, `Fetichism`, therefore remains visible as `location unavailable` even though the imported guides identify the required items, eligible enemies, destination zone, and useful camps already present in AccessXI's navigation data.

This change makes farming and enemy-hunting destinations first-class mission navigation rows. An active mission can lead the player from any supported current zone, through verified zone transitions, to each distinct verified camp needed for the objective. The player stays in the normal flat navigation browser: `O` and `U` select categories, `J` and `L` select rows, `K` repeats a row, and `I` starts or stops the highlighted route.

The implementation is tracker-wide. It processes every imported mission through the same evidence rules rather than hard-coding `Fetichism`. Comprehensive processing does not mean every mission is declared routeable: when the imported evidence, target identity, transport behavior, or route data is insufficient, AccessXI keeps the active mission visible and says that no verified destination is available.

## Scope

This feature covers mission steps whose relevant action is represented by one or more physical destinations, especially:

- farming an item from enemies;
- defeating named or typed enemies;
- obtaining an item at a fixed camp;
- traveling to a verified zone or camp as part of one of those actions.

It reuses the existing imported BG Wiki and FFXIclopedia snapshots, native item resources, enemy-camp navigation rows, zone-transition graph, navmeshes, recorded routes, and objective browser. It does not perform web requests from the addon.

The following are outside this change:

- guessing routes from wiki grid squares or prose alone;
- claiming that every active mission exposes its exact server-side stage;
- automatically fighting enemies, interacting with elevators, or operating doors;
- adding a second mission menu or requiring the player to open guide steps;
- installer path-detection work, rebuilding the installer executable, or publishing a release.

## Non-negotiable safety rules

- Live native client state determines which character and mission rows are eligible for runtime display. Wiki categories never determine whether a mission is active.
- Route starts require current-session, World-qualified character ownership. Persisted mission, quest, completion, key-item, or browser caches are display-only.
- Evidence is reconciled per step and per destination. A disagreement on an unrelated step does not suppress a corroborated farm destination, while a disagreement about the destination's item, enemy, zone, or traversal blocks that destination.
- A wiki coordinate, map grid, route description, or nearby same-name enemy is not proof of a safe route.
- Routeable camps must resolve to exact current AccessXI navigation targets and a verified route chain. Ambiguous enemy names, ambiguous zones, missing transport semantics, and disconnected route data fail closed.
- Co-located enemy types may share one row. Physically distinct camps remain separate rows so the player controls which destination `I` starts.
- Reaching a camp means arrival, not mission completion. AccessXI does not claim that an item dropped, an enemy was defeated, or a mission stage advanced without native evidence.
- False positives and unsafe routes are worse than an unavailable destination.

## Evidence model

The destination builder uses claim-level evidence in this order:

1. Native mission state and World-qualified character identity establish that the mission belongs in the current browser.
2. Existing imported BG Wiki and FFXIclopedia claims establish the relationship among the mission step, required item or fight, eligible enemy, and zone.
3. Native item resources establish stable item identities and spoken names.
4. Current AccessXI enemy-camp and static-destination data establish exact destination identities and coordinates.
5. Current navmeshes, walked-route data, verified zone transitions, and explicit transport metadata establish whether AccessXI can actually navigate there.

LandSandBoat data may corroborate an internal item, enemy, or trigger identity during development, but it cannot override retail guide disagreement or substitute for current AccessXI route evidence. Ghidra-backed inspection has confirmed the native mission-state boundary; it does not expose a universal retail drop-camp or exact mission-stage table, so the design does not pretend that it does.

The existing imported source snapshot remains the input. A broad web refresh is not required for this feature. Any later source refresh continues through the existing offline importer and review process.

## Canonical farming-destination record

The offline generator emits reviewed destination records alongside the existing objective guide data. Conceptually, each record contains:

```text
mission_destination
  stable_id
  mission_context, mission_id, mission_title
  source_step_ids[]
  action: farm | fight | obtain
  items[]
    native_item_id, spoken_name, required_quantity_when_known
  enemies[]
    spoken_name, source_claim_ids[]
  drop_relations[]
    enemy_key, item_ids[], source_claim_ids[]
  zone_id, zone_name
  camp
    nav_destination_id, exact_xyz, arrival_radius
    grouped_enemy_names[]
  canonical_ingress
    from_zone_id, zone_transition_id
  transport_stages[]
    type, approach_destination_id, completion_evidence, prompt
  comparison_status
  route_ready
  failure_reason
  provenance[]
```

`stable_id` is deterministic and does not depend on browser row number. It combines the native mission key, reviewed source step, destination zone, and camp identity. This lets rows be rebuilt dynamically without confusing a highlighted camp with a different row after zoning or character changes.

The record contains item and enemy arrays rather than one guessed label. Explicit drop relations preserve which enemies are actually supported for which items. This is required for objectives where several items drop from the same enemy group, one item can drop from several enemies, or several co-located enemy types form one useful camp.

`canonical_ingress` constrains the final cross-zone leg when the destination zone has multiple entrances that are not mutually connected or are unsafe for this objective. It does not force the player to backtrack after they are already inside the destination zone: local routing always starts from the player's current live position and succeeds only if the current route graph proves a path.

`transport_stages` represents required interactions such as an elevator, geyser, boat, door, or same-zone re-entry. AccessXI routes to the verified approach point, speaks the action a sighted player must perform, waits for native position, floor, zone, or route-graph evidence of completion, and then recalculates the next stage. It never inserts a straight line through the transport gap.

## Offline destination generation

### Step classification

The generator evaluates every imported mission step, not a hand-maintained list of selected missions. Candidate actions include normalized `farm`, `fight`, `obtain`, and travel steps that are inseparable from one of those actions.

For each candidate, source claims are reconciled field by field:

- required item identity and quantity when explicitly stated;
- eligible enemy identity;
- destination zone and map when relevant;
- whether an enemy is explicitly excluded;
- camp or traversal requirements;
- step order and relation to the active mission.

Only material fields needed by that destination gate its route readiness. For example, a disagreement about a later turn-in NPC does not disable a corroborated Palborough Mines farming step. A disagreement over which zone contains the enemies does disable it.

### Entity resolution

Item names are resolved against native item resources. Enemy names are resolved only within the corroborated zone against current AccessXI enemy-camp destinations. Normalized spelling and aliases can propose a match, but publication requires a unique reviewed identity.

An enemy mentioned by only one guide may be retained in provenance and spoken guidance, but it becomes a routeable camp only if independent native, live, or reviewed data corroborates both its objective relevance and its exact camp. Source unions are never silently treated as agreement.

### Camp grouping

Resolved enemy destinations are grouped only when their current navigation points describe the same physically useful camp. Grouping uses explicit reviewed camp identity or a conservative spatial component generated from actual current spawn/navigation points; it does not group merely because enemies share a zone.

- Co-located enemies become one row listing all relevant enemy and item names.
- Distinct lower-floor, upper-floor, entrance, or remote camps become separate rows.
- A camp requiring a different transport sequence remains separate even if its straight-line distance is small.
- Duplicate wiki prose pointing at the same camp is deduplicated by stable camp identity.

### Route readiness

A generated destination sets `route_ready = true` only when all of the following are satisfied:

- the mission step's item/enemy/zone relationship is sufficiently corroborated;
- every spoken item and enemy identity is exact enough not to mislead the player;
- the camp resolves to a current AccessXI destination with exact coordinates;
- a safe local route can be proven by current navmesh or recorded-route data;
- a generated destination marked `untested` is treated only as a candidate until its spawn origin, camp identity, and path probe satisfy the reviewed objective policy;
- required zone transitions and transport stages are represented explicitly, including reliable evidence for continuing after each required interaction;
- the canonical ingress and one-way constraints do not conflict with the route graph.

Otherwise the record carries a concise reviewed failure reason for diagnostics, but unsafe details are not promoted into a startable browser row.

## Runtime browser behavior

The existing `Missions` category remains flat. It contains native active missions plus the already supported missions proven available to start.

For an available-to-start mission, behavior remains unchanged: the row can route to the verified starting NPC. Farming camps are not exposed as though the player had already accepted the mission.

For an active mission:

1. The runtime loads destination records for that exact native mission key.
2. It filters them using current-session mission evidence and the current World-qualified character owner.
3. Each routeable, physically distinct camp becomes its own `J`/`L` selectable row.
4. If one or more routeable destination rows exist, they replace the mission's generic `location unavailable` row.
5. If none can be safely started, the mission retains one generic row and truthfully reports that no verified current destination is available.

Rows are rebuilt from current state and never assume a fixed count. A row's identity is its stable destination ID, not its current index.

The spoken row includes:

- mission title;
- action, such as `farm` or `defeat`;
- every relevant item represented by that row;
- every relevant enemy represented by that row;
- destination zone and a concise camp distinction such as `lower camp` or `upper camp` when needed;
- whether `I` can start navigation;
- the ordinary item position count at the end, following existing navigation speech conventions.

The speech does not add invented quest-stage certainty. If native evidence proves an exact stage or missing item set, the row may say so. Otherwise it describes itself as a mission destination rather than claiming it is the only current task.

## Routing lifecycle

Pressing `I` on a farming row uses the same objective-owned route lifecycle as existing direct mission navigation:

1. Revalidate the row's mission key, stable destination ID, current-session evidence, and World-qualified owner.
2. Read the player's current live zone and position.
3. If outside the destination zone, calculate a verified zone-transition chain to the destination's canonical ingress.
4. Start the first walkable leg from the current live position.
5. After each zone transition, discard obsolete local waypoints, wait for current-zone and live-position evidence, and calculate the next leg.
6. In the destination zone, calculate a local route from the player's actual current position to the next transport stage or final camp.
7. After a detour, combat movement, mount-speed change, or manual displacement, continue using the existing live position rematching rather than replaying a time-based script.
8. At a transport stage, route to its approach point, speak the required interaction, wait for proof of transition, then recalculate.
9. At the final camp, announce arrival and the relevant enemies/items without claiming completion.

If any leg becomes unavailable, ownership changes, live packet evidence disappears, or a route no longer matches the current zone, AccessXI cancels only the mission-owned route and reports why. Ordinary navigation remains untouched.

The route is zone-wide in the practical sense requested by the user: it can begin in any zone from which the current verified zone graph can reach the destination and continue automatically after zoning. It does not claim universal reachability from disconnected maps or unsupported transport networks.

## Fetichism reference behavior

`Fetichism` is the first acceptance fixture, not a special-case runtime implementation.

The imported sources agree on the four required items—Fetich Head, Fetich Torso, Fetich Arms, and Fetich Legs—and on farming eligible Quadav in Palborough Mines. Current AccessXI navigation data contains distinct useful destinations including a lower Amber Quadav camp and an upper group containing Greater, Onyx, and Veteran Quadav, with the upper area requiring reviewed elevator handling.

The expected browser result is therefore separate rows comparable to:

- `Fetichism. Farm Fetich Head, Fetich Torso, Fetich Arms, and Fetich Legs from Amber Quadav. Palborough Mines lower camp. Press I to navigate.`
- `Fetichism. Farm Fetich Head, Fetich Torso, Fetich Arms, and Fetich Legs from Greater Quadav, Onyx Quadav, and Veteran Quadav. Palborough Mines upper camp by elevator. Press I to navigate.`

The precise enemy-to-item wording must follow the reconciled claims; the generator must not imply that every listed enemy drops every listed item unless the evidence supports that relationship. If that relationship cannot be expressed safely, the row speaks the item objective and eligible enemy set separately.

Starting either row from Bastok, North Gustaberg, Palborough Mines, or another supported connected zone must use verified zone-wide routing. The upper-camp row must route through the explicit elevator stage and must not connect floors with fabricated geometry.

## Failure behavior

- A stale or disk-restored mission snapshot may keep a display row visible but cannot authorize `I`.
- A stale browser row is rejected after any character or World transition, even if the new character has the same name or mission.
- Missing source agreement on a material destination field keeps that destination unavailable.
- An ambiguous item, enemy, camp, zone, or entrance is not resolved by nearest-name matching.
- A camp with no current route target remains guide-only and does not start navigation.
- A cross-zone route with no verified chain reports that the destination is unavailable from the current location.
- A transport step with no reliable completion evidence stops at the approach point and speaks the required action; it does not guess the post-transport path.
- Losing the route after zoning or displacement cancels safely instead of walking in circles or toward a stale beacon.
- One failed destination does not hide other independently verified destinations for the same mission.
- One conflicted step does not disable a separate corroborated farming step.

## Implementation boundaries

The code should preserve clear responsibilities:

- The offline guide generator classifies and reconciles source claims.
- A focused destination resolver maps reviewed item/enemy/zone claims to current nav destinations and transport metadata.
- Generated Lua data contains stable, provenance-backed mission destination records and no route calculations.
- `mission_quest_navigation.lua` owns current-character filtering, flat row construction, row speech, and route preparation.
- The existing navigation engine owns live position tracking, local pathfinding, cross-zone continuation, route cancellation, and transport-stage progression.

No broad navigation refactor is included. Any shared route-target extension must remain backward compatible with ordinary NPC, zone-line, survival-guide, and objective navigation.

## Validation strategy

### Offline data tests

- Process every imported mission and report candidate, routeable, conflict, ambiguous, and unavailable counts without fixed expected menu sizes.
- Verify claim-level reconciliation so an unrelated source conflict cannot suppress a safe farming destination.
- Resolve native item names and reject unknown or multiply matched items.
- Resolve enemies only within the corroborated zone and reject ambiguous same-name camps.
- Group co-located enemies while keeping physically distinct camps and transport paths separate.
- Generate deterministic stable destination IDs and byte-identical Lua output from the same inputs.
- Require provenance for every item, enemy, zone, camp, and transport assertion used by a routeable row.

### Focused Lua 5.1 tests

- An active farming mission emits one row per distinct verified camp.
- Co-located enemies appear in one row with complete item/enemy speech.
- Routeable rows replace the generic unavailable row; no-route missions retain it.
- Available-to-start missions still route only to their verified starter.
- `J`, `K`, `L`, `U`, `O`, and `I` preserve the existing flat-browser behavior.
- Row counts and selection survive dynamic list changes through stable IDs rather than fixed indexes.
- Current-session packet provenance is mandatory for route starts.
- Same-name characters on different Worlds cannot reuse rows or routes.
- Character changes tear down active and pending mission routes without stopping ordinary navigation.
- A source conflict on another step does not disable a corroborated camp.
- Ambiguous and unsafe targets fail closed with accurate speech.

### Route integration tests

- Start the same camp route from several connected zones and verify each first leg is based on the current live zone and position.
- Resume the final objective automatically after every verified zone transition.
- Honor canonical destination ingress when alternate entrances are disconnected or unsafe.
- Recalculate after detours and speed changes without time-based waypoint assumptions.
- Exercise doors, same-zone re-entry, and at least one explicit transport stage.
- For Palborough Mines, verify the North Gustaberg transition, lower Amber camp, separate upper camp, elevator prompt, floor transition, and final local route.
- Reject a fabricated direct edge across the Palborough elevator height change.

### Regression and release checks

- Run the focused mission/quest harness and all affected navigation suites.
- Run the repository's standalone Lua 5.1 syntax wrapper on every generated and modified Lua file.
- Run generator fixtures offline, then inspect any deliberate live-source audit separately.
- Run `git diff --check` and inspect generated-data changes for unexpected route-ready promotions.
- Confirm ordinary navigation categories, recorded-route steering, zone-line behavior, and route stop semantics remain unchanged.
- Do not rebuild or publish the installer executable as part of this change.

## Acceptance criteria

The design is satisfied when:

- every imported mission is evaluated by the same farming/fight destination pipeline;
- active missions with multiple distinct verified camps expose separate selectable rows;
- each camp row accurately names its supported items, enemies, zone, and camp distinction;
- `I` starts a verified route from any currently supported connected zone and resumes after zoning;
- local routing always uses the player's current live position and safely recalculates after deviations;
- required elevators, geysers, doors, boats, or re-entry transitions are explicit stages rather than fabricated path edges;
- active missions without adequate evidence remain visible with an unavailable message;
- stale state, ambiguous targets, and unsafe routes cannot start movement;
- `Fetichism` passes the lower-camp, upper-camp, cross-zone, and elevator fixtures without mission-specific runtime code;
- existing mission, quest, and ordinary navigation behavior has no regression;
- installer and release artifacts remain unchanged until separately requested.
