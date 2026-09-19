#include "collision_native/collision_world.h"
#include "collision_native/file_snapshot.h"
#include "collision_native/mzb_parser.h"
#include "collision_native/recast_zone.h"
#include "collision_native/rom_resolver.h"

#include <cmath>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

namespace fs = std::filesystem;

namespace {

using accessxi::collision::CollisionWorld;
using accessxi::collision::ContactBudget;
using accessxi::collision::ParsedZoneMesh;
using accessxi::collision::PathStatus;
using accessxi::collision::RecastZone;
using accessxi::collision::Triangle;
using accessxi::collision::Vec3;
using accessxi::collision::parse_zone_collision;
using accessxi::collision::read_stable_snapshot;
using accessxi::collision::recast_raster_walkable_climb;
using accessxi::collision::resolve_zone_model_dat;

void check(const bool condition, const char* expression, const int line)
{
    if (!condition)
    {
        throw std::runtime_error(
            std::string("CHECK failed at line ") + std::to_string(line) + ": " + expression);
    }
}

#define CHECK(expression) check(static_cast<bool>(expression), #expression, __LINE__)

void append_quad(
    ParsedZoneMesh& mesh,
    const Vec3& a,
    const Vec3& b,
    const Vec3& c,
    const Vec3& d)
{
    const auto base = static_cast<std::uint32_t>(mesh.vertices.size());
    mesh.vertices.insert(mesh.vertices.end(), {a, b, c, d});
    mesh.triangles.push_back(Triangle{base, base + 1u, base + 2u});
    mesh.triangles.push_back(Triangle{base, base + 2u, base + 3u});
}

ParsedZoneMesh synthetic_detour_mesh(const bool leave_gap)
{
    ParsedZoneMesh mesh;
    append_quad(
        mesh,
        Vec3{-6.0f, 0.0f, -6.0f},
        Vec3{-6.0f, 0.0f, 6.0f},
        Vec3{6.0f, 0.0f, 6.0f},
        Vec3{6.0f, 0.0f, -6.0f});
    const float wall_end = leave_gap ? 3.0f : 6.0f;
    append_quad(
        mesh,
        Vec3{0.0f, 0.0f, -6.0f},
        Vec3{0.0f, 3.0f, -6.0f},
        Vec3{0.0f, 3.0f, wall_end},
        Vec3{0.0f, 0.0f, wall_end});
    return mesh;
}

bool step_aware_segment_is_clear(const CollisionWorld& world, const Vec3& start, const Vec3& end)
{
    if (world.sweep_capsule(start, end, 0.40f, 1.80f).clear)
    {
        return true;
    }
    const Vec3 raised_start{start.x, start.y + 0.65f, start.z};
    const Vec3 raised_end{end.x, end.y + 0.65f, end.z};
    return world.sweep_capsule(start, raised_start, 0.40f, 1.80f).clear
        && world.sweep_capsule(raised_start, raised_end, 0.40f, 1.80f).clear
        && world.sweep_capsule(raised_end, end, 0.40f, 1.80f).clear;
}

void check_clear_segments(const CollisionWorld& world, const std::vector<Vec3>& points)
{
    CHECK(points.size() >= 2u);
    for (std::size_t index = 1; index < points.size(); ++index)
    {
        CHECK(step_aware_segment_is_clear(world, points[index - 1u], points[index]));
    }
}

void check_direct_segments(const CollisionWorld& world, const std::vector<Vec3>& points)
{
    CHECK(points.size() >= 2u);
    for (std::size_t index = 1; index < points.size(); ++index)
    {
        CHECK(world.sweep_capsule(
            points[index - 1u],
            points[index],
            0.40f,
            1.80f).clear);
    }
}

void check_bounded_step_segments(const CollisionWorld& world, const std::vector<Vec3>& points)
{
    CHECK(points.size() >= 2u);
    for (std::size_t index = 1; index < points.size(); ++index)
    {
        const auto& start = points[index - 1u];
        const auto& end = points[index];
        if (world.sweep_capsule(start, end, 0.40f, 1.80f).clear)
        {
            continue;
        }
        const float dx = end.x - start.x;
        const float dz = end.z - start.z;
        CHECK(std::sqrt((dx * dx) + (dz * dz)) <= 1.5f);
        CHECK(step_aware_segment_is_clear(world, start, end));
    }
}

void run_synthetic_tests()
{
    const ParsedZoneMesh mesh = synthetic_detour_mesh(true);
    const CollisionWorld world(mesh);
    const RecastZone zone(mesh, world);
    const auto first = zone.find_path(
        Vec3{-4.0f, 0.02f, 0.0f},
        Vec3{4.0f, 0.02f, 0.0f},
        0.5f,
        128u);
    if (first.status != PathStatus::ready)
    {
        throw std::runtime_error("Synthetic Recast route failed: " + first.reason);
    }
    CHECK(first.status == PathStatus::ready);
    CHECK(first.points.size() > 2u);
    CHECK(first.total_length > 8.0f);
    check_clear_segments(world, first.points);

    const auto repeated = zone.find_path(
        Vec3{-4.0f, 0.02f, 0.0f},
        Vec3{4.0f, 0.02f, 0.0f},
        0.5f,
        128u);
    CHECK(repeated.status == PathStatus::ready);
    CHECK(repeated.points.size() == first.points.size());
    for (std::size_t index = 0; index < first.points.size(); ++index)
    {
        CHECK(repeated.points[index].x == first.points[index].x);
        CHECK(repeated.points[index].y == first.points[index].y);
        CHECK(repeated.points[index].z == first.points[index].z);
    }

    const ParsedZoneMesh blocked_mesh = synthetic_detour_mesh(false);
    const CollisionWorld blocked_world(blocked_mesh);
    const RecastZone blocked_zone(blocked_mesh, blocked_world);
    CHECK(blocked_zone.find_path(
        Vec3{-4.0f, 0.02f, 0.0f},
        Vec3{4.0f, 0.02f, 0.0f},
        0.5f,
        128u).status == PathStatus::unreachable);
}

void run_installed_tomb_test(const fs::path& ffxi_root)
{
    const auto snapshot = read_stable_snapshot(resolve_zone_model_dat(ffxi_root, 190u));
    const ParsedZoneMesh mesh = parse_zone_collision(snapshot, 190u);
    const CollisionWorld world(mesh);
    CHECK(!step_aware_segment_is_clear(
        world,
        Vec3{-136.382f, -1.129f, 202.791f},
        Vec3{-143.982f, 6.071f, 151.191f}));
    CHECK(!step_aware_segment_is_clear(
        world,
        Vec3{-137.282f, -0.329f, 202.491f},
        Vec3{-143.782f, 6.271f, 150.991f}));
    const RecastZone zone(mesh, world);
    const auto path = zone.find_path(
        Vec3{-115.008f, -0.051f, 218.328f},
        Vec3{1.000f, -1.419f, -103.608f},
        8.0f,
        512u);
    if (path.status != PathStatus::ready)
    {
        throw std::runtime_error("Installed Tomb Recast route failed: " + path.reason);
    }
    CHECK(path.status == PathStatus::ready);
    CHECK(path.points.size() > 2u);
    CHECK(path.points.size() <= 512u);
    CHECK(path.total_length > 0.0f);
    CHECK(path.settings_digest == RecastZone::settings_digest());
    check_clear_segments(world, path.points);
}

void run_installed_lathine_query_latency_test(const fs::path& ffxi_root)
{
    const auto snapshot = read_stable_snapshot(resolve_zone_model_dat(ffxi_root, 102u));
    const ParsedZoneMesh mesh = parse_zone_collision(snapshot, 102u);
    const CollisionWorld world(mesh);
    const RecastZone zone(mesh, world);
    const Vec3 galaihaurat{-481.196f, 7.028f, 220.547f};

    // Exact 2026-08-12 automatic start. Terrain construction runs before this
    // timer. A deployed candidate search blocked the game thread here for
    // 50.5 seconds; path queries against an already-built zone must stay
    // bounded. La Theine gameplay now uses the installed full-zone navmesh.
    const auto query_started = std::chrono::steady_clock::now();
    const auto initial = zone.find_path(
        Vec3{-430.056f, -8.357f, 207.719f},
        galaihaurat,
        8.0f,
        512u);
    const auto query_elapsed = std::chrono::steady_clock::now() - query_started;
    if (initial.status != PathStatus::ready)
    {
        throw std::runtime_error("Installed La Theine initial route failed: " + initial.reason);
    }
    CHECK(query_elapsed < std::chrono::seconds(5));
    CHECK(initial.points.size() >= 2u);
    CHECK(initial.points.size() <= 512u);
    check_direct_segments(world, initial.points);
}

void run_installed_upper_jeuno_bounded_step_test(const fs::path& ffxi_root)
{
    const auto snapshot = read_stable_snapshot(resolve_zone_model_dat(ffxi_root, 244u));
    const ParsedZoneMesh mesh = parse_zone_collision(snapshot, 244u);
    const CollisionWorld world(mesh);
    const RecastZone zone(mesh, world);
    const auto path = zone.find_path(
        Vec3{-105.224f, 0.0f, 186.989f},
        Vec3{4.763f, 1.796f, -54.883f},
        8.0f,
        512u);
    if (path.status != PathStatus::ready)
    {
        throw std::runtime_error("Installed Upper Jeuno route failed: " + path.reason);
    }
    CHECK(path.points.size() >= 2u);
    CHECK(path.points.size() <= 512u);
    check_bounded_step_segments(world, path.points);
}

void run_installed_mhaura_test(const fs::path& ffxi_root)
{
    CHECK(RecastZone::settings_digest()
        == "fbd9d83386f631a523850365dc2ab5921759d17949408c8d70d2398c6bb5aae1");
    CHECK(recast_raster_walkable_climb(248u) == 0.60f);
    CHECK(recast_raster_walkable_climb(249u) == 0.80f);
    CHECK(recast_raster_walkable_climb(250u) == 0.60f);

    const auto snapshot = read_stable_snapshot(resolve_zone_model_dat(ffxi_root, 249u));
    const ParsedZoneMesh mesh = parse_zone_collision(snapshot, 249u);
    const CollisionWorld world(mesh);
    const RecastZone zone(mesh, world);

    // Production pairs the raw Mhaura-to-Buburimu trigger with the reverse
    // landing from edge 845230970, then validates the short trigger tail.
    const auto path = zone.find_path(
        Vec3{-12.750f, 15.791f, 86.286f},
        Vec3{0.003f, 6.252f, 117.971f},
        20.0f,
        512u);
    if (path.status != PathStatus::ready)
    {
        throw std::runtime_error("Installed Mhaura route failed: " + path.reason);
    }
    CHECK(path.points.size() >= 2u);
    CHECK(path.points.size() <= 512u);
    CHECK(path.settings_digest == RecastZone::settings_digest());
    for (const Vec3& point : path.points)
    {
        CHECK(std::isfinite(point.x));
        CHECK(std::isfinite(point.y));
        CHECK(std::isfinite(point.z));
    }
    check_clear_segments(world, path.points);
    CHECK(step_aware_segment_is_clear(
        world,
        path.points.back(),
        Vec3{-0.179f, 8.549f, 121.015f}));
}

void run_crawlers_nest_safety_tests()
{
    // The cave raster may admit more candidate surfaces, but walls must still
    // block travel and a real passage around a wall must remain usable.
    for (const bool leave_gap : {false, true})
    {
        auto mesh = synthetic_detour_mesh(leave_gap);
        mesh.zone_id = 197u;
        const CollisionWorld world(mesh);
        const RecastZone zone(mesh, world);
        const auto path = zone.find_path(
            Vec3{-4.0f, 0.02f, 0.0f}, Vec3{4.0f, 0.02f, 0.0f}, 0.5f, 128u);
        CHECK(path.status == (leave_gap ? PathStatus::ready : PathStatus::unreachable));
        if (leave_gap)
        {
            CHECK(path.total_length > 8.0f);
            check_clear_segments(world, path.points);
        }
    }

    // A 2-yalm ledge is smaller than the candidate raster's seam tolerance.
    // It is not a player step: reject both climbing it and floating downhill.
    ParsedZoneMesh ledge;
    ledge.zone_id = 197u;
    append_quad(ledge, Vec3{-8, 2, -8}, Vec3{-8, 2, 8},
        Vec3{0, 2, 8}, Vec3{0, 2, -8});
    append_quad(ledge, Vec3{0, 0, -8}, Vec3{0, 0, 8},
        Vec3{8, 0, 8}, Vec3{8, 0, -8});
    append_quad(ledge, Vec3{0, 0, -8}, Vec3{0, 2, -8},
        Vec3{0, 2, 8}, Vec3{0, 0, 8});
    const CollisionWorld world(ledge);
    const RecastZone zone(ledge, world);
    const Vec3 high{-4, 2.02f, 0};
    const Vec3 low{4, 0.02f, 0};
    CHECK(zone.find_path(high, low, 0.5f, 128u).status == PathStatus::unreachable);
    CHECK(zone.find_path(low, high, 0.5f, 128u).status == PathStatus::unreachable);

    ParsedZoneMesh gap;
    gap.zone_id = 197u;
    append_quad(gap, Vec3{-8, 0, -8}, Vec3{-8, 0, 8},
        Vec3{-1, 0, 8}, Vec3{-1, 0, -8});
    append_quad(gap, Vec3{1, 0, -8}, Vec3{1, 0, 8},
        Vec3{8, 0, 8}, Vec3{8, 0, -8});
    const CollisionWorld gap_world(gap);
    CHECK(!gap_world.player_walk_segment(Vec3{-2, 0, 0}, Vec3{2, 0, 0}));
    CHECK(gap_world.player_local_detour(Vec3{-2, 0, 0}, Vec3{2, 0, 0}, 128u).empty());
    CHECK(!gap_world.player_contact_segment(Vec3{-0.2f, 0, 0}, Vec3{0.2f, 0, 0}));
    CHECK(gap_world.player_segment_detour(Vec3{-6, 0, 0}, Vec3{6, 0, 0}, 128u).empty());
}

void run_contact_budget_tests()
{
    // THE ALLOWANCE MUST FAIL CLOSED.
    //
    // An exhausted budget means "not proven walkable". If it ever read as
    // "assume walkable" the ceiling would hand back exactly the unvalidated
    // routes the contact profile exists to prevent, so the checks below pin the
    // direction of the failure, not merely that it happens.
    CHECK(!ContactBudget(0u).spend(1u));
    ContactBudget small(3u);
    CHECK(small.spend(2u));
    CHECK(small.remaining() == 1u);
    CHECK(!small.spend(2u));          // a charge larger than the remainder
    CHECK(small.exhausted());
    CHECK(small.remaining() == 0u);
    CHECK(!small.spend(0u));          // and it stays exhausted afterwards

    // Flat ground a body can certainly walk, so the ONLY reason any of the
    // checks below can fail is the allowance.
    ParsedZoneMesh flat;
    flat.zone_id = 197u;
    append_quad(flat, Vec3{-8, 0, -8}, Vec3{-8, 0, 8}, Vec3{8, 0, 8}, Vec3{8, 0, -8});
    const CollisionWorld flat_world(flat);
    const Vec3 from{-2, 0, 0};
    const Vec3 to{2, 0, 0};

    // Unlimited: this geometry is walkable, which is what makes the rest of the
    // test meaningful rather than a tautology.
    CHECK(flat_world.player_walk_segment(from, to));
    CHECK(flat_world.player_walk_segment(from, to, nullptr));
    const auto subdivided = flat_world.player_segment_detour(
        Vec3{-7, 0, 0}, Vec3{7, 0, 0}, 16u);
    CHECK(subdivided.size() > 2u && subdivided.size() <= 16u);
    for (std::size_t i = 1; i < subdivided.size(); ++i)
        CHECK(flat_world.player_walk_segment(subdivided[i - 1], subdivided[i]));
    CHECK(flat_world.player_segment_detour(
        Vec3{-7, 0, 0}, Vec3{7, 0, 0}, 2u).empty());
    ContactBudget no_subdivision_work(0u);
    CHECK(flat_world.player_segment_detour(
        Vec3{-7, 0, 0}, Vec3{7, 0, 0}, 16u, &no_subdivision_work).empty());

    ContactBudget empty_budget(0u);
    CHECK(!flat_world.player_walk_segment(from, to, &empty_budget));
    CHECK(empty_budget.exhausted());

    // A part-spent allowance must not yield a partial route. The detour either
    // returns a path it validated end to end, or nothing at all.
    for (const std::uint64_t units : {std::uint64_t{0}, std::uint64_t{1},
             std::uint64_t{25}, std::uint64_t{400}})
    {
        ContactBudget budget(units);
        const auto path = flat_world.player_local_detour(from, to, 128u, &budget);
        CHECK(path.empty() || !budget.exhausted());
        if (!path.empty())
        {
            // Whatever it returned has to start and end where it was asked to.
            CHECK(path.size() >= 2u);
            CHECK(std::fabs(path.front().x - from.x) < 0.001f);
            CHECK(std::fabs(path.back().x - to.x) < 0.001f);
        }
    }

    ContactBudget contact_budget(0u);
    CHECK(!flat_world.player_contact_segment(
        Vec3{-0.2f, 0, 0}, Vec3{0.2f, 0, 0}, &contact_budget));

    // Other zones must not acquire an allowance, or any behaviour at all, from
    // this change: the same mesh outside zone 197 still uses the capsule path.
    ParsedZoneMesh elsewhere = flat;
    elsewhere.zone_id = 200u;
    const CollisionWorld other_world(elsewhere);
    const RecastZone other_zone(elsewhere, other_world);
    const auto other = other_zone.find_path(
        Vec3{-2.0f, 0.02f, 0.0f}, Vec3{2.0f, 0.02f, 0.0f}, 0.5f, 128u);
    CHECK(other.status == PathStatus::ready);
    CHECK(other.reason.find("work allowance") == std::string::npos);
}

void run_installed_crawlers_nest_test(const fs::path& ffxi_root)
{
    const auto snapshot = read_stable_snapshot(resolve_zone_model_dat(ffxi_root, 197u));
    const ParsedZoneMesh mesh = parse_zone_collision(snapshot, 197u);
    const CollisionWorld world(mesh);
    const RecastZone zone(mesh, world);

    // September 19 support report: the player entered from Rolanberry, then
    // selected Exoray while working on In Defiant Challenge. Coordinates here
    // are the logged game positions converted to the collision API's Y-up.
    const Vec3 start{381.367f, 32.433f, 4.581f};
    const Vec3 destination{60.0f, 2.0f, -13.0f};
    const auto path = zone.find_path(start, destination, 3.5f, 512u);
    if (path.status != PathStatus::ready)
    {
        throw std::runtime_error("Installed Crawlers' Nest entrance-to-Exoray route failed: " + path.reason);
    }
    CHECK(path.points.size() > 2u);
    CHECK(path.points.size() <= 512u);
    CHECK(path.total_length > 320.0f);
    const auto& first = path.points.front();
    const auto& last = path.points.back();
    CHECK(std::hypot(first.x - start.x, first.z - start.z) < 1.0f);
    CHECK(std::fabs(first.y - start.y) < 1.0f);
    CHECK(std::hypot(last.x - destination.x, last.z - destination.z) <= 3.55f);
    CHECK(std::fabs(last.y - destination.y) < 2.0f);
    for (std::size_t i = 1; i < path.points.size(); ++i)
    {
        CHECK(world.player_walk_segment(path.points[i - 1], path.points[i])
            || world.player_contact_segment(path.points[i - 1], path.points[i]));
    }
    std::cout << "Crawlers' Nest route points=" << path.points.size()
              << " length=" << path.total_length << '\n';
    CHECK(zone.find_path(start, destination, 3.5f, 2u).status == PathStatus::unreachable);

    // The zone-wide audit found repeated-prefix work exhaustion and a steeper
    // northern passage beyond the original Exoray case. Preserve those routes
    // while keeping the same ground/contact proof on every returned segment.
    for (const Vec3 camp : {Vec3{-27.520f, 1.154f, -354.861f},
             Vec3{-134.0f, 1.0f, 361.0f}, Vec3{216.350f, 0.535f, -340.001f}})
    {
        const auto distant = zone.find_path(start, camp, 3.5f, 512u);
        CHECK(distant.status == PathStatus::ready);
        CHECK(distant.points.size() >= 2u && distant.points.size() <= 512u);
        for (std::size_t i = 1; i < distant.points.size(); ++i)
        {
            CHECK(world.player_walk_segment(distant.points[i - 1], distant.points[i])
                || world.player_contact_segment(distant.points[i - 1], distant.points[i]));
        }
    }
}

} // namespace

int main(const int argc, char** argv)
{
    try
    {
        if (argc != 2 && argc != 3)
        {
            throw std::runtime_error("Expected the installed FINAL FANTASY XI root path.");
        }
        run_synthetic_tests();
        run_crawlers_nest_safety_tests();
        run_contact_budget_tests();
        if (argc == 3)
        {
            if (std::string(argv[2]) != "--crawlers-nest-only")
            {
                throw std::runtime_error("Unknown collision Recast test selection.");
            }
            run_installed_crawlers_nest_test(fs::path(argv[1]));
            std::cout << "collision Crawlers' Nest tests passed\n";
            return 0;
        }
        run_installed_tomb_test(fs::path(argv[1]));
        run_installed_lathine_query_latency_test(fs::path(argv[1]));
        run_installed_upper_jeuno_bounded_step_test(fs::path(argv[1]));
        run_installed_mhaura_test(fs::path(argv[1]));
        run_installed_crawlers_nest_test(fs::path(argv[1]));
        std::cout << "collision Recast tests passed\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
