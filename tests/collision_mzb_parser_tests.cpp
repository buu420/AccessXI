#include "collision_native/file_snapshot.h"
#include "collision_native/mzb_parser.h"
#include "collision_native/rom_resolver.h"

#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

namespace fs = std::filesystem;

namespace {

using accessxi::collision::FileSnapshot;
using accessxi::collision::ParsedZoneMesh;
using accessxi::collision::TriangleDisposition;
using accessxi::collision::Vec3;
using accessxi::collision::classify_transformed_triangle;
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

template <typename T>
void write_value(std::vector<std::uint8_t>& bytes, const std::size_t offset, const T value)
{
    static_assert(std::is_trivially_copyable_v<T>);
    CHECK(offset <= bytes.size());
    CHECK(sizeof(T) <= bytes.size() - offset);
    std::memcpy(bytes.data() + offset, &value, sizeof(T));
}

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

float triangle_area(const Vec3& a, const Vec3& b, const Vec3& c)
{
    const Vec3 normal = cross(subtract(b, a), subtract(c, a));
    return 0.5f * std::sqrt(dot(normal, normal));
}

bool approximately_equal(const float actual, const float expected, const float tolerance)
{
    return std::fabs(actual - expected) <= tolerance;
}

FileSnapshot synthetic_rank_reduction_snapshot()
{
    constexpr std::size_t payload_size = 768u;
    constexpr std::size_t mesh_offset = 32u;
    constexpr std::size_t grid_offset = 64u;
    constexpr std::size_t entry_list_offset = 464u;
    constexpr std::size_t rank_two_transform_offset = 512u;
    constexpr std::size_t rank_one_transform_offset = 576u;
    constexpr std::size_t geometry_offset = 640u;
    constexpr std::size_t vertices_offset = 656u;
    constexpr std::size_t normals_offset = 704u;
    constexpr std::size_t triangles_offset = 752u;

    std::vector<std::uint8_t> payload(payload_size, 0u);
    write_value<std::int32_t>(payload, 8u, static_cast<std::int32_t>(mesh_offset));
    payload[0x0cu] = 1u;
    payload[0x0du] = 1u;
    write_value<std::int32_t>(payload, mesh_offset + 0x10u, static_cast<std::int32_t>(grid_offset));
    write_value<std::int32_t>(payload, grid_offset, static_cast<std::int32_t>(entry_list_offset));

    const std::array<std::int32_t, 6> entries{
        1,
        static_cast<std::int32_t>(rank_two_transform_offset),
        static_cast<std::int32_t>(geometry_offset),
        static_cast<std::int32_t>(rank_one_transform_offset),
        static_cast<std::int32_t>(geometry_offset),
        0,
    };
    for (std::size_t index = 0; index < entries.size(); ++index)
    {
        write_value(payload, entry_list_offset + index * sizeof(std::int32_t), entries[index]);
    }

    std::array<float, 16> rank_two{};
    rank_two[0] = 1.0f;
    rank_two[5] = 1.0f;
    rank_two[15] = 1.0f;
    std::array<float, 16> rank_one{};
    rank_one[0] = 1.0f;
    rank_one[15] = 1.0f;
    for (std::size_t index = 0; index < rank_two.size(); ++index)
    {
        write_value(payload, rank_two_transform_offset + index * sizeof(float), rank_two[index]);
        write_value(payload, rank_one_transform_offset + index * sizeof(float), rank_one[index]);
    }

    write_value<std::int32_t>(payload, geometry_offset, static_cast<std::int32_t>(vertices_offset));
    write_value<std::int32_t>(payload, geometry_offset + 4u, static_cast<std::int32_t>(normals_offset));
    write_value<std::int32_t>(payload, geometry_offset + 8u, static_cast<std::int32_t>(triangles_offset));
    write_value<std::int16_t>(payload, geometry_offset + 12u, 2);

    const std::array<Vec3, 4> vertices{
        Vec3{0.0f, 0.0f, 0.0f},
        Vec3{2.0f, 0.0f, 0.0f},
        Vec3{2.0f, 2.0f, 0.0f},
        Vec3{0.0f, 2.0f, 0.0f},
    };
    for (std::size_t index = 0; index < vertices.size(); ++index)
    {
        const std::size_t offset = vertices_offset + index * 12u;
        write_value(payload, offset, vertices[index].x);
        write_value(payload, offset + 4u, vertices[index].y);
        write_value(payload, offset + 8u, vertices[index].z);
    }
    const std::array<std::uint16_t, 6> triangle_indices{0u, 1u, 2u, 0u, 2u, 3u};
    for (std::size_t triangle = 0; triangle < 2u; ++triangle)
    {
        const std::size_t offset = triangles_offset + triangle * 8u;
        write_value(payload, offset, triangle_indices[triangle * 3u]);
        write_value(payload, offset + 2u, triangle_indices[triangle * 3u + 1u]);
        write_value(payload, offset + 4u, triangle_indices[triangle * 3u + 2u]);
    }

    FileSnapshot snapshot;
    snapshot.canonical_path = L"C:\\synthetic\\rank-reduction.DAT";
    snapshot.bytes.resize(payload_size + 16u, 0u);
    const std::uint32_t units = static_cast<std::uint32_t>(snapshot.bytes.size() / 16u);
    write_value(snapshot.bytes, 4u, (units << 7u) | 0x1cu);
    std::memcpy(snapshot.bytes.data() + 16u, payload.data(), payload.size());
    return snapshot;
}

void run_synthetic_rank_reduction_tests()
{
    const Vec3 a{0.0f, 0.0f, 0.0f};
    const Vec3 b{2.0f, 0.0f, 0.0f};
    const Vec3 c{2.0f, -2.0f, 0.0f};
    const Vec3 d{0.0f, -2.0f, 0.0f};
    CHECK(classify_transformed_triangle(a, b, c, true, 0.0f) == TriangleDisposition::keep);
    CHECK(classify_transformed_triangle(a, c, d, true, 0.0f) == TriangleDisposition::keep);
    CHECK(classify_transformed_triangle(
        Vec3{0.0f, 0.0f, 0.0f},
        Vec3{1.0f, 0.0f, 0.0f},
        Vec3{2.0f, 0.0f, 0.0f},
        true,
        0.0f) == TriangleDisposition::collapsed);

    const ParsedZoneMesh mesh = parse_zone_collision(synthetic_rank_reduction_snapshot(), 1u);
    CHECK(mesh.geometry_instances == 1u);
    CHECK(mesh.vertices.size() == 4u);
    CHECK(mesh.triangles.size() == 2u);
    CHECK(approximately_equal(mesh.bounds.minimum.x, 0.0f, 0.0f));
    CHECK(approximately_equal(mesh.bounds.minimum.y, -2.0f, 0.0f));
    CHECK(approximately_equal(mesh.bounds.maximum.x, 2.0f, 0.0f));
    CHECK(approximately_equal(mesh.bounds.maximum.y, 0.0f, 0.0f));
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

void run_installed_mhaura_test(const fs::path& ffxi_root)
{
    const FileSnapshot snapshot = read_stable_snapshot(resolve_zone_model_dat(ffxi_root, 249u));
    CHECK(snapshot.sha256_hex == "43ed3f17ccfdb1092af9bed77ceaf54ece101bfb94764717fd4b37992f3bdc25");

    const ParsedZoneMesh mesh = parse_zone_collision(snapshot, 249u);
    CHECK(mesh.zone_id == 249u);
    CHECK(mesh.source_sha256 == snapshot.sha256_hex);
    CHECK(mesh.geometry_instances == 3010u);
    CHECK(mesh.vertices.size() == 31318u);
    CHECK(mesh.triangles.size() == 34885u);
    CHECK(approximately_equal(mesh.bounds.minimum.x, -83.787917f, 0.001f));
    CHECK(approximately_equal(mesh.bounds.minimum.y, -1.041260f, 0.001f));
    CHECK(approximately_equal(mesh.bounds.minimum.z, -40.0f, 0.001f));
    CHECK(approximately_equal(mesh.bounds.maximum.x, 80.0f, 0.001f));
    CHECK(approximately_equal(mesh.bounds.maximum.y, 61.357300f, 0.001f));
    CHECK(approximately_equal(mesh.bounds.maximum.z, 195.247002f, 0.001f));

    std::size_t rank_two_triangles = 0u;
    for (const auto& triangle : mesh.triangles)
    {
        const Vec3& a = mesh.vertices.at(triangle.a);
        const Vec3& b = mesh.vertices.at(triangle.b);
        const Vec3& c = mesh.vertices.at(triangle.c);
        const bool in_known_planar_region =
            a.x >= -24.001f && a.x <= -19.999f
            && b.x >= -24.001f && b.x <= -19.999f
            && c.x >= -24.001f && c.x <= -19.999f
            && a.y >= 12.999f && a.y <= 24.001f
            && b.y >= 12.999f && b.y <= 24.001f
            && c.y >= 12.999f && c.y <= 24.001f;
        if (in_known_planar_region && approximately_equal(triangle_area(a, b, c), 4.0f, 0.001f))
        {
            ++rank_two_triangles;
        }
    }
    CHECK(rank_two_triangles == 6u);

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
        run_synthetic_rank_reduction_tests();
        run_invalid_input_tests();
        run_installed_tomb_test(fs::path(argv[1]));
        run_installed_east_ronfaure_test(fs::path(argv[1]));
        run_installed_mhaura_test(fs::path(argv[1]));
        std::cout << "collision MZB parser tests passed\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
