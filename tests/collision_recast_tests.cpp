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
using accessxi::collision::ParsedZoneMesh;
using accessxi::collision::PathStatus;
using accessxi::collision::RecastZone;
using accessxi::collision::Triangle;
using accessxi::collision::Vec3;
using accessxi::collision::parse_zone_collision;
using accessxi::collision::read_stable_snapshot;
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

} // namespace

int main(const int argc, char** argv)
{
    try
    {
        if (argc != 2)
        {
            throw std::runtime_error("Expected the installed FINAL FANTASY XI root path.");
        }
        run_synthetic_tests();
        run_installed_tomb_test(fs::path(argv[1]));
        run_installed_lathine_query_latency_test(fs::path(argv[1]));
        std::cout << "collision Recast tests passed\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
