#include "collision_native/player_contact.h"

#include <cmath>

namespace accessxi::collision
{
namespace
{

// Constants read out of the current client. Addresses are the data symbols the
// decompilation names; the dumps are in
// logs/2026-09-19-crawlers-nest/ghidra-current-contact-constants*.txt.
constexpr float kZero = 0.0f;               // _DAT_103295D8
constexpr float kOne = 1.0f;                // _DAT_1032961C
constexpr float kInsideEpsilon = 1.0e-4f;   // _DAT_1032A1A8, 0x38D1B717
constexpr float kContactEpsilon = 1.0e-3f;  // _DAT_1032A22C, 0x3A83126F
constexpr float kWallNormalY = 0.708f;      // _DAT_1033663C / _DAT_10336638
constexpr float kWallYScale = 0.2f;         // _DAT_1032A39C, 0x3E4CCCCD
constexpr float kFloorVertexSlack = 0.3f;   // _DAT_1032B15C, 0x3E99999A
constexpr float kWallVertexSlack = 0.002f;  // _DAT_10336648, 0x3B03126F
constexpr float kGroundDrop = 0.5f;         // _DAT_10329A08, 0x3F000000
constexpr float kFarSentinel = 9999999.0f;  // 0x4B18967F, written to +0x34130/4

// Y is the only axis that differs between the mesh frame and the client's.
constexpr Vec3 reflectY(const Vec3& v) noexcept
{
    return Vec3{v.x, -v.y, v.z};
}

struct NativeTriangle final
{
    Vec3 a{};
    Vec3 b{};
    Vec3 c{};
    Vec3 normal{};
};

// FUN_1016F0E0 keeps this state on the collision context; the offsets are in
// the comments so the port can be re-checked against the decompilation.
struct ContactState final
{
    float radiusSquared = kPlayerContactRadiusSquared;  // +0x3412C
    float nearestWall = kFarSentinel;                   // +0x34130
    float nearestFloor = kFarSentinel;                  // +0x34134
    Vec3 corrected{};                                   // +0x341AC..+0x341B4
    bool wallHit = false;                               // +0x34125
    bool groundHit = false;                             // +0x34126
};

// FUN_1016F6C0. For each edge, the three components of cross(edge, point - edge
// start) are each multiplied by the MATCHING normal component and must all fall
// at or below the epsilon. This is deliberately per-component and is stricter
// than a single dot product; the client is what it is.
bool insideTriangle(const NativeTriangle& t, const Vec3& point) noexcept
{
    const auto edge = [&](const Vec3& start, const Vec3& end) noexcept {
        const float ux = end.x - start.x;
        const float uy = end.y - start.y;
        const float uz = end.z - start.z;
        const float vx = point.x - start.x;
        const float vy = point.y - start.y;
        const float vz = point.z - start.z;
        return (uy * vz - uz * vy) * t.normal.x <= kInsideEpsilon
            && (uz * vx - ux * vz) * t.normal.y <= kInsideEpsilon
            && (ux * vy - uy * vx) * t.normal.z <= kInsideEpsilon;
    };
    return edge(t.a, t.b) && edge(t.b, t.c) && edge(t.c, t.a);
}

// FUN_1016F910. The body sphere may overlap an edge even when the plane
// projection lands outside the triangle, which is what keeps the player from
// slipping through a seam between two faces.
bool edgeOverlapsSphere(const Vec3& start, const Vec3& end, const Vec3& center, float radiusSquared) noexcept
{
    const float dx = center.x - start.x;
    const float dy = center.y - start.y;
    const float dz = center.z - start.z;
    const float ex = end.x - start.x;
    const float ey = end.y - start.y;
    const float ez = end.z - start.z;
    const float length = std::sqrt(ex * ex + ey * ey + ez * ez);
    // The client divides by this without checking. A zero-length edge belongs to
    // a degenerate triangle the caller should already have dropped; refusing it
    // here keeps the port free of a division by zero.
    if (length == kZero)
    {
        return false;
    }
    const float inverse = kOne / length;
    const float along = inverse * ex * dx + inverse * ey * dy + inverse * ez * dz;
    if (along < kZero)
    {
        return false;
    }
    if (length < along)
    {
        return false;
    }
    const float perpendicularSquared = (dx * dx + dy * dy + dz * dz) - along * along;
    return !(radiusSquared - perpendicularSquared < kZero);
}

// FUN_1016F320, with the sweep flag (+0x34124) clear -- which is how the settle
// phase of FUN_1016F0E0 always calls it, so the front-face gate on the
// triangle's +0x2C scalar is satisfied unconditionally and is not modelled.
void applyTriangle(ContactState& state, const NativeTriangle& t, const Vec3& center) noexcept
{
    const Vec3& n = t.normal;
    const float normalSquared = n.z * n.z + n.y * n.y + n.x * n.x;
    if (normalSquared == kZero)
    {
        return;
    }

    // Nearest point on the triangle's plane. The client scales by the squared
    // normal rather than assuming unit length.
    const float scale = ((t.a.y - center.y) * n.y + (t.a.z - center.z) * n.z + (t.a.x - center.x) * n.x)
        / normalSquared;
    const Vec3 projected{scale * n.x + center.x, scale * n.y + center.y, scale * n.z + center.z};

    const bool touching = insideTriangle(t, projected)
        || edgeOverlapsSphere(t.a, t.b, center, state.radiusSquared)
        || edgeOverlapsSphere(t.b, t.c, center, state.radiusSquared)
        || edgeOverlapsSphere(t.c, t.a, center, state.radiusSquared);
    if (!touching)
    {
        return;
    }

    const float ox = projected.x - center.x;
    const float oy = projected.y - center.y;
    const float oz = projected.z - center.z;
    const float distanceSquared = ox * ox + oy * oy + oz * oz;
    if (!(distanceSquared <= state.radiusSquared - kContactEpsilon))
    {
        return;
    }

    if (n.y > kWallNormalY || n.y < -kWallNormalY)
    {
        // Floor or ceiling in the client's frame. Only the nearest one counts,
        // and at least one vertex must sit above the body's slack line.
        if (distanceSquared < state.nearestFloor)
        {
            const float above = center.y - kFloorVertexSlack;
            if (above < t.a.y || above < t.b.y || above < t.c.y)
            {
                // n.y < 0 in the client's frame is a MESH-FRAME FLOOR. This is
                // the vertical settlement: drop the centre one radius clear of
                // the plane it is standing on.
                if (n.y < kZero)
                {
                    state.corrected.y = projected.y - kGroundDrop;
                    state.groundHit = true;
                }
                state.nearestFloor = distanceSquared;
            }
        }
        return;
    }

    // Wall. At least one vertex must sit below the body, so a lip overhead is
    // not treated as something to be pushed off.
    if (distanceSquared >= state.nearestWall)
    {
        return;
    }
    const float below = center.y - kWallVertexSlack;
    if (!(t.a.y < below || t.b.y < below || t.c.y < below))
    {
        return;
    }

    const float outX = center.x - projected.x;
    const float outY = center.y - projected.y;
    const float outZ = center.z - projected.z;
    const float outSquared = outX * outX + outY * outY + outZ * outZ;
    if (outSquared == kZero)
    {
        return;
    }
    const float inverse = kOne / std::sqrt(outSquared);
    // Front-facing guard: the body must already be on the normal's side, or the
    // client refuses to move it. Without this the solver would happily drag the
    // player through the back of a wall.
    if (kZero > inverse * outX * n.x + outY * inverse * n.y + inverse * outZ * n.z)
    {
        return;
    }

    // The original penetration depth: sqrt(r^2 - d^2), not r - d. It is the
    // half-chord of the sphere at the contact plane. Using r - d here would
    // underestimate the client's correction for a penetrating body.
    const float push = std::sqrt(state.radiusSquared - distanceSquared);
    state.corrected.x = inverse * outX * push + center.x;
    state.corrected.y = outY * inverse * push * kWallYScale + center.y;
    state.corrected.z = push * inverse * outZ + center.z;
    state.wallHit = true;
    state.nearestWall = distanceSquared;
}

}  // namespace

bool makePlayerContactTriangle(const Vec3& a, const Vec3& b, const Vec3& c, PlayerContactTriangle& out)
{
    const float ux = b.x - a.x;
    const float uy = b.y - a.y;
    const float uz = b.z - a.z;
    const float vx = c.x - a.x;
    const float vy = c.y - a.y;
    const float vz = c.z - a.z;
    const Vec3 normal{uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx};
    const float length = std::sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
    if (!(length > 1.0e-5f))
    {
        return false;
    }
    out.a = a;
    out.b = b;
    out.c = c;
    out.normal = Vec3{normal.x / length, normal.y / length, normal.z / length};
    return true;
}

PlayerContactResult resolvePlayerContact(
    std::span<const PlayerContactTriangle> triangles,
    const Vec3& center,
    float radiusSquared)
{
    PlayerContactResult result{};
    result.center = center;

    ContactState state{};
    state.radiusSquared = radiusSquared;
    Vec3 native = reflectY(center);

    for (int pass = 0; pass < kPlayerContactMaxPasses; ++pass)
    {
        result.passes = pass + 1;

        // FUN_1016F0E0 reseeds these at the top of every pass and seeds the
        // correction with the pass's input centre, so a pass that touches
        // nothing leaves the body exactly where it was.
        state.nearestWall = kFarSentinel;
        state.nearestFloor = kFarSentinel;
        state.wallHit = false;
        state.groundHit = false;
        state.corrected = native;

        // Every triangle is tested against the SAME input centre; the nearest
        // wall and nearest floor candidates win. This is not a sequential
        // application of corrections.
        for (const PlayerContactTriangle& triangle : triangles)
        {
            const NativeTriangle converted{
                reflectY(triangle.a), reflectY(triangle.b), reflectY(triangle.c), reflectY(triangle.normal)};
            applyTriangle(state, converted, native);
        }

        native = state.corrected;
        // DELIBERATE ADDITION. The client's own flags are read after the loop,
        // where a successful settle has just completed a pass that touched
        // nothing -- so on success they are always false and say nothing about
        // what moved the body. Accumulating them across passes is the only way
        // the caller can tell a wall push from a floor settle. Nothing in the
        // resolved position depends on this.
        result.wallContact = result.wallContact || state.wallHit;
        result.groundContact = result.groundContact || state.groundHit;
        result.center = reflectY(native);

        if (!state.wallHit && !state.groundHit)
        {
            result.resolved = true;
            return result;
        }
    }

    // A fourth pass still moving the body is the client's failure case.
    result.resolved = false;
    return result;
}

PlayerSettleResult settlePlayerFeet(
    std::span<const PlayerContactTriangle> triangles,
    const Vec3& feet,
    float radius)
{
    const Vec3 center{feet.x, feet.y + radius, feet.z};
    const PlayerContactResult contact = resolvePlayerContact(triangles, center, radius * radius);

    PlayerSettleResult result{};
    result.feet = Vec3{contact.center.x, contact.center.y - radius, contact.center.z};
    result.resolved = contact.resolved;
    result.wallContact = contact.wallContact;
    result.groundContact = contact.groundContact;
    result.passes = contact.passes;
    return result;
}

}  // namespace accessxi::collision
