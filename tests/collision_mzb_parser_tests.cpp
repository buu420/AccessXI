#include "collision_native/file_snapshot.h"
#include "collision_native/mzb_parser.h"
#include "collision_native/rom_resolver.h"

#include <cmath>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

namespace fs = std::filesystem;

namespace {

using accessxi::collision::FileSnapshot;
using accessxi::collision::ParsedZoneMesh;
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

Vec3 subtract(const Vec3& left, const Vec3& right)
{
    return Vec3{left.x - right.x, left.y - right.y, left.z - right.z};
}

Vec3 cross(const Vec3& left, const Vec3& right)
{
    return Vec3{
        left.y * right.z - left.z * right.y,
        left.z * right.x - left.x * right.z,
        left.x * right.y - left.y * right.x,
    };
}

float dot(const Vec3& left, const Vec3& right)
{
    return left.x * right.x + left.y * right.y + left.z * right.z;
}

bool segment_intersects_triangle(
    const Vec3& start,
    const Vec3& end,
    const Vec3& a,
    const Vec3& b,
    const Vec3& c)
{
    constexpr float epsilon = 1.0e-6f;
    const Vec3 direction = subtract(end, start);
    const Vec3 edge1 = subtract(b, a);
    const Vec3 edge2 = subtract(c, a);
    const Vec3 h = cross(direction, edge2);
    const float determinant = dot(edge1, h);
    if (std::fabs(determinant) < epsilon)
    {
        return false;
    }
    const float inverse = 1.0f / determinant;
    const Vec3 s = subtract(start, a);
    const float u = inverse * dot(s, h);
    if (u < -epsilon || u > 1.0f + epsilon)
    {
        return false;
    }
    const Vec3 q = cross(s, edge1);
    const float v = inverse * dot(direction, q);
    if (v < -epsilon || u + v > 1.0f + epsilon)
    {
        return false;
    }
    const float t = inverse * dot(edge2, q);
    return t >= -epsilon && t <= 1.0f + epsilon;
}

std::size_t segment_intersection_count(
    const ParsedZoneMesh& mesh,
    const Vec3& start,
    const Vec3& end)
{
    std::size_t count = 0;
    for (const auto& triangle : mesh.triangles)
    {
        if (segment_intersects_triangle(
                start,
                end,
                mesh.vertices.at(triangle.a),
                mesh.vertices.at(triangle.b),
                mesh.vertices.at(triangle.c)))
        {
            ++count;
        }
    }
    return count;
}

void run_invalid_input_tests()
{
    FileSnapshot empty;
    empty.canonical_path = L"C:\\synthetic\\empty.DAT";
    CHECK_THROWS(parse_zone_collision(empty, 190u));

    FileSnapshot truncated = empty;
    truncated.bytes.resize(15u, 0u);
    CHECK_THROWS(parse_zone_collision(truncated, 190u));

    FileSnapshot missing_mzb = empty;
    missing_mzb.bytes.resize(16u, 0u);
    CHECK_THROWS(parse_zone_collision(missing_mzb, 190u));
}

void run_installed_tomb_test(const fs::path& ffxi_root)
{
    const fs::path dat_path = resolve_zone_model_dat(ffxi_root, 190u);
    const FileSnapshot snapshot = read_stable_snapshot(dat_path);
    const ParsedZoneMesh mesh = parse_zone_collision(snapshot, 190u);

    CHECK(mesh.zone_id == 190u);
    CHECK(mesh.source_sha256 == snapshot.sha256_hex);
    CHECK(mesh.vertices.size() == 193918u);
    CHECK(mesh.triangles.size() == 216349u);
    CHECK(mesh.geometry_instances == 10297u);
    CHECK(mesh.bounds.minimum.x < -278.7f);
    CHECK(mesh.bounds.minimum.y < -9.0f);
    CHECK(mesh.bounds.minimum.z < -376.5f);
    CHECK(mesh.bounds.maximum.x > 287.9f);
    CHECK(mesh.bounds.maximum.y > 41.5f);
    CHECK(mesh.bounds.maximum.z > 349.9f);

    const std::size_t old_bad_hits = segment_intersection_count(
        mesh,
        Vec3{-136.382f, -1.129f, 202.791f},
        Vec3{-143.982f, 6.071f, 151.191f});
    CHECK(old_bad_hits >= 1u);

    const std::size_t current_bad_hits = segment_intersection_count(
        mesh,
        Vec3{-137.282f, -0.329f, 202.491f},
        Vec3{-143.782f, 6.271f, 150.991f});
    CHECK(current_bad_hits >= 1u);
}

void run_installed_east_ronfaure_test(const fs::path& ffxi_root)
{
    const FileSnapshot snapshot = read_stable_snapshot(resolve_zone_model_dat(ffxi_root, 101u));
    const ParsedZoneMesh mesh = parse_zone_collision(snapshot, 101u);

    // This large outdoor zone reproduced the in-game std::bad_alloc.  Pin its
    // installed geometry shape so a faster parser cannot silently omit the
    // repeated MZB instances that make the test meaningful.
    CHECK(mesh.zone_id == 101u);
    CHECK(mesh.source_sha256 == snapshot.sha256_hex);
    CHECK(mesh.vertices.size() == 447043u);
    CHECK(mesh.triangles.size() == 385748u);
    CHECK(mesh.geometry_instances == 65893u);
    CHECK(mesh.bounds.minimum.x < -279.9f);
    CHECK(mesh.bounds.minimum.y < -5.0f);
    CHECK(mesh.bounds.minimum.z < -719.9f);
    CHECK(mesh.bounds.maximum.x > 879.9f);
    CHECK(mesh.bounds.maximum.y > 101.9f);
    CHECK(mesh.bounds.maximum.z > 679.9f);
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
        run_invalid_input_tests();
        run_installed_tomb_test(fs::path(argv[1]));
        run_installed_east_ronfaure_test(fs::path(argv[1]));
        std::cout << "collision MZB parser tests passed\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
