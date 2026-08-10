#pragma once

#include <cstdint>
#include <filesystem>

namespace accessxi::collision {

std::uint32_t zone_model_file_id(std::uint32_t zone_id);
std::filesystem::path resolve_zone_model_dat(
    const std::filesystem::path& ffxi_root,
    std::uint32_t zone_id);

} // namespace accessxi::collision
