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

} // namespace accessxi::collision
