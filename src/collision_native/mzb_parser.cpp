#include "collision_native/mzb_parser.h"

#include "collision_native/mzb_key_table.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace accessxi::collision {

TriangleDisposition classify_transformed_triangle(
    const Vec3& a,
    const Vec3& b,
    const Vec3& c,
    const bool singular,
    const float determinant)
{
    const Vec3 ab{b.x - a.x, b.y - a.y, b.z - a.z};
    const Vec3 ac{c.x - a.x, c.y - a.y, c.z - a.z};
    const Vec3 bc{c.x - b.x, c.y - b.y, c.z - b.z};
    const Vec3 normal{
        ab.y * ac.z - ab.z * ac.y,
        ab.z * ac.x - ab.x * ac.z,
        ab.x * ac.y - ab.y * ac.x,
    };
    const auto length_squared = [](const Vec3& value) {
        return value.x * value.x + value.y * value.y + value.z * value.z;
    };
    const float normal_length_squared = length_squared(normal);
    const float max_edge_squared = std::max({length_squared(ab), length_squared(ac), length_squared(bc), 1.0f});
    const float collapse_limit = 1.0e-12f * max_edge_squared * max_edge_squared;
    if (!std::isfinite(normal.x)
        || !std::isfinite(normal.y)
        || !std::isfinite(normal.z)
        || !std::isfinite(normal_length_squared)
        || !std::isfinite(max_edge_squared)
        || !std::isfinite(collapse_limit)
        || normal_length_squared <= collapse_limit)
    {
        return TriangleDisposition::collapsed;
    }
    if (!singular)
    {
        return determinant < 0.0f ? TriangleDisposition::flip : TriangleDisposition::keep;
    }
    return normal.y < -1.0e-6f * std::sqrt(normal_length_squared)
        ? TriangleDisposition::flip
        : TriangleDisposition::keep;
}

namespace {

constexpr std::uint32_t resource_type_mzb = 0x1cu;

void check_canceled(const std::stop_token stop_token)
{
    if (stop_token.stop_requested())
    {
        throw CollisionError("Terrain mapping was canceled.");
    }
}

template <typename T>
T read_value(const std::vector<std::uint8_t>& bytes, const std::size_t offset, const char* label)
{
    static_assert(std::is_trivially_copyable_v<T>);
    if (offset > bytes.size() || bytes.size() - offset < sizeof(T))
    {
        throw CollisionError(std::string(label) + " is outside the MZB buffer.");
    }
    T value{};
    std::memcpy(&value, bytes.data() + offset, sizeof(T));
    return value;
}

std::size_t positive_offset(
    const std::vector<std::uint8_t>& bytes,
    const std::size_t field_offset,
    const char* label)
{
    const std::int32_t value = read_value<std::int32_t>(bytes, field_offset, label);
    if (value <= 0 || static_cast<std::uint64_t>(value) >= bytes.size())
    {
        throw CollisionError(std::string(label) + " is invalid.");
    }
    return static_cast<std::size_t>(value);
}

void require_range(
    const std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const std::size_t length,
    const char* label)
{
    if (offset > bytes.size() || length > bytes.size() - offset)
    {
        throw CollisionError(std::string(label) + " is truncated.");
    }
}

void decode_mzb(std::vector<std::uint8_t>& bytes, const std::stop_token stop_token)
{
    require_range(bytes, 0u, 8u, "MZB decode header");
    if (bytes[3] < 0x1bu)
    {
        return;
    }

    const std::size_t decode_length = read_value<std::uint32_t>(bytes, 0u, "MZB decode length") & 0x00ffffffu;
    if (decode_length < 8u || decode_length > bytes.size())
    {
        throw CollisionError("MZB decode length is invalid.");
    }

    int key = static_cast<int>(mzb_key_table[bytes[7] ^ 0xffu]);
    int key_count = 0;
    for (std::size_t position = 8u; position < decode_length;)
    {
        if ((position & 0xffffu) == 0u)
        {
            check_canceled(stop_token);
        }
        const std::size_t xor_length = static_cast<std::size_t>(((key >> 4) & 7) + 16);
        if ((key & 1) != 0 && xor_length < decode_length - position)
        {
            for (std::size_t index = 0; index < xor_length; ++index)
            {
                bytes[position + index] ^= 0xffu;
            }
        }
        key += ++key_count;
        if (xor_length > decode_length - position)
        {
            break;
        }
        position += xor_length;
    }

    const std::size_t node_count = read_value<std::uint32_t>(bytes, 4u, "MZB node count") & 0x00ffffffu;
    constexpr std::size_t node_start = 0x20u;
    constexpr std::size_t node_stride = 0x64u;
    constexpr std::size_t node_decode_bytes = 16u;
    if (node_count > (bytes.size() - std::min(bytes.size(), node_start)) / node_stride)
    {
        throw CollisionError("MZB node table is truncated.");
    }
    for (std::size_t node = 0; node < node_count; ++node)
    {
        if ((node & 0x3ffu) == 0u)
        {
            check_canceled(stop_token);
        }
        const std::size_t offset = node_start + node * node_stride;
        require_range(bytes, offset, node_decode_bytes, "MZB node");
        for (std::size_t index = 0; index < node_decode_bytes; ++index)
        {
            bytes[offset + index] ^= 0x55u;
        }
    }
}

void update_bounds(Bounds& bounds, const Vec3& vertex)
{
    bounds.minimum.x = std::min(bounds.minimum.x, vertex.x);
    bounds.minimum.y = std::min(bounds.minimum.y, vertex.y);
    bounds.minimum.z = std::min(bounds.minimum.z, vertex.z);
    bounds.maximum.x = std::max(bounds.maximum.x, vertex.x);
    bounds.maximum.y = std::max(bounds.maximum.y, vertex.y);
    bounds.maximum.z = std::max(bounds.maximum.z, vertex.z);
}

void append_geometry(
    const std::vector<std::uint8_t>& bytes,
    const std::size_t transform_offset,
    const std::size_t geometry_offset,
    ParsedZoneMesh& result,
    const std::stop_token stop_token)
{
    require_range(bytes, transform_offset, 16u * sizeof(float), "MZB transform");
    require_range(bytes, geometry_offset, 16u, "MZB geometry header");

    std::array<float, 16> matrix{};
    for (std::size_t index = 0; index < matrix.size(); ++index)
    {
        matrix[index] = read_value<float>(bytes, transform_offset + index * sizeof(float), "MZB transform value");
        if (!std::isfinite(matrix[index]))
        {
            throw CollisionError("MZB transform contains a nonfinite value.");
        }
    }

    const std::size_t vertices_offset = positive_offset(bytes, geometry_offset, "MZB vertex offset");
    const std::size_t normals_offset = positive_offset(bytes, geometry_offset + 4u, "MZB normal offset");
    const std::size_t triangles_offset = positive_offset(bytes, geometry_offset + 8u, "MZB triangle offset");
    const std::int16_t signed_triangle_count = read_value<std::int16_t>(
        bytes,
        geometry_offset + 12u,
        "MZB triangle count");

    if (normals_offset <= vertices_offset || (normals_offset - vertices_offset) % 12u != 0u)
    {
        throw CollisionError("MZB vertex range is invalid.");
    }
    if (triangles_offset < normals_offset || (triangles_offset - normals_offset) % 12u != 0u)
    {
        throw CollisionError("MZB normal range is invalid.");
    }
    if (signed_triangle_count <= 0)
    {
        throw CollisionError("MZB triangle count is invalid.");
    }

    const std::size_t vertex_count = (normals_offset - vertices_offset) / 12u;
    const std::size_t triangle_count = static_cast<std::size_t>(signed_triangle_count);
    if (vertex_count == 0u || vertex_count > 0x4000u)
    {
        throw CollisionError("MZB vertex count is invalid.");
    }
    require_range(bytes, vertices_offset, vertex_count * 12u, "MZB vertices");
    require_range(bytes, triangles_offset, triangle_count * 8u, "MZB triangles");
    const float determinant =
        matrix[0] * (matrix[5] * matrix[10] - matrix[6] * matrix[9])
        - matrix[1] * (matrix[4] * matrix[10] - matrix[6] * matrix[8])
        + matrix[2] * (matrix[4] * matrix[9] - matrix[5] * matrix[8]);
    if (!std::isfinite(determinant))
    {
        throw CollisionError("MZB transform is singular.");
    }
    const bool singular = std::fabs(determinant) < 1.0e-12f;

    std::vector<Vec3> staged_vertices;
    staged_vertices.reserve(vertex_count);
    for (std::size_t index = 0; index < vertex_count; ++index)
    {
        if ((index & 0xffu) == 0u)
        {
            check_canceled(stop_token);
        }
        const std::size_t offset = vertices_offset + index * 12u;
        const float x = read_value<float>(bytes, offset, "MZB vertex X");
        const float y = read_value<float>(bytes, offset + 4u, "MZB vertex Y");
        const float z = read_value<float>(bytes, offset + 8u, "MZB vertex Z");
        if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z))
        {
            throw CollisionError("MZB vertex contains a nonfinite value.");
        }

        const Vec3 transformed{
            matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12],
            -(matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13]),
            matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14],
        };
        if (!std::isfinite(transformed.x)
            || !std::isfinite(transformed.y)
            || !std::isfinite(transformed.z)
            || transformed.z <= -99329.0f)
        {
            throw CollisionError("MZB transformed vertex is invalid.");
        }
        staged_vertices.push_back(transformed);
    }

    std::vector<Triangle> staged_triangles;
    staged_triangles.reserve(triangle_count);
    for (std::size_t index = 0; index < triangle_count; ++index)
    {
        if ((index & 0xffu) == 0u)
        {
            check_canceled(stop_token);
        }
        const std::size_t offset = triangles_offset + index * 8u;
        std::array<std::uint32_t, 3> local{
            static_cast<std::uint32_t>(read_value<std::uint16_t>(bytes, offset, "MZB triangle A") & 0x3fffu),
            static_cast<std::uint32_t>(read_value<std::uint16_t>(bytes, offset + 2u, "MZB triangle B") & 0x3fffu),
            static_cast<std::uint32_t>(read_value<std::uint16_t>(bytes, offset + 4u, "MZB triangle C") & 0x3fffu),
        };
        if (local[0] >= vertex_count || local[1] >= vertex_count || local[2] >= vertex_count)
        {
            throw CollisionError("MZB triangle references an invalid vertex.");
        }
        const TriangleDisposition disposition = classify_transformed_triangle(
            staged_vertices[local[0]],
            staged_vertices[local[1]],
            staged_vertices[local[2]],
            singular,
            determinant);
        if (disposition == TriangleDisposition::collapsed)
        {
            continue;
        }
        if (disposition == TriangleDisposition::flip)
        {
            std::swap(local[0], local[2]);
        }
        staged_triangles.push_back(Triangle{local[0], local[1], local[2]});
    }

    if (staged_triangles.empty())
    {
        return;
    }
    if (result.vertices.size() > std::numeric_limits<std::uint32_t>::max() - vertex_count)
    {
        throw CollisionError("MZB vertex index space is exhausted.");
    }

    const std::uint32_t base_vertex = static_cast<std::uint32_t>(result.vertices.size());
    for (const Vec3& vertex : staged_vertices)
    {
        result.vertices.push_back(vertex);
        update_bounds(result.bounds, vertex);
    }
    for (const Triangle& triangle : staged_triangles)
    {
        result.triangles.push_back(Triangle{
            base_vertex + triangle.a,
            base_vertex + triangle.b,
            base_vertex + triangle.c,
        });
    }
    ++result.geometry_instances;
}

void parse_mzb_payload(
    std::vector<std::uint8_t> bytes,
    ParsedZoneMesh& result,
    const std::stop_token stop_token)
{
    decode_mzb(bytes, stop_token);
    require_range(bytes, 0u, 0x20u, "MZB header");

    std::size_t mesh_field = 8u;
    while (mesh_field + sizeof(std::int32_t) <= bytes.size()
        && read_value<std::int32_t>(bytes, mesh_field, "MZB mesh offset") == 0)
    {
        mesh_field += sizeof(std::int32_t);
    }
    if (mesh_field + sizeof(std::int32_t) > bytes.size())
    {
        throw CollisionError("MZB mesh offset is missing.");
    }
    const std::size_t mesh_offset = positive_offset(bytes, mesh_field, "MZB mesh offset");
    require_range(bytes, mesh_offset, 0x14u, "MZB mesh header");
    const std::size_t grid_offset = positive_offset(bytes, mesh_offset + 0x10u, "MZB grid offset");

    const std::size_t columns = static_cast<std::size_t>(bytes[0x0cu]) * 10u;
    const std::size_t rows = static_cast<std::size_t>(bytes[0x0du]) * 10u;
    if (columns == 0u || rows == 0u || columns > 4096u || rows > 4096u)
    {
        throw CollisionError("MZB grid dimensions are invalid.");
    }
    if (columns > std::numeric_limits<std::size_t>::max() / rows)
    {
        throw CollisionError("MZB grid dimensions overflow.");
    }
    const std::size_t cell_count = columns * rows;
    require_range(bytes, grid_offset, cell_count * sizeof(std::int32_t), "MZB grid");

    // A zone can reference tens of thousands of small geometry instances.
    // Collect them contiguously, then sort/deduplicate once.  A node-based set
    // and exact-size reserve before every instance fragmented FFXI's 32-bit
    // address space and made East Ronfaure end in std::bad_alloc.
    std::vector<std::pair<std::size_t, std::size_t>> geometry_pairs;
    for (std::size_t cell = 0; cell < cell_count; ++cell)
    {
        if ((cell & 0x3ffu) == 0u)
        {
            check_canceled(stop_token);
        }
        const std::int32_t signed_entry_offset = read_value<std::int32_t>(
            bytes,
            grid_offset + cell * sizeof(std::int32_t),
            "MZB grid entry");
        if (signed_entry_offset == 0)
        {
            continue;
        }
        if (signed_entry_offset < 0 || static_cast<std::uint64_t>(signed_entry_offset) >= bytes.size())
        {
            throw CollisionError("MZB grid entry offset is invalid.");
        }

        std::size_t cursor = static_cast<std::size_t>(signed_entry_offset);
        std::vector<std::int32_t> entries;
        for (;;)
        {
            const std::int32_t value = read_value<std::int32_t>(bytes, cursor, "MZB grid entry list");
            cursor += sizeof(std::int32_t);
            if (value == 0)
            {
                break;
            }
            entries.push_back(value);
            if (entries.size() > bytes.size() / sizeof(std::int32_t))
            {
                throw CollisionError("MZB grid entry list is unterminated.");
            }
        }
        if (entries.empty())
        {
            continue;
        }
        if ((entries.size() - 1u) % 2u != 0u)
        {
            throw CollisionError("MZB grid entry list has an incomplete geometry pair.");
        }
        for (std::size_t index = 1u; index < entries.size(); index += 2u)
        {
            if (entries[index] <= 0 || entries[index + 1u] <= 0)
            {
                throw CollisionError("MZB grid geometry pair has an invalid offset.");
            }
            const std::pair<std::size_t, std::size_t> pair{
                static_cast<std::size_t>(entries[index]),
                static_cast<std::size_t>(entries[index + 1u]),
            };
            if (pair.first >= bytes.size() || pair.second >= bytes.size())
            {
                throw CollisionError("MZB grid geometry pair is outside the buffer.");
            }
            geometry_pairs.push_back(pair);
        }
    }

    std::sort(geometry_pairs.begin(), geometry_pairs.end());
    geometry_pairs.erase(
        std::unique(geometry_pairs.begin(), geometry_pairs.end()),
        geometry_pairs.end());

    if (geometry_pairs.empty())
    {
        throw CollisionError("MZB contains no referenced collision geometry.");
    }
    for (const auto& [transform_offset, geometry_offset] : geometry_pairs)
    {
        check_canceled(stop_token);
        append_geometry(bytes, transform_offset, geometry_offset, result, stop_token);
    }
}

} // namespace

ParsedZoneMesh parse_zone_collision(
    const FileSnapshot& snapshot,
    const std::uint32_t zone_id,
    const std::stop_token stop_token)
{
    if (zone_id == 0u || snapshot.bytes.empty())
    {
        throw CollisionError("Zone collision source is empty or has an invalid zone ID.");
    }

    ParsedZoneMesh result;
    result.zone_id = zone_id;
    result.source_path = snapshot.canonical_path;
    result.source_identity = snapshot.identity;
    result.source_sha256 = snapshot.sha256_hex;
    const float infinity = std::numeric_limits<float>::infinity();
    result.bounds.minimum = Vec3{infinity, infinity, infinity};
    result.bounds.maximum = Vec3{-infinity, -infinity, -infinity};

    bool found_mzb = false;
    std::size_t position = 0u;
    while (position < snapshot.bytes.size())
    {
        check_canceled(stop_token);
        if (snapshot.bytes.size() - position < 16u)
        {
            throw CollisionError("DAT chunk header is truncated.");
        }
        const std::uint32_t value = read_value<std::uint32_t>(snapshot.bytes, position + 4u, "DAT chunk value");
        const std::uint32_t units = (value >> 7u) & 0x7ffffu;
        if (units == 0u)
        {
            throw CollisionError("DAT chunk size is zero.");
        }
        const std::size_t total_size = static_cast<std::size_t>(units) * 16u;
        if (total_size < 16u || total_size > snapshot.bytes.size() - position)
        {
            throw CollisionError("DAT chunk extends beyond the accepted source bytes.");
        }
        const std::size_t payload_size = total_size - 16u;
        if ((value & 0x7fu) == resource_type_mzb)
        {
            std::vector<std::uint8_t> payload(payload_size);
            std::copy_n(
                snapshot.bytes.begin() + static_cast<std::ptrdiff_t>(position + 16u),
                static_cast<std::ptrdiff_t>(payload_size),
                payload.begin());
            parse_mzb_payload(std::move(payload), result, stop_token);
            found_mzb = true;
        }
        position += total_size;
    }

    if (!found_mzb || result.vertices.empty() || result.triangles.empty())
    {
        throw CollisionError("DAT contains no usable MZB collision geometry.");
    }
    return result;
}

} // namespace accessxi::collision
