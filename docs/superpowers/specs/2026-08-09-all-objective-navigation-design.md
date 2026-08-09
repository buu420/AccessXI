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

An actionable destination is publishable when its identity and location are
supported by one of these combinations:

1. Both guide sources agree on the named target and zone, and current nav data
   resolves the target without an identity ambiguity.
2. One guide source supplies the exact target and zone, while current nav data
   plus independent game-data evidence corroborate the same identity.
3. A live retail entity supplies an exact identity and position for a dynamic
   target whose zone and action are source-backed.
4. A reviewed AccessXI override pins a source revision, exact current nav target,
   and route evidence for a case automation cannot disambiguate.

`???` targets require a source-backed zone plus exact candidate identity or
position. A name-only `???` match is never sufficient. Conflicting map numbers,
coordinates, entrances, or target identities block the affected route until
reviewed.

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
zone are reduced only when the navmesh proves the selected camp is reachable
from that zone's canonical ingress; otherwise the distinct reachable camps stay
separate or unresolved.

Cross-zone routing starts from the player's current zone. The existing zone
graph chooses a verified transition chain, then the current zone navmesh routes
to the target. Explicit canonical ingress and transport metadata are retained
where an objective requires a particular entrance, floor, one-way path, door,
elevator, geyser, or battlefield.

## Offline pipeline

The build pipeline performs these deterministic stages:

1. Extract and classify installed native rows as playable objectives or
   nonplayable client records.
2. Refresh and parse both guide sources into source-specific ordered claims.
3. Reconcile steps without discarding single-source facts that have independent
   game-data corroboration.
4. Resolve action targets against current destinations, zone names, live-target
   rules, zone edges, transports, and navmesh connectivity.
5. Emit source-specific Lua modules plus one authored resolved-step module for
   each native context or quest area.
6. Emit a coverage report that measures playable objectives, actionable steps,
   routable steps, instruction-only steps, conflicts, and unresolved steps by
   storyline and quest area.
7. Fail the release build when a playable objective has no actionable entry or
   when a generated route lacks pinned identity, location, and route evidence.

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
and zero silently discarded material steps. The report must not add `guide-only`
rows to the navigational coverage total. Conflicted or unresolved steps remain
visible in the audit, never converted into guessed destinations.

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
global count.

Before publication, all changed Lua files pass the Lua 5.1 checker; objective,
navigation, transport, hotkey, package, updater, and public-hygiene tests pass;
the canonical addon is synced to the live Ashita installation; and the latest
GitHub release is verified to contain the exact tested updater payload. The
installer executable remains unchanged unless installer behavior itself is
modified.
