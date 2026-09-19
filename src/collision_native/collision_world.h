#pragma once

#include "collision_native/collision_types.h"
#include "collision_native/player_contact.h"

#include <cstdint>
#include <memory>
#include <optional>
#include <stop_token>
#include <vector>

namespace accessxi::collision {

struct SweepResult final
{
    bool clear = true;
    float fraction = 1.0f;
    Vec3 point;
    Vec3 normal;
    std::int32_t triangle_index = -1;
};

// A FINITE WORK ALLOWANCE FOR ONE ROUTE QUERY.
//
// The zone 197 contact profile replaces the capsule sweep with ground-following
// checks that cost far more: a waypoint the straight check rejects triggers a
// local grid search with many floor casts and pairwise stitching checks.
// Failed candidate corridors can repeat that cost across their waypoints. The
// addon therefore runs this profile on a background worker, with a shared finite
// allowance and cooperative cancellation for each query.
//
// The allowance is counted in WORK UNITS rather than wall-clock time on purpose:
// the same query must return the same route on a fast and a slow machine, or
// both the route cache and these tests become nondeterministic. One unit is one
// floor cast or one body resolve, the two primitives that dominate.
//
// A null budget pointer means unlimited, so existing callers and the offline
// probes are unaffected.
class ContactBudget final
{
public:
    // The optional stop token lets a query that nobody is waiting for any more
    // stop at the next charge instead of running to completion. A default token
    // never reports a stop, so synchronous callers are unaffected.
    explicit ContactBudget(std::uint64_t units, std::stop_token stop_token = {}) noexcept
        : remaining_(units)
        , stop_token_(std::move(stop_token))
    {
    }

    // Charges the allowance. Returns false once it is gone, and every caller
    // must then fail CLOSED -- an exhausted budget means "not proven walkable",
    // never "assume walkable". A cancellation is reported the same way, because
    // a canceled query has proven nothing either.
    bool spend(std::uint64_t units = 1u) noexcept
    {
        if (stop_token_.stop_requested())
        {
            canceled_ = true;
        }
        if (canceled_ || exhausted_ || units > remaining_)
        {
            remaining_ = 0;
            exhausted_ = true;
            return false;
        }
        remaining_ -= units;
        return true;
    }

    bool exhausted() const noexcept { return exhausted_; }
    // True only when a stop was requested, so an abandoned query is never
    // reported to the player as an exhausted allowance.
    bool canceled() const noexcept { return canceled_; }
    std::uint64_t remaining() const noexcept { return remaining_; }

private:
    std::uint64_t remaining_ = 0;
    bool exhausted_ = false;
    bool canceled_ = false;
    std::stop_token stop_token_;
};

// Sized from measurement rather than taste. See the comment at the definition
// in collision_world.cpp for the numbers this came from.
extern const std::uint64_t kPlayerContactQueryWorkUnits;

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

    // Cast down through the original collision triangles, independently of
    // the rasterized navigation surface. Back faces cannot act as floors.
    std::optional<Vec3> find_floor(const Vec3& feet, float vertical_extent) const;

    // Ground-following checks use the client's small contact body and settle
    // it on the original DAT surface before checking movement. They are used
    // only by terrain profiles explicitly validated with that controller.
    bool player_walk_segment(
        const Vec3& start, const Vec3& end, ContactBudget* budget = nullptr) const;
    bool player_contact_segment(
        const Vec3& start, const Vec3& end, ContactBudget* budget = nullptr) const;
    std::vector<Vec3> player_local_detour(
        const Vec3& start, const Vec3& end, std::size_t maximum_points,
        ContactBudget* budget = nullptr) const;
    std::vector<Vec3> player_segment_detour(
        const Vec3& start, const Vec3& end, std::size_t maximum_points,
        ContactBudget* budget = nullptr) const;

private:
    // The gathered triangle set is passed in so one local search reuses a single
    // broadphase query instead of repeating it for every stitch check.
    bool walk_segment_with(
        const Vec3& start, const Vec3& end,
        const std::vector<PlayerContactTriangle>& triangles, ContactBudget* budget) const;
    bool contact_segment_with(
        const Vec3& start, const Vec3& end,
        const std::vector<PlayerContactTriangle>& triangles, ContactBudget* budget) const;

    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace accessxi::collision
