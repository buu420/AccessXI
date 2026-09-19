#pragma once

#include "collision_native/collision_types.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <stop_token>
#include <string>
#include <vector>

namespace accessxi::collision {

class CollisionWorld;

float recast_raster_walkable_climb(std::uint32_t zone_id) noexcept;

enum class PathStatus
{
    ready,
    unreachable,
};

struct PathResult final
{
    PathStatus status = PathStatus::unreachable;
    std::vector<Vec3> points;
    Vec3 projected_start;
    Vec3 projected_end;
    float total_length = 0.0f;
    std::string settings_digest;
    std::string reason;
};

class RecastZone final
{
public:
    RecastZone(
        const ParsedZoneMesh& mesh,
        const CollisionWorld& collision_world,
        std::stop_token stop_token = {});
    ~RecastZone();

    RecastZone(const RecastZone&) = delete;
    RecastZone& operator=(const RecastZone&) = delete;
    RecastZone(RecastZone&&) noexcept;
    RecastZone& operator=(RecastZone&&) noexcept;

    // The optional stop token only affects the zone profiles that use the
    // player-contact checks; a default token never reports a stop, so every
    // existing synchronous caller behaves exactly as before.
    PathResult find_path(
        const Vec3& start,
        const Vec3& destination,
        float arrival_radius,
        std::size_t maximum_points,
        std::stop_token stop_token = {}) const;

    static const std::string& settings_digest();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace accessxi::collision
