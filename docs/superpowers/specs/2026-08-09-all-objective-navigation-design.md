# Complete Mission and Quest Navigation Design

## Purpose

AccessXI must make the `Missions` and `Quests` navigation categories useful for
finishing the objectives they display. The previous release imported guide text
for most native objectives but treated that as coverage even when no actionable
destination existed. That definition is insufficient.

This project covers every playable mission and quest represented by the
installed client, including all three nations, every expansion and add-on,
Rhapsodies of Vana'diel, The Voracious Resurgence, Campaign-era objectives,
Abyssea, Adoulin and coalition quests, and the remaining regional quest logs.
Internal sentinels, headers, and protocol-only rows are classified separately
and are not claimed as playable objectives.

## Proven current failures

The 2026-08-09 audit found 1,844 native rows with imported guide records, but
only 313 rows had any verified navigation step: 116 missions and 197 quests.
The current guide corpus contains 23,953 parsed steps, while only 508 steps are
route-ready. Therefore, `guide` status cannot be presented as navigational
coverage.

The live log also proves a runtime failure independent of the content gap.
Expansion contexts call `tonumber(accessxi.current_mission_value_for_context())`
on a function that returns both the mission value and packet age. Lua forwards
both results, so the packet age is interpreted as `tonumber`'s numeric base and
raises `bad argument #2 to 'tonumber' (base out of range)`. The safe context
wrapper hides the crash and silently omits affected storylines.

For `Smash the Orcish Scouts`, both current source pages identify the required
action: obtain an Orcish Axe from Orcish Fodder. BG Wiki confirms East and West
Ronfaure; FFXIclopedia confirms West Ronfaure and also lists Ghelsba Outpost and
La Theine Plateau. The shipped nav catalog contains exact Orcish Fodder camps,
but the destination generator supports only manually reviewed mission farming
overrides, so the active mission currently has no kill target.

## User-visible behavior

`Missions` continues to contain native active missions and only those available
nation missions whose availability is proven by current client state. `Quests`
continues to contain native active quests only. Wiki data never decides what is
active.

Each active objective expands into a flat ordered set of meaningful step items:

- a live-state-selected current step when its stage predicates are fully proven;
- otherwise, all verified actionable steps in guide order, explicitly described
  as steps the player can choose from;
- one destination per distinct required enemy, item source, NPC, object,
  entrance, battlefield, or transport action when the steps lead to different
  places;
- separate destinations for independently useful source-confirmed zones, such
  as East Ronfaure and West Ronfaure Orcish Fodder camps;
- an instruction-only item for actions that require no movement, such as waiting,
  choosing an option, trading an already held item, or defeating enemies after
  arriving.

The existing controls do not change. `J` and `L` move through the flat items,
`K` repeats the highlighted item, and `I` starts or stops its route. Pressing `I`
on an instruction-only step repeats the action and explains that no movement is
required. Counts always come from the current list.

The spoken label includes the native objective title, concise action, target,
and location. Arrival speech states what a sighted guide tells the player to do,
but reaching a camp never claims that a fight, trade, drop, cutscene, or objective
has completed.

## Stage safety

Current-session, World-qualified native evidence remains the only source for
automatic stage selection. Eligible predicates include active mission or quest
ID, a complete current key-item table, current inventory state, current zone,
and an exact live entity identity. Disk-restored caches remain display-only.

Many stages are server-only and cannot be recovered universally from the
client. The Ghidra mission-menu trace confirms the native menu boundary but does
not expose a universal internal stage table. Those objectives expose ordered
step choices instead of guessing the current step. A character or World change
invalidates objective-owned selections and routes without touching ordinary
navigation.

## Source and target evidence

The offline corpus is refreshed through the official MediaWiki APIs for BG Wiki
and FFXIclopedia. Installed DAT rows remain the completeness authority. Each
generated claim pins the source page, revision, URL, and content hash.

Routing input preserves typed source relationships instead of a flattened union:
source step, action, target or role, exact zone and temporal variant, item,
relationship (`talk-to`, `trade-to`, `examine`, `use`, `defeat`, `farm-from`,
`enter-through`, or `wait-for`), and the exact supporting sentence. A name and
zone that came from different source steps can never be joined into evidence.

An actionable destination may enter the review catalogue when its identity and
location are supported by one of these combinations:

1. Both guide sources agree on the named target and zone, and current nav data
   resolves the target without an identity ambiguity.
2. One guide source supplies the exact target and zone, while current nav data
   plus independent game-data evidence corroborate the same identity.
3. A live retail entity supplies an exact identity and position for a dynamic
   target whose zone and action are source-backed.
4. A reviewed AccessXI override pins a source revision and immutable current nav
   target identity for a case automation cannot disambiguate.

`???` targets require a source-backed zone plus exact candidate identity or
position. A name-only `???` match is never sufficient. Conflicting map numbers,
coordinates, entrances, or target identities block the affected route until
reviewed.

Catalogue membership is not permission to start movement. An automatic route
also requires a versioned route contract that references immutable destination,
directed-ingress, and transition identities. The contract pins the exact zone
mesh, FFXINAV binary, proof-tool protocol, source destination row, route policy,
and transition registry hashes. Free-text evidence, a wiki coordinate, a
generated row, or a successful process exit can never promote a destination.

## Route proof boundary

A same-zone walking leg is `mesh-proven` only when both requested endpoints are
valid, exact `FindPath` returns at least two finite waypoints, neither endpoint
is snapped, and the first and last waypoints meet the requested endpoints within
the policy tolerance. Proof mode never calls `FindClosestPath`. The evidence is
directed from one exact target-zone ingress anchor to one immutable destination
instance; reverse reachability is never inferred.

Doors, lifts, geysers, ferries, airships, one-way drops, battlefield entries,
and other stateful crossings are separate transition contracts. Each transition
records its exact pre- and post-anchors, interaction identity, direction,
expected live state change, timeout/cancellation behavior, and evidence hashes.
A navmesh line that appears to cross one of these boundaries is classified as
`requires-transition`, not as a safe route. This specifically prevents a raw
Palborough mesh path from bypassing the required lift.

Enemy camps and other duplicate display names use immutable destination IDs,
not `(zone, name, kind)` as identity. Camp IDs include the zone, source mob
identity, sorted raw spawn identities, and a versioned bounded clustering
policy. Ambiguous camps remain separate choices or unresolved. A chain of nearby
spawns cannot merge floors or grow past the configured camp diameter.

Generic roles such as “San d'Orian Gate Guard” resolve only through an explicit
revision-pinned member set. Each exact member remains a separate destination,
or the runtime may choose the nearest member only when the player's current zone
proves which local set applies. Fuzzy name matching and “first row” selection are
never used.

## Destination classes

The resolver handles these classes through one shared objective-step schema:

- named NPC talks and trades;
- named objects, doors, switches, and `???` interactions;
- enemy camps for fights, farming, or item acquisition;
- zone entrances and ordinary travel steps;
- battlefields and event entrances;
- elevators, geysers, ferries, airships, and other reviewed transports;
- dynamic targets and source-confirmed candidate sets;
- instruction-only actions that do not have a movement destination.

Enemy destinations use current camp records rather than converting wiki grid
squares into guessed coordinates. When one enemy has several source-confirmed
zones, each useful zone is a separate choice. Multiple spawn clusters inside one
zone are reduced only when a current directed route contract proves the selected
camp is reachable from that zone's canonical ingress; otherwise the distinct
camps stay separate or unresolved.

Cross-zone routing starts from the player's current zone. Objective-owned graph
search filters its adjacency list before traversal: every directed prefix edge
must be `proven` or have an equivalent reviewed live-retail transition contract.
`Observed` remains review-only and `untested` never enters an objective route.
The current zone navmesh then routes to the first authorized edge. Explicit
canonical ingress and transport metadata are retained
where an objective requires a particular entrance, floor, one-way path, door,
elevator, geyser, or battlefield.

## Offline pipeline

The build pipeline performs these deterministic stages:

1. Extract and classify installed native rows as playable objectives or
   nonplayable client records.
2. Refresh and parse both guide sources into source-specific ordered claims.
3. Reconcile typed source relationships without discarding single-source facts
   that have independent game-data corroboration. Export every reconciled row;
   text-only `note` rows must be classified rather than silently skipped.
4. Resolve action targets to immutable destination candidates against current
   destinations, zone names, live-target rules, zone edges, and transports.
5. Batch exact route proofs per loaded zone mesh, producing sorted hash-bound
   evidence for each directed ingress-to-destination leg and separate transition
   contracts. Rejected proofs retain a concise machine reason.
6. Emit source-specific Lua modules plus one authored resolved-step module for
   each native context or quest area.
7. Emit a coverage report that measures playable objectives, actionable steps,
   routable steps, instruction-only steps, conflicts, and unresolved steps by
   storyline and quest area.
8. Fail the release build when a playable objective has no actionable entry or
   when an automatic route lacks a current immutable destination, directed local
   leg proof, and every required transition contract.

Generated data never edits source modules by hand. Reviewed overrides stay
small, source-revision-pinned, and explicit. Any source refresh that changes a
pinned claim returns it to the review queue.

## Coverage requirements

The release report must list every native storyline and quest area separately.
For each playable objective it must prove all material progress actions are one
of:

- `routable`: exact verified destination and safe route construction;
- `instruction-only`: complete nonmovement instruction;
- `conflict`: source disagreement shown explicitly and not routed;
- `unresolved`: missing evidence, which blocks a claim of complete coverage.

Complete coverage requires zero playable objectives with no actionable entry
and zero silently discarded, conflicted, or unresolved material steps. The
report must not add `guide-only` rows to the navigational coverage total.
Conflicted or unresolved steps remain visible in the audit, never converted
into guessed destinations, and block a complete release claim until resolved.

Every reconciled source row appears exactly once in the audit as `routable`,
`instruction-only`, `context-only`, `conflict`, or `unresolved`. Objective-level
status is orthogonal: source coverage, native playability, material-step counts,
target proof, same-zone route proof, cross-zone route proof, and automatic-stage
support are separate fields. One reviewed talk target cannot hide unresolved
progress elsewhere in the objective.

`Context-only` requires a source-backed, machine-readable non-material reason;
it is not a catch-all for parser failures. Instructions to protect NPCs, touch
multiple objects, preserve a key item by not leaving a battlefield, choose a
menu answer, or perform another progress-affecting action are material even when
they have no standalone movement target.

## Testing and release

Tests first reproduce the multi-return `tonumber` crash and the missing Orcish
Scouts kill destinations. Generator tests then cover each destination class,
single-source corroboration, source conflicts, duplicate names, multiple zones,
dynamic `???` candidates, nonmovement instructions, native-row classification,
and release-gate failures.

Runtime tests cover missions and quests, all native contexts, flat step
expansion, World-qualified ownership, current-session route authorization,
cross-zone routing, route cancellation, and truthful speech. Corpus tests assert
the coverage matrix for every storyline and quest area rather than a single
global count. Probe tests reject invalid endpoints, one-way assumptions, snapped
or one-waypoint fallback results, stale mesh/DLL/policy hashes, ambiguous target
instances, and direct mesh paths across declared transitions.

Before publication, all changed Lua files pass the Lua 5.1 checker; objective,
navigation, transport, hotkey, package, updater, and public-hygiene tests pass;
the canonical addon is synced to the live Ashita installation; and the latest
GitHub release is verified to contain the exact tested updater payload. The
installer executable remains unchanged unless installer behavior itself is
modified.
