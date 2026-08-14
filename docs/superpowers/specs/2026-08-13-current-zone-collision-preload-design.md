# Current-Zone Collision Preload Design

## Problem

Collision terrain is built lazily when a route is selected. In the Upper Jeuno trace, the player position was valid for sixteen seconds before route selection, but the five-second background build did not begin until Start was pressed. The Areas menu then announced “Beacon active” with no route points while route guidance and beacon playback were intentionally suppressed.

## Approved behavior

- After zone loading has settled and a valid player position exists, begin preparing that zone’s collision terrain silently on the existing low-priority native worker.
- Preloading is begin-only: it has no destination, performs no path query, starts no route, emits no speech, and activates no beacon.
- Repeated idle polls in the same zone reuse the same native generation and never restart the build.
- A zone change cancels the prior generation; the first stable position in the new zone starts one new preload.
- Zone 102 is excluded because its installed La Theine navmesh is the established immediate route source and its DAT terrain build has historically been exceptionally slow and unreliable.
- If Start is pressed before preloading completes, retain the safe collision wait but announce that the safe route is still preparing. Never announce an active beacon with no usable route.
- Once the worker is ready, route selection uses the existing collision path query and safety validation. It must not substitute an unvalidated temporary navmesh.

## Boundaries

`collision_navigation.State:preload(zone)` owns the begin-only native lifecycle. Reader polling decides when a zone is stable enough to call it and records one attempt per zone. Existing route and zone-reset code remains authoritative for destination queries and cancellation.

Persistent serialized terrain caching, a new native ABI, and preloading neighboring zones are intentionally out of scope.

## Verification

Focused tests must prove that preload begins once, never calls pathfinding, route selection reuses the generation, zone changes cancel and begin once, zone 102 is skipped, and the menu’s pending branch never claims the beacon is active. Existing collision lifecycle, reader integration, Lua 5.1 syntax, and live deployed hashes remain release gates.
