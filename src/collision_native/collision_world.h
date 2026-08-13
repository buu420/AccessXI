#pragma once

#include "collision_native/collision_types.h"

#include <cstdint>
#include <memory>

namespace accessxi::collision {

struct SweepResult final
{
    bool clear = true;
    float fraction = 1.0f;
    Vec3 point;
    Vec3 normal;
    std::int32_t triangle_index = -1;
};

class CollisionWorld final
{
public:
    explicit CollisionWorld(const ParsedZoneMesh& mesh);
    ~CollisionWorld();

    CollisionWorld(const CollisionWorld&) = delete;
    CollisionWorld& operator=(const CollisionWorld&) = delete;
    CollisionWorld(CollisionWorld&&) noexcept;
    CollisionWorld& operator=(CollisionWorld&&) noexcept;

    SweepResult sweep_capsule(
        const Vec3& start_feet,
        const Vec3& end_feet,
        float radius,
        float height) const;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace accessxi::collision
