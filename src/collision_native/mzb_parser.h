#pragma once

#include "collision_native/collision_types.h"

#include <cstdint>
#include <stop_token>

namespace accessxi::collision {

ParsedZoneMesh parse_zone_collision(
    const FileSnapshot& snapshot,
    std::uint32_t zone_id,
    std::stop_token stop_token = {});

} // namespace accessxi::collision
