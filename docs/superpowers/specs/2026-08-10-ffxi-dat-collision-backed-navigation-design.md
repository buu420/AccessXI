# FFXI DAT Collision-Backed Navigation Design

## Goal

Make AccessXI derive walkable routes from the collision geometry installed with Final Fantasy XI instead of trusting a prebuilt `.nav` file that can contain wall-crossing shortcuts. The player must not have to walk, record, or visually inspect a route. This applies to mission and quest objectives, survival guides, NPCs, zone lines, and ordinary point navigation.

The first acceptance case is the failed King Ranperre's Tomb route from addon coordinates `(-115.008, 218.328, -0.051)` to the Tombstone at `(1, -103.608, -1.419)`. Both the installed 2022 navmesh and the current upstream navmesh produce an approximately 52-yalm segment through a wall. The new planner must reject that segment using the installed zone DAT and find a collision-safe alternative when one exists.

## Non-goals

- Do not require the player to walk, record, draw, or visually inspect terrain.
- Do not infer walls from screenshots, OCR, wiki prose, repeated collision failures, or an online service when the installed collision model is available.
- Do not make enemy selection part of terrain replanning. Combat/enemy tracking remains independent and cannot move route progress backward or cause a route to oscillate.
- Do not automate targeting or interaction keys at doors, elevators, NPCs, or objectives.
- Do not use a direct internal game-function call as the first implementation when the installed collision bytes can answer the same static-terrain question safely.

## Confirmed evidence

- Zone 190 resolves to the installed model file `FINAL FANTASY XI\ROM\1\14.DAT`.
- The file is 9,536,304 bytes and contains an MZB collision chunk at offset `0xD6490` with a 3,319,424-byte payload, plus an RID chunk at offset `0x20`.
- The installed `King_Ranperres_Tomb.nav` is 716,964 bytes with SHA-256 `1EB704DA1D881D86B6EE65E839FAF7602AD03F0B059FF68EBBF1EC145C49F276`.
- The current upstream mesh is 606,524 bytes with SHA-256 `1A40D93521653C38135CDFAB3CCDDF225920B7F8E21E172FACD2685C23841702`.
- The installed mesh crosses the wall between native waypoints `(-136.382, -1.129, 202.791)` and `(-143.982, 6.071, 151.191)`. The current upstream mesh makes essentially the same shortcut between `(-137.282, -0.329, 202.491)` and `(-143.782, 6.271, 150.991)`.
- FFXINAV exposes coarse mesh operations but no triangle-level segment or capsule collision query. `GetDistanceToWall` returns only a scalar and cannot prove that an entire route segment is clear.
- The public [FFXI NavMesh Builder](https://github.com/LandSandBoat/FFXI-NavMesh-Builder) confirms that FFXI MZB/RID data contains the collision geometry needed to generate an OBJ. It is GPL-3.0; its behavior and output can be used as reference evidence, but its source will not be copied into the AccessXI helper unless the resulting licensing obligations are deliberately adopted.
- Official [Recast Navigation](https://github.com/recastnavigation/recastnavigation) provides a permissively licensed walkable-surface and pathfinding implementation. Its configuration controls topology, agent radius, step height, slope, and simplification, all of which can explain a bad prebuilt route.

## Selected approach

Add a 32-bit native library, `accessxi_collision_native.dll`, with three responsibilities:

1. Resolve and parse the exact installed collision DAT for a zone.
2. Build and cache a player-sized collision-safe navigation representation.
3. Answer bounded collision and path queries for the Lua addon without exposing native-owned pointers or stale result state.

The existing FFXINAV route may be used temporarily as a coarse candidate, but every candidate segment must pass the new DAT-backed capsule test. A rejected segment is never driven. The collision helper then computes the replacement path from its own walkable representation. FFXINAV is therefore a hint, not the authority.

Direct calls into the game's internal collision functions remain a fallback research path only. Existing Ghidra work identifies likely collision functions in `FFXiMain.unpacked.dll`, but their stable callable ABI and side effects are not proven. A version-fragile in-process game call will not be the foundation of navigation while the installed collision data is available directly.

## Architecture

### Exact zone asset resolution

- Resolve `zone_id -> model DAT` from the installed FFXI tables and zone metadata. Do not scan for similar filenames or select the first match.
- Open the lexical absolute path without following a caller-supplied reparse alias.
- Record the canonical path, file size, write-time identity, and SHA-256 of the bytes actually parsed.
- Recheck file identity after reading. A mutation or short read cancels the build.
- Parse chunks with strict bounds, type, count, offset, finite-number, and index validation. Malformed geometry fails the zone build without affecting other addon features.

### MZB and RID extraction

- Decode MZB collision vertices, triangle indices, normals, grid/quadtree references, visibility groups, and transformed submodels required by RID records.
- Preserve the source coordinate system internally and perform one explicit conversion at the API boundary. AccessXI uses `(x, z, y)` while native FFXI/Recast geometry uses `(X, Y, Z)`.
- Deduplicate only exact or deliberately epsilon-equivalent vertices. Never merge vertically separate floors merely because their horizontal coordinates overlap.
- Produce a diagnostic OBJ and a compact machine cache from the same accepted triangle set so a route failure can be reproduced without the live game.

### Collision structure

- Build a bounding-volume hierarchy over the original collision triangles.
- Provide segment, swept-sphere, and upright capsule queries. Route authorization uses the capsule query with a conservative player radius and height, not a center-line ray.
- Treat floor, wall, and ceiling contacts separately. A valid floor under the player does not make a segment valid when the capsule intersects a wall.
- Use exact start/end floor projection with bounded vertical tolerances. Overlapping floors, ramps, drops, and stair steps remain separate unless the agent's climb and slope limits connect them.

### Walkable path structure

- Build a tiled Recast/Detour navigation mesh from the accepted DAT collision triangles using explicitly versioned agent settings.
- Erode walkable space by the player radius, enforce maximum slope and climb, retain vertical layers, and avoid simplification that can move a portal across collision geometry.
- Query a polygon corridor and a straight path from the player's current floor to a reachable point inside the destination's normal arrival radius.
- Validate every returned straight segment with the original-triangle capsule sweep. If any segment fails, refine/rebuild locally or reject that candidate; never drive the failed shortcut.
- Every returned path includes its source DAT digest, cache/settings digest, zone ID, projected start/end floors, and path-generation number.

### Dynamic doors, gates, and elevators

Static DAT collision cannot establish whether a door is currently open or whether an elevator is at the required floor.

- Represent doors, gates, elevators, and other moving geometry as explicit transitions layered over the static path graph.
- Require the same live entity/transition evidence already used by AccessXI before crossing one of these links.
- A transition owns one exact, bounded portal through otherwise blocking static geometry. Only that portal segment may bypass the ordinary capsule-clear requirement, and only while the expected live door/elevator state and route ownership remain current.
- Stop at a collision-safe interaction point and speak the ordinary interaction instruction. Never press targeting or interaction keys automatically.
- Continue only after live position/state confirms the expected crossing. A timeout, wrong floor, wrong zone, or changed objective cancels that transition without damaging ordinary navigation.

### Addon integration

- Load the helper through LuaJIT FFI only after verifying the deployed DLL's exact pinned bytes.
- Begin zone loading when a zone becomes stable. DAT parsing and cache construction run on a native worker thread; Lua only polls status. No Lua callback occurs from the worker.
- Keep a newly requested route pending while its zone map is being built and speak once: `Mapping terrain for <zone>. Navigation will start automatically.`
- When the cache becomes ready, recompute from the player's current position rather than the position at request time.
- For every route type, prefer the collision-backed result. This is not limited to missions or quests.
- Preserve route ownership and objective/item progression behavior, but do not label a wiki-backed destination as unverified merely because the terrain cache was not ready.
- Replan only after a material off-route deviation or a confirmed blocked transition, with cooldown and hysteresis. Do not replan every frame, oscillate between floors, or repeatedly turn the player around.
- If the destination itself is not on a walkable surface, select the nearest collision-safe reachable point within its existing arrival radius. The semantic destination remains unchanged.

## Native ABI

The DLL exports a small C ABI using `cdecl`, fixed-width integers, finite 32-bit floats, caller-owned buffers, and opaque handles. No API returns a pointer to mutable native waypoint storage.

Proposed operations:

- `AXI_CreateContext` / `AXI_DestroyContext`
- `AXI_BeginLoadZone`
- `AXI_CancelLoad`
- `AXI_PollLoadZone`
- `AXI_GetLoadedZoneIdentity`
- `AXI_SweepCapsule`
- `AXI_FindPath`
- `AXI_CopyLastDiagnostic`

`AXI_FindPath` receives the opaque context, zone ID, current generation, start, destination, arrival radius, and a caller-owned fixed-capacity point buffer. It returns one status and one complete copied result. Buffer-too-small, stale generation, wrong zone, nonfinite coordinates, unavailable cache, or collision failure returns no drivable points.

All calls are serialized per context initially. The worker owns build-only state; query state becomes immutable only after an atomic generation swap.

## Cache and performance

- Cache files live under the addon's data/cache directory, not beside Square Enix DAT files.
- A cache key includes zone ID, exact DAT SHA-256, parser version, helper ABI version, Recast version, and every agent/build setting.
- Cache files have a magic value, schema version, bounded section table, payload digest, and exact source identity. Corrupt, partial, stale, or oversized caches are discarded and rebuilt.
- Write to a temporary file, flush, verify, and rename atomically.
- Prebuild known mission/quest and survival-guide zones during installation where practical. Build other zones lazily in the background.
- The Lua update loop only polls a small status structure. It never reads, hashes, parses, or builds a zone DAT on the game thread.
- Route queries have hard polygon, node, waypoint, time, and memory limits. A bounded failure is spoken once and logged with a reproducible diagnostic code.

## Failure behavior

- Cache building: keep the requested route pending and start automatically when ready.
- No collision-safe path: say `No collision-safe path was found to <destination>.` Do not steer straight through the wall.
- Helper/DAT/cache error: ordinary screen-reader and menu behavior stays responsive; stop only collision-backed movement and report the concrete error once.
- Zone change during build or route: cancel the old generation, load the new zone asynchronously, and never reuse old-zone waypoints.
- Game update: the DAT hash changes, the old cache is rejected, and a new one is built automatically.
- Helper update: the DLL/cache ABI or settings digest changes, so old cache data cannot be mixed with new query code.

## Verification

### Parser and geometry

- Parse the exact installed zone 190 DAT and reproduce stable triangle/vertex counts and bounds.
- Compare the diagnostic geometry against an independently produced reference OBJ for the same accepted bytes without copying GPL implementation code.
- Reject malformed chunk sizes, offsets, indices, transforms, NaN/infinite coordinates, truncated reads, reparse aliases, and mid-read file mutation.
- Prove coordinate round-trips for AccessXI `(x, z, y)` and native `(X, Y, Z)`.

### King Ranperre's Tomb acceptance case

- The exact approximately 52-yalm FFXINAV shortcut must collide with the DAT-backed player capsule.
- Neither the installed nor current upstream `.nav` shortcut may reach the steering layer.
- If a route exists, every segment of the replacement route must pass the original-triangle capsule sweep and reach an approach point inside the Tombstone arrival radius.
- The survival-guide destination in the same area must use the same collision-backed planner and must not loop or steer into the same wall.

### Runtime and stability

- Starting, polling, canceling, completing, failing, and replacing a background zone build must leave the Lua update loop responsive.
- A delayed zone transition must not freeze the addon or retain old-zone native state.
- Same-zone cache reuse must revalidate the exact DAT and DLL identities.
- Route deviation tests must prove stable floor selection, bounded replanning, and no left-right or forward-back oscillation.
- Door/elevator tests must prove no static shortcut is driven without its live transition.
- Existing mission, quest, inventory-progression, enemy-tracking, ordinary navigation, and speech tests must remain functional.
- Full reader and all new modules must pass the project's standalone Lua 5.1 syntax checker.
- Native x86 unit/integration tests, cache determinism, source/live byte identity, and a live addon smoke test are required before declaring completion.

## Deployment

- Add the x86 native target and its tests to the existing CMake build.
- Vendor Recast/Detour according to its license and record the exact revision.
- Include the helper DLL, licenses, cache schema metadata, and Lua adapter in the addon payload.
- Build and deploy the helper and updated addon files to `C:\Users\buu42\Ashita\addons\accessxi_reader`.
- Prebuild or trigger the zone 190 cache, verify deployed hashes, reload the addon, and exercise the King Ranperre's Tomb route in the live game.
- Keep the existing route recorder as a diagnostic tool, not as a requirement for producing terrain maps.

## Success criteria

The implementation is successful when AccessXI can derive a route from installed game collision data without sighted or manual mapping, the exact King Ranperre's Tomb wall shortcut is rejected before movement, a collision-safe alternative is driven when one exists, mission/quest and ordinary destinations use the same terrain authority, and zoning/cache construction does not freeze input or speech.
