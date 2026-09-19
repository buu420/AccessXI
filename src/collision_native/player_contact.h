#pragma once

// PLAYER BODY CONTACT RESOLUTION, PORTED FROM THE CURRENT CLIENT.
//
// A mathematical port of the September 2026 retail contact solver, so offline
// route auditing can ask the question the game asks: "with the player's body
// where it is, does the client push it, and to where?"  Static capsule and
// sphere clearance grids answered a different question -- whether a coordinate
// is free-standing -- and rejected hill ground the client accepts.
//
// EVIDENCE.  FFXiMain-20260910.unpacked.dll, SHA256
// e47ddc426b1c84b643732e615390507c75e56da46c1afd8c4794b238f84a752a.
//   FUN_1016F320  one triangle against the body sphere (the contact test)
//   FUN_1016F0E0  the resolve loop; its second phase is the settle iteration
//   FUN_1016F6C0  inside-triangle test, per-component signed products
//   FUN_1016F910  edge/sphere overlap fallback
// Decompilation and the constant dumps are in
// logs/2026-09-19-crawlers-nest/ghidra-current-wall-contact.txt,
// ghidra-current-wall-segment.txt, ghidra-current-contact-predicates.txt and
// ghidra-current-contact-constants*.txt.  No game bytes are reproduced here.
//
// TWO FRAMES, AND WHY IT MATTERS.  Mesh vertices are Y-UP; the client works
// Y-DOWN.  Reflecting Y (no vertex swap) is the whole conversion, and the
// branch constants were measured in the client's frame, so this port converts
// at the boundary and runs the comparisons natively.  The consequence is easy
// to get backwards: the client's "normal.y < -0.708" case is a Y-UP FLOOR, and
// it is the branch that moves the body.  Its "normal.y > +0.708" case is a real
// ceiling and only records a distance.
//
// WINDING. makePlayerContactTriangle() uses normalize(cross(b - a, c - a))
// in the mesh frame. Reflect that normal with the vertices; recomputing a
// cross product after reflecting Y would reverse its sign. This convention
// was checked against the current client's transformed Crawler's Nest faces.

#include "collision_native/collision_types.h"

#include <cstddef>
#include <span>

namespace accessxi::collision
{

// this+0x3412C, written as 0x3E800000 by FUN_1016F0E0 before every pass.
// A 0.5 yalm body sphere, centred a radius above the feet.
inline constexpr float kPlayerContactRadius = 0.5f;
inline constexpr float kPlayerContactRadiusSquared = 0.25f;

// FUN_1016F0E0 runs the contact pass at most four times; a fourth pass that
// still reports movement is a failure to resolve.
inline constexpr int kPlayerContactMaxPasses = 4;

// A triangle in the MESH frame (Y up). `normal` must be unit length and must
// follow the vertex winding -- use makePlayerContactTriangle().
struct PlayerContactTriangle final
{
    Vec3 a{};
    Vec3 b{};
    Vec3 c{};
    Vec3 normal{};
};

// normal = normalize(cross(b - a, c - a)). Returns false for a degenerate
// triangle, which the caller should drop: the client's plane projection divides
// by the squared normal and would produce nothing useful.
bool makePlayerContactTriangle(const Vec3& a, const Vec3& b, const Vec3& c, PlayerContactTriangle& out);

struct PlayerContactResult final
{
    // Corrected body centre, mesh frame (Y up). Equals the input when nothing
    // touched it.
    Vec3 center{};
    // False when a fourth pass still moved the body: the client would not have
    // settled here either.
    bool resolved = false;
    // this+0x34125, accumulated over the passes: a wall pushed the body.
    bool wallContact = false;
    // this+0x34126, accumulated. In the mesh frame this is a FLOOR (any surface
    // whose normal points away from the client's +Y), and it is the flag that
    // carries the vertical settlement.
    //
    // Accumulating is a deliberate addition: the client reads these after the
    // loop, so on a successful settle the last pass touched nothing and both are
    // always false. The resolved position is unaffected.
    bool groundContact = false;
    // Passes actually executed, 1..kPlayerContactMaxPasses.
    int passes = 0;
};

// Resolve the body centre against `triangles`.
//
// Mirrors the settle phase of FUN_1016F0E0: each pass tests every triangle
// against the SAME input centre and keeps the nearest wall candidate and the
// nearest floor/ceiling candidate separately, then adopts the result and runs
// again. Candidates are ordered by squared distance, not by triangle order.
PlayerContactResult resolvePlayerContact(
    std::span<const PlayerContactTriangle> triangles,
    const Vec3& center,
    float radiusSquared = kPlayerContactRadiusSquared);

struct PlayerSettleResult final
{
    // Corrected FEET position, mesh frame (Y up).
    Vec3 feet{};
    bool resolved = false;
    bool wallContact = false;
    bool groundContact = false;
    int passes = 0;
};

// Convenience wrapper for a standing body: lifts the feet by the radius to get
// the sphere centre, resolves, and lowers the result back to the feet.
PlayerSettleResult settlePlayerFeet(
    std::span<const PlayerContactTriangle> triangles,
    const Vec3& feet,
    float radius = kPlayerContactRadius);

}  // namespace accessxi::collision
