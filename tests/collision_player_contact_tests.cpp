// Tests for src/collision_native/player_contact.cpp.
//
// Every expected number below is derived BY HAND from the decompiled client
// formulas (logs/2026-09-19-crawlers-nest/ghidra-current-wall-contact.txt,
// ghidra-current-wall-segment.txt, ghidra-current-contact-predicates.txt and
// the constant dumps), never by running the port and recording what it said. A
// test that prints its own output back at itself proves nothing.
//
// Where the client's behaviour is an exact closed form -- the plane projection,
// the sqrt(r^2 - d^2) push, the one-radius vertical drop, the front-face guard,
// the four-pass ceiling -- the fixture asserts the exact value, and the wrong
// implementation of the same shape fails it. The commonly-guessed r - d push,
// for instance, gives 4.5 where the client gives 4.8 - sqrt(0.21).
//
// EXACT NATIVE COMPARISON. logs/2026-09-19-crawlers-nest/native-probe can emit
// the client's own answers for these same fixtures with
// `native_contact_probe <exported-root> --contact-fixtures`, which writes
// native-contact-math-fixtures.tsv (distinct from the route-audit artifact
// native-contact-fixtures.tsv). That file needs math blobs exported from the
// locally installed client, which are deliberately not in the repository.
// Pass that table as the executable's optional argument to compare directly.
// Without an argument, only the portable hand-derived expectations run.

#include "collision_native/player_contact.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

using accessxi::collision::kPlayerContactMaxPasses;
using accessxi::collision::kPlayerContactRadius;
using accessxi::collision::makePlayerContactTriangle;
using accessxi::collision::PlayerContactResult;
using accessxi::collision::PlayerContactTriangle;
using accessxi::collision::resolvePlayerContact;
using accessxi::collision::settlePlayerFeet;
using accessxi::collision::Vec3;

namespace
{

int g_failures = 0;

void check(bool condition, const char* what)
{
    if (condition)
    {
        return;
    }
    ++g_failures;
    std::printf("  FAIL %s\n", what);
}

void checkNear(float actual, float expected, float tolerance, const char* what)
{
    if (std::fabs(actual - expected) <= tolerance)
    {
        return;
    }
    ++g_failures;
    std::printf("  FAIL %s (expected %.7f, got %.7f)\n", what, expected, actual);
}

PlayerContactTriangle triangle(const Vec3& a, const Vec3& b, const Vec3& c)
{
    PlayerContactTriangle out{};
    const bool ok = makePlayerContactTriangle(a, b, c, out);
    check(ok, "fixture triangle is non-degenerate");
    return out;
}

// A large horizontal floor at y = 10, wound so the derived normal is +Y.
std::vector<PlayerContactTriangle> horizontalFloor()
{
    return {triangle(Vec3{0.0f, 10.0f, 0.0f}, Vec3{0.0f, 10.0f, 20.0f}, Vec3{20.0f, 10.0f, 0.0f})};
}

// A vertical wall in the plane x = 5, derived normal -X, tall enough that a
// vertex sits above the body (the client requires that for a wall push).
std::vector<PlayerContactTriangle> wallAtX5()
{
    return {triangle(Vec3{5.0f, 0.0f, 0.0f}, Vec3{5.0f, 0.0f, 20.0f}, Vec3{5.0f, 20.0f, 0.0f})};
}

void testNormalWinding()
{
    std::printf("normal follows the vertex winding\n");
    PlayerContactTriangle up{};
    check(makePlayerContactTriangle(
              Vec3{0.0f, 10.0f, 0.0f}, Vec3{0.0f, 10.0f, 20.0f}, Vec3{20.0f, 10.0f, 0.0f}, up),
        "floor winding accepted");
    checkNear(up.normal.x, 0.0f, 1e-6f, "floor normal x");
    checkNear(up.normal.y, 1.0f, 1e-6f, "floor normal y is +1, not the stored sign");
    checkNear(up.normal.z, 0.0f, 1e-6f, "floor normal z");

    PlayerContactTriangle degenerate{};
    check(!makePlayerContactTriangle(
              Vec3{1.0f, 2.0f, 3.0f}, Vec3{1.0f, 2.0f, 3.0f}, Vec3{4.0f, 5.0f, 6.0f}, degenerate),
        "a zero-area triangle is refused");
}

void testEmptySpaceIsUntouched()
{
    std::printf("empty space leaves the body exactly where it was\n");
    const Vec3 center{123.25f, -17.5f, 6.0f};
    const PlayerContactResult result = resolvePlayerContact({}, center);
    check(result.resolved, "no triangles resolves");
    check(result.passes == 1, "one pass is enough when nothing is near");
    check(!result.wallContact && !result.groundContact, "no contact flags");
    checkNear(result.center.x, center.x, 0.0f, "x is bit-identical");
    checkNear(result.center.y, center.y, 0.0f, "y is bit-identical");
    checkNear(result.center.z, center.z, 0.0f, "z is bit-identical");
}

void testBodyRestingExactlyOnTheFloorIsNotAContact()
{
    // The client requires d^2 <= r^2 - 0.001 (_DAT_1032A22C). A body exactly one
    // radius above the plane has d^2 == 0.25, so 0.25 <= 0.249 is false and the
    // floor is NOT touched. This pins the epsilon: drop it and this fails.
    std::printf("a body exactly one radius clear is not in contact\n");
    const auto floor = horizontalFloor();
    const Vec3 center{2.0f, 10.5f, 2.0f};
    const PlayerContactResult result = resolvePlayerContact(floor, center);
    check(result.resolved, "resting body resolves");
    check(result.passes == 1, "and needs a single pass");
    check(!result.groundContact, "with no ground correction");
    checkNear(result.center.y, 10.5f, 0.0f, "y untouched");
}

void testFloorSettlesToExactlyOneRadius()
{
    // Feet 0.2 below the floor. Native frame centre y = -10.3, plane y = -10, so
    // the projection is (2, -10, 2), d^2 = 0.09 <= 0.249, |n.y| = 1 > 0.708 and
    // n.y < 0 -- the mesh-frame floor branch. The correction is
    // projected.y - 0.5 = -10.5, i.e. mesh y = 10.5, feet = 10.0. A second pass
    // then finds d^2 = 0.25 and stops.
    std::printf("a sunken body settles to exactly one radius above the floor\n");
    const auto floor = horizontalFloor();
    const PlayerContactResult result = resolvePlayerContact(floor, Vec3{2.0f, 10.3f, 2.0f});
    check(result.resolved, "sunken body resolves");
    check(result.passes == 2, "in two passes: correct, then confirm");
    check(result.groundContact, "and reports ground contact");
    check(!result.wallContact, "with no wall involved");
    checkNear(result.center.y, 10.5f, 1e-5f, "centre is one radius above the plane");
    checkNear(result.center.x, 2.0f, 0.0f, "floor branch never moves x");
    checkNear(result.center.z, 2.0f, 0.0f, "floor branch never moves z");

    const auto settled = settlePlayerFeet(floor, Vec3{2.0f, 9.8f, 2.0f});
    check(settled.resolved, "feet settle resolves");
    checkNear(settled.feet.y, 10.0f, 1e-5f, "feet land on the floor plane");
}

void testSlopeSettlesAboveThePlaneAndIsAFixedPoint()
{
    // Normal (-1, 2, 0)/sqrt(5): n.y = 0.894 > 0.708, so still the floor branch.
    // The client's correction is a pure vertical move, so on a slope one pass
    // undershoots and it iterates. The invariants that must hold regardless of
    // how many passes it takes: the body ends on the outside of the plane, and
    // re-resolving the answer changes nothing.
    std::printf("a slope settles above the plane and the answer is stable\n");
    const Vec3 a{0.0f, 10.0f, 0.0f};
    const std::vector<PlayerContactTriangle> slope{
        triangle(a, Vec3{0.0f, 10.0f, 20.0f}, Vec3{40.0f, 30.0f, 0.0f})};
    checkNear(slope[0].normal.y, 2.0f / std::sqrt(5.0f), 1e-6f, "slope normal y is 0.894");
    check(slope[0].normal.y > 0.708f, "so the slope is a floor, not a wall");

    // The plane is y = 10 + x/2, so the surface under x = 4 sits at y = 12; a
    // centre at 12.3 is 0.268 in front of it, inside the 0.5 radius.
    const PlayerContactResult result = resolvePlayerContact(slope, Vec3{4.0f, 12.3f, 5.0f});
    check(result.resolved, "slope body resolves within four passes");
    check(result.groundContact, "and reports ground contact");

    const Vec3& p = result.center;
    const float signed_distance = (p.x - a.x) * slope[0].normal.x
        + (p.y - a.y) * slope[0].normal.y
        + (p.z - a.z) * slope[0].normal.z;
    check(signed_distance > 0.0f, "the body ends on the front of the slope");

    // WHERE A SLOPE ACTUALLY SETTLES. The client's floor correction is a pure
    // vertical move to projected.y - r, so for plane distance s and normal
    // component ny it lands at
    //
    //     s' = s * (1 - ny^2) + r * |ny|
    //
    // Here ny^2 = 0.8, so s' = 0.2 s + 0.4472136 and the iteration's fixed point
    // is 0.4472136 / 0.8 = 0.559017 -- FURTHER OUT than the 0.5 radius. It stops
    // as soon as the body leaves contact range, which is s > sqrt(r^2 - 0.001)
    // = 0.4989990. So a slope settles in the narrow band between those two, and
    // never exactly at the radius the way a level floor does.
    const float outOfContact = std::sqrt(0.25f - 1.0e-3f);
    const float fixedPoint = (kPlayerContactRadius * (2.0f / std::sqrt(5.0f))) / 0.8f;
    check(signed_distance > outOfContact,
        "the body ends clear of contact range");
    check(signed_distance <= fixedPoint + 1e-5f,
        "and no further than the vertical correction's fixed point");

    const PlayerContactResult again = resolvePlayerContact(slope, result.center);
    check(again.resolved && again.passes == 1, "the settled point needs no correction");
    checkNear(again.center.x, result.center.x, 0.0f, "settling is a fixed point in x");
    checkNear(again.center.y, result.center.y, 0.0f, "settling is a fixed point in y");
    checkNear(again.center.z, result.center.z, 0.0f, "settling is a fixed point in z");
}

void testVerticalWallPushesByTheSphereHalfChord()
{
    // Centre x = 4.8, wall plane x = 5, so d = 0.2 and d^2 = 0.04 <= 0.249.
    // |n.y| = 0 <= 0.708 -> the wall branch. The client's push is
    // sqrt(r^2 - d^2) = sqrt(0.25 - 0.04) = sqrt(0.21) = 0.4582576, NOT
    // r - d = 0.3. Expected centre x = 4.8 - sqrt(0.21) = 4.3417424.
    std::printf("a vertical wall pushes by sqrt(r^2 - d^2), not r - d\n");
    const auto wall = wallAtX5();
    checkNear(wall[0].normal.x, -1.0f, 1e-6f, "wall normal points at the body");
    checkNear(wall[0].normal.y, 0.0f, 1e-6f, "wall normal y is zero");

    const PlayerContactResult result = resolvePlayerContact(wall, Vec3{4.8f, 1.5f, 2.0f});
    check(result.resolved, "the body is pushed clear and settles");
    check(result.passes == 2, "one correcting pass and one confirming pass");
    check(result.wallContact, "and reports wall contact");
    check(!result.groundContact, "with no floor involved");

    const float expected = 4.8f - std::sqrt(0.21f);
    checkNear(result.center.x, expected, 1e-5f, "x is the half-chord push");
    check(std::fabs(result.center.x - 4.5f) > 0.1f, "and is NOT the r - d push");
    // out.y is zero here, so the 0.2 vertical scale has nothing to scale.
    checkNear(result.center.y, 1.5f, 0.0f, "y is unchanged by a level push");
    checkNear(result.center.z, 2.0f, 0.0f, "z is unchanged by a level push");
}

void testWallDoesNotPullTheBodyThroughItsBack()
{
    // Same wall, body on the far side at x = 5.2. The projection is still 0.2
    // away, so the distance gate passes, but normalize(centre - projection) now
    // points against the normal and the client's front-face guard refuses to
    // move anything. Without that guard the body would be yanked to x = 5.66.
    std::printf("a wall never pulls a body through its back face\n");
    const auto wall = wallAtX5();
    const PlayerContactResult result = resolvePlayerContact(wall, Vec3{5.2f, 1.5f, 2.0f});
    check(result.resolved, "the back side resolves");
    check(result.passes == 1, "without any correcting pass");
    check(!result.wallContact, "and reports no wall contact");
    checkNear(result.center.x, 5.2f, 0.0f, "x is untouched behind the wall");
    checkNear(result.center.y, 1.5f, 0.0f, "y is untouched behind the wall");
    checkNear(result.center.z, 2.0f, 0.0f, "z is untouched behind the wall");
}

void testWallAboveTheBodyIsIgnored()
{
    // The wall branch requires a vertex above the body in the mesh frame
    // (vertex.y < centre.y - 0.002 once Y is reflected). A wall panel that stops
    // below the centre is a lip, not something to be pushed off.
    std::printf("a wall entirely below the body is not pushed against\n");
    const std::vector<PlayerContactTriangle> lip{
        triangle(Vec3{5.0f, 0.0f, 0.0f}, Vec3{5.0f, 0.0f, 20.0f}, Vec3{5.0f, 1.0f, 0.0f})};
    const PlayerContactResult result = resolvePlayerContact(lip, Vec3{4.8f, 1.5f, 2.0f});
    check(result.resolved, "the lip resolves");
    check(!result.wallContact, "with no wall push");
    checkNear(result.center.x, 4.8f, 0.0f, "and the body stays put");
}

void testEdgeOverlapCatchesAProjectionOutsideTheTriangle()
{
    // Centre placed beyond the triangle's edge in z, so the plane projection
    // lands outside the face and the inside test fails -- but the body sphere
    // still overlaps the edge, which is the fallback that stops a player
    // slipping through a seam. The floor branch then applies the usual drop.
    std::printf("the edge fallback catches a projection outside the face\n");
    const std::vector<PlayerContactTriangle> patch{
        triangle(Vec3{0.0f, 10.0f, 0.0f}, Vec3{0.0f, 10.0f, 2.0f}, Vec3{2.0f, 10.0f, 0.0f})};
    // x = z = 1.1 puts the projection outside the hypotenuse (x + z = 2.2 > 2)
    // by 0.141 in plane, and the centre 0.3 above it, so the distance to the
    // edge is sqrt(0.141^2 + 0.3^2) = 0.332 -- inside the 0.5 radius, which only
    // the edge fallback can see.
    const PlayerContactResult result = resolvePlayerContact(patch, Vec3{1.1f, 10.3f, 1.1f});
    check(result.groundContact, "the edge overlap registers a ground contact");
    check(result.resolved, "and the body settles");
    checkNear(result.center.y, 10.5f, 1e-5f, "onto the plane of the patch");

    // Far enough away in the same direction there is no overlap at all.
    const PlayerContactResult clear = resolvePlayerContact(patch, Vec3{4.0f, 10.3f, 4.0f});
    check(clear.resolved && !clear.groundContact, "a body clear of the edge is untouched");
    checkNear(clear.center.y, 10.3f, 0.0f, "and keeps its height");
}

void testOpposingWallsExhaustTheFourPasses()
{
    // Two inward-facing walls a gap g apart, body on the midline. The push off
    // one is sqrt(0.25 - (g/2)^2), and for the body to land STILL IN FRONT of
    // the opposite wall -- rather than being ejected past it, where the
    // front-face guard would end the matter -- that push must be under g/2:
    //
    //     sqrt(0.25 - (g/2)^2) < g/2   <=>   g > sqrt(0.5) = 0.7071
    //
    // while contact at all needs (g/2)^2 <= 0.249, so g <= 0.998. g = 0.8 sits
    // in that window: 0.4 -> 0.7 -> 0.2101 -> 0.6639 -> still moving on pass 4.
    std::printf("two walls closer than the body exhaust the four passes\n");
    const std::vector<PlayerContactTriangle> corridor{
        triangle(Vec3{0.0f, 0.0f, 0.0f}, Vec3{0.0f, 20.0f, 0.0f}, Vec3{0.0f, 0.0f, 20.0f}),
        triangle(Vec3{0.8f, 0.0f, 0.0f}, Vec3{0.8f, 0.0f, 20.0f}, Vec3{0.8f, 20.0f, 0.0f})};
    checkNear(corridor[0].normal.x, 1.0f, 1e-6f, "first wall faces +X");
    checkNear(corridor[1].normal.x, -1.0f, 1e-6f, "second wall faces -X");

    const PlayerContactResult result = resolvePlayerContact(corridor, Vec3{0.4f, 1.5f, 2.0f});
    check(!result.resolved, "the body cannot be resolved between them");
    check(result.passes == kPlayerContactMaxPasses, "and the four passes are all spent");
    check(result.wallContact, "having been pushed by a wall");
}

void testNearestCandidateWinsRatherThanTriangleOrder()
{
    // Two walls, the far one listed first. A solver that applied corrections in
    // order would push off the far wall; the client keeps only the nearest
    // candidate, so the answer must be the same whichever order they arrive in.
    std::printf("the nearest candidate wins regardless of triangle order\n");
    const PlayerContactTriangle near =
        triangle(Vec3{5.0f, 0.0f, 0.0f}, Vec3{5.0f, 0.0f, 20.0f}, Vec3{5.0f, 20.0f, 0.0f});
    const PlayerContactTriangle far =
        triangle(Vec3{5.4f, 0.0f, 0.0f}, Vec3{5.4f, 0.0f, 20.0f}, Vec3{5.4f, 20.0f, 0.0f});

    const std::vector<PlayerContactTriangle> nearFirst{near, far};
    const std::vector<PlayerContactTriangle> farFirst{far, near};
    const Vec3 center{4.9f, 1.5f, 2.0f};
    const PlayerContactResult a = resolvePlayerContact(nearFirst, center);
    const PlayerContactResult b = resolvePlayerContact(farFirst, center);
    checkNear(b.center.x, a.center.x, 0.0f, "x does not depend on triangle order");
    checkNear(b.center.y, a.center.y, 0.0f, "y does not depend on triangle order");
    checkNear(b.center.z, a.center.z, 0.0f, "z does not depend on triangle order");
    // d = 0.1 to the near wall: push sqrt(0.25 - 0.01) = 0.4898979.
    checkNear(a.center.x, 4.9f - std::sqrt(0.24f), 1e-5f, "and is the nearest wall's push");
}

void testWallVerticalCorrectionIsScaledByOneFifth()
{
    // A wall leaning just inside the threshold: normal.y magnitude below 0.708
    // keeps it in the wall branch, and then the vertical part of the push is
    // multiplied by 0.2 (_DAT_1032A39C). This is the only fixture where out.y is
    // non-zero, so it is the one that pins the scale.
    std::printf("the wall branch scales its vertical correction by 0.2\n");
    // Normal (-1, 1, 0)/sqrt(2): n.y = 0.7071 < 0.708, so still a wall.
    const Vec3 a{5.0f, 0.0f, 0.0f};
    const std::vector<PlayerContactTriangle> leaning{
        triangle(a, Vec3{5.0f, 0.0f, 20.0f}, Vec3{25.0f, 20.0f, 0.0f})};
    const float ny = leaning[0].normal.y;
    checkNear(ny, 1.0f / std::sqrt(2.0f), 1e-6f, "leaning normal y is 0.7071");
    check(ny < 0.708f, "which is inside the wall threshold, not the floor one");

    // The plane is y = x - 5. Take the surface point (5.5, 0.5, 2) and step 0.2
    // back along the unit normal (-0.7071, +0.7071, 0) to get a centre 0.2 in
    // front of the lean, inside the radius.
    const Vec3 center{5.5f - 0.7071068f * 0.2f, 0.5f + 0.7071068f * 0.2f, 2.0f};
    const PlayerContactResult result = resolvePlayerContact(leaning, center);
    check(result.wallContact, "the lean is treated as a wall");

    // Both x and y move along the same unit direction by the same push, so the
    // ratio of the two displacements is exactly the 0.2 scale. Deriving it as a
    // ratio keeps the check independent of the push magnitude.
    const float movedX = result.center.x - center.x;
    const float movedY = result.center.y - center.y;
    check(std::fabs(movedX) > 1e-4f, "the horizontal part moved");
    // Mesh +Y is the client's -Y, so the reflected vertical displacement is
    // compared against the horizontal one.
    checkNear(std::fabs(movedY) / std::fabs(movedX), 0.2f, 1e-3f,
        "vertical displacement is one fifth of the horizontal");
}

// ---------------------------------------------------------------------------
// Exact comparison against the client, when the probe has been run.

struct Fixture final
{
    std::string name;
    Vec3 center{};
    Vec3 expected{};
    int resolved = 0;
};

bool loadNativeFixtures(const std::string& path, std::vector<Fixture>& out)
{
    std::ifstream in(path);
    if (!in)
    {
        return false;
    }
    std::string line;
    std::getline(in, line);  // header
    while (std::getline(in, line))
    {
        if (line.empty())
        {
            continue;
        }
        std::istringstream row(line);
        Fixture fixture{};
        row >> fixture.name >> fixture.center.x >> fixture.center.y >> fixture.center.z
            >> fixture.expected.x >> fixture.expected.y >> fixture.expected.z >> fixture.resolved;
        if (row.fail()) return false;
        out.push_back(fixture);
    }
    return true;
}

void testAgainstNativeFixturesIfPresent(const char* fixturePath)
{
    std::vector<Fixture> fixtures;
    if (fixturePath == nullptr)
    {
        std::printf(
            "native fixture comparison SKIPPED: no usable cases in %s.\n"
            "  Produce it with: native_contact_probe <exported-root> --contact-fixtures\n"
            "  (needs client math blobs, which are deliberately not in the repository).\n",
            fixturePath == nullptr ? "<no path given>" : fixturePath);
        return;
    }
    if (!loadNativeFixtures(fixturePath, fixtures) || fixtures.empty())
    {
        check(false, "requested native fixture table is missing, malformed or empty");
        return;
    }
    std::printf("native fixture comparison: %zu case(s) from %s\n", fixtures.size(), fixturePath);

    // The probe emits the same geometry this suite builds, keyed by name.
    const auto floor = horizontalFloor();
    const auto wall = wallAtX5();
    for (const Fixture& fixture : fixtures)
    {
        const std::vector<PlayerContactTriangle>* geometry = nullptr;
        if (fixture.name == "floor")
        {
            geometry = &floor;
        }
        else if (fixture.name == "wall")
        {
            geometry = &wall;
        }
        if (geometry == nullptr)
        {
            check(false, "unknown native fixture geometry");
            continue;
        }
        const PlayerContactResult result = resolvePlayerContact(*geometry, fixture.center);
        const std::string label = "native " + fixture.name;
        checkNear(result.center.x, fixture.expected.x, 1e-4f, (label + " x").c_str());
        checkNear(result.center.y, fixture.expected.y, 1e-4f, (label + " y").c_str());
        checkNear(result.center.z, fixture.expected.z, 1e-4f, (label + " z").c_str());
        check(result.resolved == (fixture.resolved != 0), (label + " resolved").c_str());
    }
}

}  // namespace

int main(int argc, char** argv)
{
    testNormalWinding();
    testEmptySpaceIsUntouched();
    testBodyRestingExactlyOnTheFloorIsNotAContact();
    testFloorSettlesToExactlyOneRadius();
    testSlopeSettlesAboveThePlaneAndIsAFixedPoint();
    testVerticalWallPushesByTheSphereHalfChord();
    testWallDoesNotPullTheBodyThroughItsBack();
    testWallAboveTheBodyIsIgnored();
    testEdgeOverlapCatchesAProjectionOutsideTheTriangle();
    testOpposingWallsExhaustTheFourPasses();
    testNearestCandidateWinsRatherThanTriangleOrder();
    testWallVerticalCorrectionIsScaledByOneFifth();
    testAgainstNativeFixturesIfPresent(argc > 1 ? argv[1] : nullptr);

    if (g_failures != 0)
    {
        std::printf("player contact tests FAILED (%d)\n", g_failures);
        return 1;
    }
    std::printf("player contact tests passed\n");
    return 0;
}
