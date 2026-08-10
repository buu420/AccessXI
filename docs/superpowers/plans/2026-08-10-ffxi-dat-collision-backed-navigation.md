# FFXI DAT Collision-Backed Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and deploy an x86 collision-backed route planner that parses installed FFXI zone DAT geometry, rejects the exact King Ranperre's Tomb wall shortcut, finds player-sized safe paths, and supplies them to every AccessXI point route without freezing the addon.

**Architecture:** A native C++ DLL resolves and parses the installed MZB/RID collision model, builds immutable Bullet and Recast/Detour query state on a worker thread, and caches it by exact source/build hashes. A focused Lua module owns FFI, asynchronous route state, and point copying; `accessxi_reader.lua` asks it for every same-zone route before any legacy mesh route and polls pending builds until navigation starts automatically.

**Tech Stack:** C++20/Win32 x86, CMake 4.x, Recast/Detour commit `9f4ce64458dfae86e1239c525ddc219c4e9e06f1`, Bullet Collision commit `63c4d67e337017f9d8b298c900e9aabdb69296e7`, Windows BCrypt SHA-256, LuaJIT FFI, standalone Lua 5.1 tests, PowerShell deployment.

## Global Constraints

- Work only in the existing linked worktree `C:\Users\buu42\Documents\Codex\2026-08-08\accessxi-comprehensive-objectives\work\repo`; preserve all pre-existing dirty files and stage only task-owned paths or hunks.
- The native DLL and all tests must be Win32/x86 because Ashita and FFXINAV are 32-bit.
- No production behavior is added before its focused test has been run and failed for the expected missing behavior.
- Do not copy GPL-3.0 FFXI NavMesh Builder source into AccessXI. Its output is comparison evidence only.
- The route authority is the exact installed DAT geometry. A prebuilt `.nav`, wiki text, OCR, or a manual recording cannot authorize a segment through collision.
- The worker thread never calls Lua. Lua polls immutable status and query results.
- Enemy selection and combat state never alter terrain route progress.
- Static capsule collision may be bypassed only by one exact live-authorized door/elevator portal.
- Cache and route results bind zone ID, exact DAT SHA-256, parser schema, dependency revisions, agent settings, and generation.
- No route-building, DAT hashing, or cache parsing runs on the Lua update thread.
- Deployment must copy exact source bytes and built DLL into `C:\Users\buu42\Ashita\addons\accessxi_reader`, verify SHA-256 equality, and leave Square Enix files unchanged.

---

## File structure

### Native core

- `src/collision_native/collision_types.h`: finite coordinate types, mesh, identity, status, and build settings.
- `src/collision_native/rom_resolver.h/.cpp`: exact zone-model file ID and VTABLE/FTABLE resolution.
- `src/collision_native/file_snapshot.h/.cpp`: reparse-safe exact-byte reads, four-word identity, and SHA-256.
- `src/collision_native/mzb_parser.h/.cpp`: DAT chunk bounds, MZB decoding, grid geometry, RID model references, and coordinate conversion.
- `src/collision_native/collision_world.h/.cpp`: immutable Bullet triangle world and capsule sweep.
- `src/collision_native/recast_zone.h/.cpp`: tiled Recast build, Detour query, reachable endpoint selection, and per-segment sweep validation.
- `src/collision_native/cache_file.h/.cpp`: deterministic versioned cache serialization and verification.
- `src/collision_native/collision_context.h/.cpp`: background load/cancel/poll, atomic generation swap, serialized queries.
- `src/collision_native/collision_api.h`, `collision_exports.cpp`, `accessxi_collision_native.def`: stable C ABI.
- `src/collision_native/collision_probe.cpp`: offline installed-DAT probe and deterministic JSON diagnostics.

### Tests and tooling

- `tests/collision_rom_resolver_tests.cpp`
- `tests/collision_mzb_parser_tests.cpp`
- `tests/collision_world_tests.cpp`
- `tests/collision_recast_tests.cpp`
- `tests/collision_context_tests.cpp`
- `tools/fetch_collision_dependencies.ps1`
- `tools/build_collision_native.ps1`
- `tools/deploy_collision_navigation.ps1`
- `tools/test_collision_native.ps1`

### Addon

- `ashita/addons/accessxi_reader/modules/collision_navigation.lua`: FFI, manifest verification, async state, safe path copying, pending/error speech state.
- `ashita/addons/accessxi_reader/data/collision-native-manifest.tsv`: ABI, dependency revisions, DLL SHA-256, and settings digest.
- `tools/lua_tests/test_collision_navigation.lua`
- `tools/test_collision_navigation.ps1`
- `tools/lua_tests/test_collision_reader_integration.lua`
- `tools/test_collision_reader_integration.ps1`
- Modify `ashita/addons/accessxi_reader/accessxi_reader.lua` only at module bootstrap, route computation, pending-start handling, polling, zone reset, and unload.
- Modify installer payload scripts only after source/live integration is green.

---

### Task 1: Pin collision dependencies and create the x86 ABI skeleton

**Files:**
- Create: `tools/fetch_collision_dependencies.ps1`
- Create: `src/collision_native/collision_api.h`
- Create: `src/collision_native/collision_exports.cpp`
- Create: `src/collision_native/accessxi_collision_native.def`
- Create: `tests/collision_context_tests.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Produces: `AXI_GetAbiVersion() -> uint32_t`, `AXI_CreateContext() -> void*`, `AXI_DestroyContext(void*)`.
- Dependency roots: `external/recastnavigation` and `external/bullet3`, both ignored locally and checked against exact commits.

- [ ] **Step 1: Write the failing ABI test**

```cpp
int main() {
    CHECK(AXI_GetAbiVersion() == 1u);
    void* context = AXI_CreateContext();
    CHECK(context != nullptr);
    AXI_DestroyContext(context);
    return 0;
}
```

- [ ] **Step 2: Run the focused test and capture RED**

Run: `cmake -S . -B build-collision -A Win32 -DACCESSXI_COLLISION_ONLY=ON; if ($LASTEXITCODE -eq 0) { cmake --build build-collision --config Debug --target collision_context_tests }`

Expected: configuration or compilation fails because the collision target/API does not exist.

- [ ] **Step 3: Add the pinned fetch script and minimal ABI**

```powershell
$pins = @{
    recastnavigation = '9f4ce64458dfae86e1239c525ddc219c4e9e06f1'
    bullet3 = '63c4d67e337017f9d8b298c900e9aabdb69296e7'
}
```

The script clones only the official repositories, checks `git rev-parse HEAD` against each pin, and refuses a dirty or wrong checkout. CMake disables demos, examples, OpenGL, pybullet, extras, and upstream tests; it links static `Recast`, `Detour`, `BulletCollision`, and `LinearMath` into `accessxi_collision_native`.

- [ ] **Step 4: Build and run GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\fetch_collision_dependencies.ps1; cmake -S . -B build-collision -A Win32 -DACCESSXI_COLLISION_ONLY=ON; cmake --build build-collision --config Debug --target collision_context_tests; ctest --test-dir build-collision -C Debug -R collision_context_tests --output-on-failure`

Expected: one test passes and the built DLL is PE32/x86.

- [ ] **Step 5: Commit task-owned paths**

```powershell
git add CMakeLists.txt tools/fetch_collision_dependencies.ps1 src/collision_native/collision_api.h src/collision_native/collision_exports.cpp src/collision_native/accessxi_collision_native.def tests/collision_context_tests.cpp
git commit -m "build: add x86 collision navigation core"
```

### Task 2: Resolve and snapshot the exact installed zone DAT

**Files:**
- Create: `src/collision_native/collision_types.h`
- Create: `src/collision_native/rom_resolver.h/.cpp`
- Create: `src/collision_native/file_snapshot.h/.cpp`
- Create: `tests/collision_rom_resolver_tests.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Produces: `resolve_zone_model_dat(ffxi_root, zone_id) -> std::filesystem::path`.
- Produces: `read_stable_snapshot(path) -> FileSnapshot{canonical_path, bytes, size_low, size_high, write_time_low, write_time_high, sha256}`.

- [ ] **Step 1: Write installed-zone and mutation RED tests**

```cpp
const auto path = resolve_zone_model_dat(ffxi_root, 190);
CHECK(path == ffxi_root / L"ROM" / L"1" / L"14.DAT");
const auto snapshot = read_stable_snapshot(path);
CHECK(snapshot.bytes.size() == 9536304u);
CHECK(snapshot.sha256.size() == 64u);
```

Add synthetic VTABLE/FTABLE cases for base ROM and ROM2, missing table bytes, noncanonical roots, reparse components, short read, changed post-read identity, invalid zone, and the post-255 file-ID formula.

- [ ] **Step 2: Run RED**

Run: `cmake --build build-collision --config Debug --target collision_rom_resolver_tests && build-collision\Debug\collision_rom_resolver_tests.exe "C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI"`

Expected: compile fails because resolver/snapshot functions are absent.

- [ ] **Step 3: Implement exact resolver and stable handle read**

```cpp
const uint32_t file_id = zone_id < 256 ? zone_id + 100 : zone_id + 83635;
const uint8_t rom_index = vtable[file_id];
const uint16_t packed = read_u16(ftable, file_id * 2u);
const auto relative = rom_index == 1
    ? path(L"ROM") / number(packed >> 7) / (number(packed & 0x7f) + L".DAT")
    : path(L"ROM" + number(rom_index)) / number(packed >> 7) / (number(packed & 0x7f) + L".DAT");
```

Use one `CreateFileW` handle with `FILE_SHARE_READ`, reject reparse components before resolution, hash the accepted byte buffer with BCrypt, and compare exact file information before/after reading.

- [ ] **Step 4: Run GREEN and parser-independent file checks**

Run the command from Step 2 and `git diff --check -- src/collision_native tests/collision_rom_resolver_tests.cpp`.

- [ ] **Step 5: Commit**

```powershell
git add src/collision_native/collision_types.h src/collision_native/rom_resolver.* src/collision_native/file_snapshot.* tests/collision_rom_resolver_tests.cpp CMakeLists.txt
git commit -m "feat: resolve exact installed zone collision DAT"
```

### Task 3: Decode MZB collision geometry and prove the Tomb shortcut intersects it

**Files:**
- Create: `src/collision_native/mzb_parser.h/.cpp`
- Create: `src/collision_native/mzb_key_table.h`
- Create: `tests/collision_mzb_parser_tests.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Produces: `parse_zone_collision(FileSnapshot, zone_id, resolver) -> ParsedZoneMesh`.
- `ParsedZoneMesh` owns finite `Vec3` vertices, `uint32_t[3]` triangles, source identities, bounds, and diagnostic counts.

- [ ] **Step 1: Write synthetic bounds RED and real zone-190 RED**

```cpp
const auto mesh = parse_zone_collision(snapshot, 190, resolver);
CHECK(mesh.vertices.size() == 193918u);
CHECK(mesh.triangles.size() == 216349u);
CHECK(mesh.bounds.min.x < -278.7f);
CHECK(mesh.bounds.max.z > 349.9f);
CHECK(segment_intersection_count(mesh,
    {-136.382f, -1.129f, 202.791f},
    {-143.982f, 6.071f, 151.191f}) >= 1u);
```

Synthetic cases cover truncated chunk headers, size overflow, missing MZB, invalid decode length/node count, grid/list loops, offsets outside the accepted buffer, invalid matrix/vertex floats, index overflow, and duplicate geometry references.

- [ ] **Step 2: Run RED**

Run: `cmake --build build-collision --config Debug --target collision_mzb_parser_tests && build-collision\Debug\collision_mzb_parser_tests.exe "C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI"`

Expected: compile fails because `parse_zone_collision` does not exist.

- [ ] **Step 3: Implement strict chunk/MZB/RID parsing**

Parse each 16-byte DAT chunk using `type = value & 0x7f` and `payload_size = 16 * ((value >> 7) & 0x7ffff) - 16`. Decode MZB XOR ranges, grid entries, transform matrices, vertex arrays, and triangle arrays using checked reads. Deduplicate identical `(visibility_offset, geometry_offset)` pairs deterministically. Resolve RID model references through the same resolver and apply their finite scale/rotation/translation before appending their geometry.

- [ ] **Step 4: Run GREEN and record stable zone-190 counts**

Run the Step 2 command twice; require identical counts and bounds both times.

- [ ] **Step 5: Commit**

```powershell
git add src/collision_native/mzb_parser.* src/collision_native/mzb_key_table.h tests/collision_mzb_parser_tests.cpp CMakeLists.txt
git commit -m "feat: decode FFXI MZB collision geometry"
```

### Task 4: Add player-capsule collision and reject both known bad Tomb segments

**Files:**
- Create: `src/collision_native/collision_world.h/.cpp`
- Create: `tests/collision_world_tests.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Produces: `CollisionWorld::sweep_capsule(start, end, radius, height) -> SweepResult{clear, fraction, point, normal, triangle_index}`.

- [ ] **Step 1: Write synthetic wall/floor RED and exact real-DAT RED**

```cpp
CollisionWorld world(mesh);
CHECK_FALSE(world.sweep_capsule(
    {-136.382f, -1.129f, 202.791f},
    {-143.982f, 6.071f, 151.191f}, 0.40f, 1.80f).clear);
CHECK_FALSE(world.sweep_capsule(
    {-137.282f, -0.329f, 202.491f},
    {-143.782f, 6.271f, 150.991f}, 0.40f, 1.80f).clear);
```

Also prove a horizontal corridor wider than the capsule passes, a too-narrow corridor blocks, support-floor contact does not count as a wall, nonfinite input rejects, start penetration rejects, and zero/oversized dimensions reject.

- [ ] **Step 2: Run RED**

Run: `cmake --build build-collision --config Debug --target collision_world_tests && build-collision\Debug\collision_world_tests.exe "C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI"`

Expected: compile fails because `CollisionWorld` does not exist.

- [ ] **Step 3: Implement immutable Bullet collision world**

Create `btTriangleIndexVertexArray`, `btBvhTriangleMeshShape`, and one static collision object from immutable mesh storage. Sweep `btCapsuleShape(radius, height - 2*radius)` along Y-up transforms whose origins are `feet_y + height/2`. Filter initial supporting-floor contact by walkable normal and penetration tolerance, but never filter lateral/ceiling contact.

- [ ] **Step 4: Run GREEN**

Run the Step 2 command and require the two real shortcuts to report a hit before fraction `1.0`.

- [ ] **Step 5: Commit**

```powershell
git add src/collision_native/collision_world.* tests/collision_world_tests.cpp CMakeLists.txt
git commit -m "feat: validate routes with DAT-backed capsule sweeps"
```

### Task 5: Build a conservative Recast route and validate every segment

**Files:**
- Create: `src/collision_native/recast_zone.h/.cpp`
- Create: `tests/collision_recast_tests.cpp`
- Modify: `CMakeLists.txt`

**Interfaces:**
- Produces: `RecastZone::find_path(start, destination, arrival_radius, maximum_points) -> PathResult`.
- `PathResult` includes copied points, exact projected endpoints, total length, DAT/settings digests, and generation.

- [ ] **Step 1: Write small synthetic route RED and Tomb acceptance RED**

```cpp
const auto path = zone.find_path(
    {-115.008f, -0.051f, 218.328f},
    {1.000f, -1.419f, -103.608f}, 8.0f, 512u);
CHECK(path.status == PathStatus::ready);
CHECK(path.points.size() > 2u);
for (size_t i = 1; i < path.points.size(); ++i) {
    CHECK(world.sweep_capsule(path.points[i-1], path.points[i], 0.40f, 1.80f).clear);
}
CHECK(polyline_does_not_contain_segment(path.points,
    {-136.382f, -1.129f, 202.791f},
    {-143.982f, 6.071f, 151.191f}));
```

Synthetic fixtures prove radius erosion, stairs within climb, ledges above climb, slopes above limit, vertically overlapping floors, unreachable islands, endpoint approach inside arrival radius, waypoint cap, and deterministic repeated output.

- [ ] **Step 2: Run RED**

Run: `cmake --build build-collision --config Release --target collision_recast_tests && build-collision\Release\collision_recast_tests.exe "C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI"`

Expected: compile fails because `RecastZone` does not exist.

- [ ] **Step 3: Implement tiled Recast/Detour state**

Use Y-up geometry, `agent_radius=0.40`, `agent_height=1.80`, `max_climb=0.60`, `max_slope=50`, `cell_size=0.20`, `cell_height=0.10`, and `tile_size=128`; encode every setting into `settings_digest`. Build deterministic tiles, find nearest start/end polygons with bounded extents, obtain corridor/straight-path points, then reject the entire result if any original-triangle capsule sweep fails. Search deterministic endpoint samples only within the destination arrival radius.

- [ ] **Step 4: Run GREEN and write the offline diagnostic JSON**

Run the Step 2 command twice and compare serialized point bytes. Record hit details for the rejected old segment and every accepted replacement segment.

- [ ] **Step 5: Commit**

```powershell
git add src/collision_native/recast_zone.* tests/collision_recast_tests.cpp CMakeLists.txt
git commit -m "feat: generate collision-safe FFXI routes"
```

### Task 6: Add deterministic cache, asynchronous context, C ABI, and probe

**Files:**
- Create: `src/collision_native/cache_file.h/.cpp`
- Create: `src/collision_native/collision_context.h/.cpp`
- Create: `src/collision_native/collision_probe.cpp`
- Create: `tests/collision_context_tests.cpp`
- Modify: `src/collision_native/collision_api.h`
- Modify: `src/collision_native/collision_exports.cpp`
- Modify: `src/collision_native/accessxi_collision_native.def`
- Create: `tools/build_collision_native.ps1`
- Create: `tools/test_collision_native.ps1`
- Modify: `CMakeLists.txt`

**Interfaces:**

```c
int32_t __cdecl AXI_BeginLoadZone(void*, uint32_t zone, const wchar_t* ffxi_root, const wchar_t* cache_root, uint64_t* generation);
int32_t __cdecl AXI_CancelLoad(void*, uint64_t generation);
int32_t __cdecl AXI_PollLoadZone(void*, uint64_t generation, AXILoadStatus* out_status);
int32_t __cdecl AXI_SweepCapsule(void*, uint64_t generation, AXIVec3 start, AXIVec3 end, float radius, float height, AXISweepResult* out_result);
int32_t __cdecl AXI_FindPath(void*, uint64_t generation, AXIVec3 start, AXIVec3 end, float arrival_radius, AXIPathPoint* points, uint32_t capacity, AXIPathResult* out_result);
```

- [ ] **Step 1: Write lifecycle/cache RED**

Test pending-to-ready, cancellation, new generation replacing old, wrong-zone/stale-generation rejection, immutable query state, concurrent poll/query, exact deterministic cache bytes, corrupted/truncated/oversized cache rejection, DAT mutation invalidation, settings-version invalidation, and temporary-file cleanup.

- [ ] **Step 2: Run RED**

Run: `cmake --build build-collision --config Release --target collision_context_tests && ctest --test-dir build-collision -C Release -R collision_context_tests --output-on-failure`

Expected: tests fail at absent async/cache operations.

- [ ] **Step 3: Implement worker/context/cache/probe**

Use one `std::jthread` per context, cancellation tokens between bounded build stages, private build state, and one mutex-protected immutable shared zone generation. Cache writes use a sibling temporary file followed by flush, reopen verification, and atomic `MoveFileExW`. `accessxi_collision_probe` loads zone 190, queries the known shortcut and final route, and emits deterministic JSON without native pointers.

- [ ] **Step 4: Run GREEN and x86 build wrapper**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_collision_native.ps1`

Expected: all native tests pass, the probe reports both shortcuts blocked, and the replacement path has only clear segments.

- [ ] **Step 5: Commit**

```powershell
git add src/collision_native/cache_file.* src/collision_native/collision_context.* src/collision_native/collision_probe.cpp src/collision_native/collision_api.h src/collision_native/collision_exports.cpp src/collision_native/accessxi_collision_native.def tests/collision_context_tests.cpp tools/build_collision_native.ps1 tools/test_collision_native.ps1 CMakeLists.txt
git commit -m "feat: expose asynchronous collision route service"
```

### Task 7: Add the Lua collision-navigation adapter

**Files:**
- Create: `ashita/addons/accessxi_reader/modules/collision_navigation.lua`
- Create: `ashita/addons/accessxi_reader/data/collision-native-manifest.tsv`
- Create: `tools/lua_tests/test_collision_navigation.lua`
- Create: `tools/test_collision_navigation.ps1`

**Interfaces:**
- Produces: `collision_navigation.new(deps) -> state`.
- Produces: `state:route(player, destination) -> points_or_nil, mode, message` where mode is `ready`, `pending`, or `error`.
- Produces: `state:poll(player)`, `state:cancel(reason)`, `state:shutdown()`.

- [ ] **Step 1: Write Lua RED with a fake ABI table**

```lua
local points, mode, message = state:route(player, destination)
assert(points == nil and mode == 'pending')
assert(message == 'Mapping terrain for King Ranperre\'s Tomb. Navigation will start automatically.')
native:complete_build()
points, mode = state:route(player, destination)
assert(mode == 'ready' and #points > 2)
assert(points[1].source == 'dat-collision')
```

Also test manifest/DLL hash mismatch before `ffi.load`, ABI mismatch, bad/nonfinite/copied points, capacity overflow, stale generation, wrong zone, owner-independent terrain input, speech-once pending state, cancellation on zone change, and shutdown.

- [ ] **Step 2: Run RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_collision_navigation.ps1`

Expected: failure because `collision_navigation.lua` is missing.

- [ ] **Step 3: Implement minimal adapter**

The module verifies the one canonical manifest and exact DLL bytes with `accessxi_sha256`, loads the C ABI, owns one context, converts AccessXI `(x,z,y)` to native `(X,Y,Z)` exactly once, copies every point into fresh Lua tables, and never returns partial/stale native data.

- [ ] **Step 4: Run GREEN and syntax**

Run: `tools\lua51\lua5.1.exe -e "assert(loadfile('ashita/addons/accessxi_reader/modules/collision_navigation.lua'))"; powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_collision_navigation.ps1`

- [ ] **Step 5: Commit new adapter files**

```powershell
git add ashita/addons/accessxi_reader/modules/collision_navigation.lua ashita/addons/accessxi_reader/data/collision-native-manifest.tsv tools/lua_tests/test_collision_navigation.lua tools/test_collision_navigation.ps1
git commit -m "feat: add asynchronous collision navigation adapter"
```

### Task 8: Route every AccessXI point through collision geometry

**Files:**
- Create: `tools/lua_tests/test_collision_reader_integration.lua`
- Create: `tools/test_collision_reader_integration.ps1`
- Modify: `ashita/addons/accessxi_reader/accessxi_reader.lua`

**Interfaces:**
- Consumes: `state:route`, `poll`, `cancel`, `shutdown` from Task 7.
- Produces: pending route start, automatic ready activation, collision-safe replans, and exact zone reset.

- [ ] **Step 1: Write extracted-reader RED**

The test extracts the real bootstrap, `nav_compute_route_with_zoneline_approach`, menu start, route poll, zone reset, and unload blocks. It asserts:

```lua
local route = accessxi.nav_compute_route_with_zoneline_approach(player, tombstone)
assert(#route == 0 and accessxi.nav_collision_route_pending ~= nil)
nav_menu_start_route()
assert(accessxi.nav_active == true)
assert(spoken[#spoken] == 'Mapping terrain for King Ranperre\'s Tomb. Navigation will start automatically.')
collision_state:complete_with(safe_points)
poll_nav_route()
assert(accessxi.nav_active == true and #accessxi.nav_route_points == #safe_points)
assert(ffxinav_find_calls == 0)
```

Add ordinary survival-guide, mission, quest, NPC, zoneline approach, enemy-selection-no-replan, deviation cooldown, pending zone change, native error, and unload cases. Explicit live door/elevator transitions retain their separate path.

- [ ] **Step 2: Run RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_collision_reader_integration.ps1`

Expected: first route calls legacy mesh or blocks instead of entering collision pending state.

- [ ] **Step 3: Integrate the adapter at the narrow seams**

Load the module during navigation bootstrap. After an exact live door/elevator/other explicit transition has claimed the leg, call collision state at the first generic same-zone route seam before recorded or legacy mesh selection. `ready` returns only copied `dat-collision` points; `pending` stores the exact destination and generation; `error` sets one concrete failure reason and never falls through to a wall-crossing direct route. Menu start keeps pending navigation alive. Poll starts automatically on ready, while deviation replans use a 1.2-second minimum cooldown and material horizontal/vertical thresholds. Zone reset and unload cancel/destroy the context.

- [ ] **Step 4: Run GREEN plus existing focused navigation suites**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_collision_reader_integration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_mission_quest_navigation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_nav_mesh_endpoint_approach.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_nav_door_interaction_prompt.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_nav_metalworks_elevator.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_nav_enemy_camps.ps1
tools\lua51\lua5.1.exe -e "assert(loadfile('ashita/addons/accessxi_reader/accessxi_reader.lua'))"
```

- [ ] **Step 5: Preserve overlapping worktree edits**

Do not stage the whole reader file while unrelated edits remain. Save the exact Task 8 patch under `artifacts/collision-reader-integration.patch` for auditability and leave the working reader uncommitted unless all pre-existing changes have independently become commit-ready.

### Task 9: Package, deploy, and verify the installed game route

**Files:**
- Create: `tools/deploy_collision_navigation.ps1`
- Modify: installer payload/build scripts that enumerate addon modules, data files, and native dependencies.
- Modify: `ashita/addons/accessxi_reader/data/collision-native-manifest.tsv` with the Release DLL hash.

**Interfaces:**
- Produces: source/live byte-identical Lua/data plus x86 `accessxi_collision_native.dll` in the live addon's `third_party\collision` directory.

- [ ] **Step 1: Write deployment RED**

The deployment test stages a fake DLL/module/manifest, asserts exact allowlisted destinations and backups, rejects a running copy/locked DLL, rejects source-stage hash drift, and proves no Square Enix DAT/executable path is writable by the script.

- [ ] **Step 2: Run RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_deploy_collision_navigation.ps1`

Expected: failure because deployment tooling does not exist.

- [ ] **Step 3: Implement build/package/deploy**

Build Release x86, generate the manifest from exact DLL bytes and pinned dependency commits, prebuild zone 190 into a temporary cache, verify it by reopening, back up live addon files, copy only allowlisted files, and compare SHA-256 source/stage/live. Never write under `FINAL FANTASY XI\ROM*`.

- [ ] **Step 4: Run the full concrete verification gate**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_collision_native.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_collision_navigation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_collision_reader_integration.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_deploy_collision_navigation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\deploy_collision_navigation.ps1
```

Then run the deployed probe against zone 190 and require: both known 52-yalm shortcuts blocked, replacement path ready, every segment capsule-clear, source/live manifest and Lua hashes equal, deployed DLL hash equal to manifest, and no addon-thread build work.

- [ ] **Step 5: Live smoke and handoff**

Reload the addon. Start the Tombstone and survival-guide routes in King Ranperre's Tomb. Confirm logs show zone 190 DAT/cache identity, collision-backed waypoint count, no legacy FFXINAV route call, no wall-hit loop, no enemy-selection replan, and no zoning/input freeze. Report exact source commit(s), deployed paths, hashes, cache identity, test counts, and any live behavior still awaiting the user's play test.

---

## Plan self-review

- Spec coverage: exact DAT resolution, MZB/RID, capsule BVH, conservative Recast path, dynamic transitions, async cache, generic addon integration, King Ranperre's Tomb regression, performance, failure behavior, packaging, and deployment each map to Tasks 2–9.
- Placeholder scan: no task defers unspecified work; every behavior has an exact file, interface, RED command, implementation boundary, and GREEN command.
- Type consistency: native coordinates are `AXIVec3{X,Y,Z}`; Lua converts from `{x,z,y}` once; `generation` is `uint64_t`; path points are always caller-owned/native-copied then Lua-deep-copied; route modes are exactly `ready`, `pending`, and `error`.
- Scope: the native parser/collision/path service, Lua adapter, reader integration, and deployment are sequentially dependent, so one implementation plan is appropriate. Doors/elevators use the already separate transition subsystem rather than creating another independent feature.
