#pragma once

#include "collision_native/collision_types.h"

#include <cstdint>
#include <stop_token>

namespace accessxi::collision {

enum class TriangleDisposition
{
    keep,
    flip,
    collapsed,
};

TriangleDisposition classify_transformed_triangle(
    const Vec3& a,
    const Vec3& b,
    const Vec3& c,
    bool singular,
    float determinant);

ParsedZoneMesh parse_zone_collision(
    const FileSnapshot& snapshot,
    std::uint32_t zone_id,
    std::stop_token stop_token = {});

} // namespace accessxi::collision
