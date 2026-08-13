# Mission Inventory Progression Design

## Purpose

AccessXI currently keeps an active mission on an item-acquisition destination even after the required item appears in the player's normal Inventory. For example, `Smash the Orcish Scouts` continues to offer Orcish Fodder camps after the player obtains an Orcish Axe, although the imported guide's next material step is to return and trade the Axe to a San d'Orian Gate Guard.

This change makes normal-inventory possession advance applicable mission guidance. It applies through the shared mission-step model rather than through an Orcish Axe or mission-name special case.

## Approved behavior

- Inventory item changes update the active mission's displayed step immediately.
- If a mission-owned route targets a step that the inventory change supersedes, AccessXI cancels that route.
- AccessXI never starts the next route automatically. The player presses `I` when ready.
- If no route is active, AccessXI only updates the mission rows. It does not produce unsolicited movement.
- If the Missions category is open, the refreshed row is available immediately through the existing `J`, `K`, `L`, and `I` controls.
- An item already present when the player opens Missions produces the advanced step without requiring a new item packet.
- Ordinary navigation and routes owned by other categories are not canceled.

## Inventory authority

The authoritative state is a fresh scan of Ashita's native Inventory memory interface for container `0`, the player's carried Inventory. Chat messages such as `obtains an Orcish axe` are not state evidence and are not parsed for progression.

The snapshot maps exact native item IDs to positive carried counts. Item names from typed guide records resolve through the installed native item resources to a unique item ID; ambiguous or missing resolution does not advance a step. Required quantities are honored when the typed guide supplies them. Storage, wardrobes, satchel, sack, case, and other remote containers do not satisfy a trade or turn-in step that requires the item in carried Inventory.

Each snapshot is bound to the current World-qualified character identity and objective-session epoch. Character, World, logout, or session changes clear it before any mission row or route can reuse it.

## Refresh lifecycle

AccessXI refreshes the snapshot in two bounded situations:

1. synchronously before constructing or refreshing the Missions category;
2. after a relevant incoming inventory-update packet, scheduled for the next safe reader tick so native memory reflects the accepted packet.

The packet is only a wake-up signal. AccessXI does not trust item IDs, counts, or ownership parsed from the packet when choosing the mission step. A compact inventory fingerprint prevents work when the native item/count set did not change.

There is no continuous inventory polling loop. A refresh scans at most the available slots in container `0`, keeping the change isolated from ordinary navigation timing and avoiding a new source of route lag.

## Mission-step selection

The mission navigation module evaluates typed, reconciled guide steps in their established order.

An acquisition step may be treated as satisfied by inventory only when all of the following are true:

- it is structurally an obtain, farm, or defeat-to-obtain step;
- its required normal items resolve to exact native item IDs;
- the current identity-bound Inventory snapshot contains every required item in the required quantity;
- the following material guide step is structurally mapped to the same active mission.

When those conditions hold, the acquisition destinations are removed from the fresh mission rows and the next material step is exposed. For `Smash the Orcish Scouts`, the East and West Ronfaure Orcish Fodder camp rows are replaced by the Gate Guard return-and-trade destinations.

Multi-item missions advance only after the complete required item set is present. Possessing an unrelated item, only part of the set, or an item in a remote storage container does not change the step. The resolver never infers progression from free text alone and never changes which mission is active.

## Route cancellation and user feedback

After a changed inventory fingerprint, AccessXI rebuilds the current mission rows and compares the active mission route's immutable mission, guide-step, candidate, and destination ownership with the fresh rows.

- If the exact routed row remains current, the route continues.
- If item possession superseded that row, AccessXI cancels only the mission-owned route and clears its pending cross-zone state.
- If no mission route is active, no route operation occurs.
- If another ordinary or non-mission route is active, it remains untouched.

When a route is canceled, AccessXI speaks one concise update stating that the mission changed and that the player can select the next destination and press `I`. When no route is active, the mission list updates quietly unless the Missions category is already open, in which case its current row is refreshed through the existing browser speech path. The next route is never started as a side effect of item acquisition.

## Failure behavior

- If native Inventory memory is temporarily unavailable or a scan throws, AccessXI retains the previous display state and does not cancel movement based on an unknown snapshot.
- A partial or invalid scan is not published. The reader retries on the next inventory event or Missions-category refresh.
- Unknown, ambiguous, or zero-count items do not satisfy a required-item predicate.
- A stale snapshot from another character, World, or session cannot advance a mission or preserve a route.
- A mission with no structurally valid next material step keeps its current guidance rather than guessing.
- One mission's item change cannot alter another mission's rows or ordinary navigation.

## Implementation boundaries

- `accessxi_reader.lua` owns the native Inventory scan, identity/session binding, inventory fingerprint, event-triggered scheduling, and notification that objective state changed.
- `mission_quest_navigation.lua` owns required-item evaluation, fresh mission-row selection, and determining whether the active mission route still has an exact owner row.
- Existing generated guide modules remain the source of ordered typed steps, required items, and turn-in destinations.
- Existing route start and stop functions remain the only movement boundary. Inventory refresh code never calls a route-start function.

No packet-format parser, chat-message parser, broad navigation refactor, or mission-specific hard-coded table is added.

## Validation

Focused tests must exercise the production inventory boundary rather than injecting fictional `inventory_packet_*` fields.

- Before the Orcish Axe is present, `Smash the Orcish Scouts` exposes its Orcish Fodder camp choices.
- Adding item ID `16656` with count `1` advances it to the exact Gate Guard turn-in step.
- Starting with the Axe already in Inventory advances the mission when Missions opens.
- Acquiring the Axe during an active camp route cancels that mission route and starts no replacement route.
- Acquiring it with no active route updates rows and starts no route.
- Pressing `I` after the update starts only the newly selected turn-in route.
- Unrelated items, zero counts, remote-container copies, scan failures, and stale character/session snapshots do not advance the mission.
- A multi-item acquisition step advances only when its full required set and quantities are carried.
- Repeated unchanged inventory packets do not rebuild rows or repeat speech.
- Ordinary routes and other mission rows remain unchanged.
- Full-reader and affected module Lua 5.1 syntax checks pass, focused mission/navigation harnesses pass, and the deployed addon contains the verified changed bytes.

## Acceptance criteria

The feature is complete when a live Orcish Axe acquisition changes `Smash the Orcish Scouts` from the camp step to the Gate Guard turn-in step, cancels an active obsolete mission route without starting another, also works when the Axe was already carried before opening Missions, and the same typed inventory rule works for other applicable mission item sets without mission-specific runtime code or measurable continuous polling overhead.
