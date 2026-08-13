# Mhaura Rank-2 Collision Transform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parse Mhaura's valid planar collision instances, build its navigation terrain, and produce a fully capsule-validated route to Buburimu Peninsula.

**Architecture:** Move validity from the instance determinant to transformed triangle geometry. Stage one instance's vertices and surviving triangles transactionally, retain valid rank-2 surfaces, omit only collapsed triangles, and append the instance only when at least one triangle survives. Rebuild the deterministic native DLL and update its manifest as one reviewed artifact change.

**Tech Stack:** C++20, MSVC Win32, CMake, Recast/Detour, Bullet, PowerShell.

## Global Constraints

- Never publish partial terrain and never use FFXINAV when collision parsing is failed or partial.
- A transformed triangle collapses only at `normalLengthSquared <= 1e-12 * max(maxEdgeSquared, 1)^2` or on nonfinite geometry.
- Nonsingular winding remains determinant-based. Singular winding reverses only when `normal.y < -1e-6 * sqrt(normalLengthSquared)`.
- The installed Mhaura DAT SHA-256 is `43ed3f17ccfdb1092af9bed77ceaf54ece101bfb94764717fd4b37992f3bdc25`.
- Release DLLs must contain `IMAGE_DEBUG_TYPE_REPRO`, match the ABI-3 manifest, and be byte-identical across independent builds with the same toolchain.

---

### Task 1: Rank-2 triangle preservation and Mhaura route proof

**Files:**
- Modify: `src/collision_native/mzb_parser.h`
- Modify: `src/collision_native/mzb_parser.cpp:185-275`
- Modify: `tests/collision_mzb_parser_tests.cpp`
- Modify: `tests/collision_recast_tests.cpp`
- Modify: `ashita/addons/accessxi_reader/data/collision-native-manifest.tsv`

**Interfaces:**
- Produces internal enum `TriangleDisposition { keep, flip, collapsed }` and pure function `classify_transformed_triangle(const Vec3& a, const Vec3& b, const Vec3& c, bool singular, float determinant) -> TriangleDisposition` in `mzb_parser.h`; production parsing and synthetic tests call the same function.
- `parse_zone_collision(snapshot, 249u) -> ParsedZoneMesh` must return the complete zone.
- Existing `build_zone_navigation(mesh, settings, stop_token)` and capsule sweep APIs remain unchanged.
- The DLL ABI remains version 3 and the settings digest remains unchanged.

- [ ] **Step 1: Add installed Mhaura RED coverage**

Extend `collision_mzb_parser_tests.cpp` with `run_installed_mhaura_test`. Assert the source hash, zone ID, `geometry_instances == 3010`, `vertices.size() == 31318`, `triangles.size() == 34885`, and bounds within `0.001f` of:

```cpp
Vec3{-83.787917f, -1.041260f, -40.0f}
Vec3{80.0f, 61.357300f, 195.247002f}
```

Assert six triangles occupy the three known planar quads around native/log X/Z `-20..-24` and `13..24`, and each has area approximately `4.0f`. Add a pure synthetic classification fixture for a rank-2 planar quad and a rank-1 collapsed triangle; the former must survive and the latter must be omitted without contributing vertices.

- [ ] **Step 2: Add the end-to-end Mhaura route RED**

Extend `collision_recast_tests.cpp` to parse zone 249, build its navigation, and query from game coordinates `(-12.750,86.286,-15.791)` to `(-0.179,121.015,-8.549)`, converting vertical coordinates exactly as existing zone-244 tests do. Require at least two finite route points and validate every emitted segment with the same player-sized capsule and raised-step policy used in production.

- [ ] **Step 3: Run RED**

Run:

```powershell
cmake --build .\build-collision --config Release --target collision_mzb_parser_tests collision_recast_tests
& .\build-collision\bin\Release\collision_mzb_parser_tests.exe 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI'
```

Expected: the parser test fails with `MZB transform is singular` before production changes.

- [ ] **Step 4: Implement transactional per-triangle validation**

Remove only the determinant-zero throw. Stage transformed vertices for the current instance, calculate each referenced triangle's edges and cross product, reject nonfinite/collapsed triangles, and keep surviving triangle indices. For nonsingular transforms retain the current determinant swap. For singular transforms use the specified normalized-Y threshold. Append staged vertices and triangles only when at least one triangle survives; increment `geometry_instances` only for an appended instance.

Use this scale calculation verbatim:

```cpp
const float max_edge_squared = std::max({length_squared(ab), length_squared(ac), length_squared(bc), 1.0f});
const float collapse_limit = 1.0e-12f * max_edge_squared * max_edge_squared;
```

- [ ] **Step 5: Run focused GREEN and the full native collision suite**

Run:

```powershell
cmake --build .\build-collision --config Release --target collision_context_tests collision_rom_resolver_tests collision_mzb_parser_tests collision_world_tests collision_recast_tests accessxi_collision_native
ctest --test-dir .\build-collision -C Release -R '^collision_' --output-on-failure
```

Expected: all five collision tests pass, including the installed Mhaura parse and route.

- [ ] **Step 6: Update and prove the deterministic release artifact**

Hash `build-collision\bin\Release\accessxi_collision_native.dll`, replace only the manifest SHA-256 field, then invoke the canonical build script. Configure a second clean build directory and require identical hashes:

```powershell
& .\tools\build_collision_native.ps1 -RepoRoot $PWD -Configuration Release
cmake -S . -B .\build-collision-mhaura-repro -A Win32 -DACCESSXI_COLLISION_ONLY=ON
cmake --build .\build-collision-mhaura-repro --config Release --target accessxi_collision_native
& .\tools\test_collision_native_reproducible.ps1 -RepoRoot $PWD -DllPath .\build-collision-mhaura-repro\bin\Release\accessxi_collision_native.dll -ManifestPath .\ashita\addons\accessxi_reader\data\collision-native-manifest.tsv
```

Expected: canonical build, stage, manifest, and independent build hashes are identical; ABI remains 3 and settings digest remains unchanged.

- [ ] **Step 7: Commit the native change**

```powershell
git diff --check
git add src/collision_native/mzb_parser.h src/collision_native/mzb_parser.cpp tests/collision_mzb_parser_tests.cpp tests/collision_recast_tests.cpp ashita/addons/accessxi_reader/data/collision-native-manifest.tsv
git commit -m "fix: preserve planar Mhaura collision geometry"
```
