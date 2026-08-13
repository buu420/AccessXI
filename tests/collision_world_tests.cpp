#include "collision_native/collision_world.h"
#include "collision_native/file_snapshot.h"
#include "collision_native/mzb_parser.h"
#include "collision_native/rom_resolver.h"

#include <cmath>
#include <filesystem>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>

namespace fs = std::filesystem;

namespace {

using accessxi::collision::CollisionWorld;
using accessxi::collision::ParsedZoneMesh;
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

template <typename Callable>
void check_throws(Callable&& callable, const char* expression, const int line)
{
    try
    {
        callable();
    }
    catch (const std::exception&)
    {
        return;
    }
    throw std::runtime_error(
        std::string("CHECK_THROWS failed at line ") + std::to_string(line) + ": " + expression);
}

#define CHECK_THROWS(expression) check_throws([&]() { (void)(expression); }, #expression, __LINE__)

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

ParsedZoneMesh corridor_mesh(const float half_width)
{
    ParsedZoneMesh mesh;
    append_quad(
        mesh,
        Vec3{-2.0f, 0.0f, -4.0f},
        Vec3{2.0f, 0.0f, -4.0f},
        Vec3{2.0f, 0.0f, 4.0f},
        Vec3{-2.0f, 0.0f, 4.0f});
    append_quad(
        mesh,
        Vec3{-half_width, 0.0f, -4.0f},
        Vec3{-half_width, 3.0f, -4.0f},
        Vec3{-half_width, 3.0f, 4.0f},
        Vec3{-half_width, 0.0f, 4.0f});
    append_quad(
        mesh,
        Vec3{half_width, 0.0f, 4.0f},
        Vec3{half_width, 3.0f, 4.0f},
        Vec3{half_width, 3.0f, -4.0f},
        Vec3{half_width, 0.0f, -4.0f});
    return mesh;
}

void run_synthetic_tests()
{
    constexpr float radius = 0.40f;
    constexpr float height = 1.80f;

    const CollisionWorld wide(corridor_mesh(1.0f));
    CHECK(wide.sweep_capsule(
        Vec3{0.0f, 0.02f, -3.0f},
        Vec3{0.0f, 0.02f, 3.0f},
        radius,
        height).clear);

    const CollisionWorld narrow(corridor_mesh(0.30f));
    CHECK(!narrow.sweep_capsule(
        Vec3{0.0f, 0.02f, -3.0f},
        Vec3{0.0f, 0.02f, 3.0f},
        radius,
        height).clear);

    ParsedZoneMesh wall_mesh = corridor_mesh(4.0f);
    append_quad(
        wall_mesh,
        Vec3{0.0f, 0.0f, -1.0f},
        Vec3{0.0f, 3.0f, -1.0f},
        Vec3{0.0f, 3.0f, 1.0f},
        Vec3{0.0f, 0.0f, 1.0f});
    const CollisionWorld wall(wall_mesh);
    const auto wall_hit = wall.sweep_capsule(
        Vec3{-2.0f, 0.02f, 0.0f},
        Vec3{2.0f, 0.02f, 0.0f},
        radius,
        height);
    CHECK(!wall_hit.clear);
    CHECK(wall_hit.fraction > 0.0f && wall_hit.fraction < 1.0f);
    CHECK(std::fabs(wall_hit.normal.x) > 0.8f);

    CHECK(!wall.sweep_capsule(
        Vec3{0.0f, 0.02f, 0.0f},
        Vec3{1.0f, 0.02f, 0.0f},
        radius,
        height).clear);

    const float nan = std::numeric_limits<float>::quiet_NaN();
    CHECK_THROWS(wall.sweep_capsule(Vec3{nan, 0.0f, 0.0f}, Vec3{}, radius, height));
    CHECK_THROWS(wall.sweep_capsule(Vec3{}, Vec3{}, 0.0f, height));
    CHECK_THROWS(wall.sweep_capsule(Vec3{}, Vec3{}, radius, radius));
}

void run_installed_tomb_tests(const fs::path& ffxi_root)
{
    const auto snapshot = read_stable_snapshot(resolve_zone_model_dat(ffxi_root, 190u));
    const ParsedZoneMesh mesh = parse_zone_collision(snapshot, 190u);
    const CollisionWorld world(mesh);

    CHECK(!world.sweep_capsule(
        Vec3{-136.382f, -1.129f, 202.791f},
        Vec3{-143.982f, 6.071f, 151.191f},
        0.40f,
        1.80f).clear);
    CHECK(!world.sweep_capsule(
        Vec3{-137.282f, -0.329f, 202.491f},
        Vec3{-143.782f, 6.271f, 150.991f},
        0.40f,
        1.80f).clear);
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
        run_installed_tomb_tests(fs::path(argv[1]));
        std::cout << "collision world tests passed\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
