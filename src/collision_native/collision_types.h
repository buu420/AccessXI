#pragma once

#include <cstdint>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <vector>

namespace accessxi::collision {

class CollisionError final : public std::runtime_error
{
public:
    using std::runtime_error::runtime_error;
};

struct FileIdentity final
{
    std::uint32_t size_low = 0;
    std::uint32_t size_high = 0;
    std::uint32_t write_time_low = 0;
    std::uint32_t write_time_high = 0;

    bool operator==(const FileIdentity&) const = default;
};

struct FileSnapshot final
{
    std::filesystem::path canonical_path;
    std::vector<std::uint8_t> bytes;
    FileIdentity identity;
    std::string sha256_hex;
};

struct Vec3 final
{
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
};

struct Triangle final
{
    std::uint32_t a = 0;
    std::uint32_t b = 0;
    std::uint32_t c = 0;
};

struct Bounds final
{
    Vec3 minimum;
    Vec3 maximum;
};

struct ParsedZoneMesh final
{
    std::uint32_t zone_id = 0;
    std::filesystem::path source_path;
    FileIdentity source_identity;
    std::string source_sha256;
    std::vector<Vec3> vertices;
    std::vector<Triangle> triangles;
    Bounds bounds;
    std::size_t geometry_instances = 0;
};

} // namespace accessxi::collision
