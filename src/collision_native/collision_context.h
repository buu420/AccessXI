#pragma once

#include "collision_native/collision_api.h"

#include "collision_native/collision_types.h"
#include "collision_native/recast_zone.h"

#include <cstdint>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace accessxi::collision {

class CollisionContext final
{
public:
    CollisionContext();
    ~CollisionContext();

    CollisionContext(const CollisionContext&) = delete;
    CollisionContext& operator=(const CollisionContext&) = delete;

    std::int32_t begin_load(
        std::uint32_t zone_id,
        const std::filesystem::path& ffxi_root,
        const std::filesystem::path& cache_root,
        std::uint64_t& generation);
    std::int32_t cancel(std::uint64_t generation);
    std::int32_t poll(std::uint64_t generation, AXILoadStatus& status) const;
    std::int32_t sweep(
        std::uint64_t generation,
        AXIVec3 start,
        AXIVec3 end,
        float radius,
        float height,
        AXISweepResult& result) const;
    std::int32_t find_path(
        std::uint64_t generation,
        AXIVec3 start,
        AXIVec3 destination,
        float arrival_radius,
        AXIVec3* points,
        std::uint32_t capacity,
        AXIPathResult& result) const;
    // Not const: this one owns a worker and mutable request state.
    std::int32_t find_path_async(
        std::uint64_t generation,
        AXIVec3 start,
        AXIVec3 destination,
        float arrival_radius,
        AXIVec3* points,
        std::uint32_t capacity,
        AXIPathResult& result);
    std::int32_t cancel_find_path(std::uint64_t generation);

private:
    struct LoadedZone;

    // The exact inputs that identify one asynchronous query. Coordinates are
    // compared exactly: the caller repeats the same float values to collect a
    // result, and anything else is a different question.
    struct PathRequest final
    {
        std::uint64_t generation = 0u;
        Vec3 start{};
        Vec3 destination{};
        float arrival_radius = 0.0f;
        std::uint32_t capacity = 0u;

        bool operator==(const PathRequest& other) const noexcept
        {
            return generation == other.generation
                && capacity == other.capacity
                && arrival_radius == other.arrival_radius
                && start.x == other.start.x && start.y == other.start.y
                && start.z == other.start.z
                && destination.x == other.destination.x
                && destination.y == other.destination.y
                && destination.z == other.destination.z;
        }
    };

    void run_path_worker(
        std::stop_token stop_token,
        std::uint64_t job,
        std::shared_ptr<const LoadedZone> zone,
        PathRequest request);
    // Stops and joins any asynchronous query. Must be called with mutex_
    // UNLOCKED: joining a worker that is publishing its result would otherwise
    // deadlock on that same mutex.
    void stop_path_worker_unlocked();

    void update_pending(std::uint64_t generation, std::uint32_t progress, std::string message);
    void run_worker(
        std::stop_token stop_token,
        std::uint64_t generation,
        std::uint32_t zone_id,
        std::filesystem::path ffxi_root,
        std::filesystem::path cache_root);
    std::shared_ptr<const LoadedZone> ready_zone(std::uint64_t generation, std::int32_t& result) const;

    mutable std::mutex mutex_;
    std::vector<std::jthread> workers_;
    std::shared_ptr<const LoadedZone> ready_;
    std::uint64_t generation_ = 0u;
    std::uint32_t zone_id_ = 0u;
    std::uint32_t progress_ = 0u;
    std::int32_t state_ = AXI_LOAD_IDLE;
    std::filesystem::path ffxi_root_;
    std::string message_;
    std::string dat_sha256_;

    // Asynchronous path query state. `path_job_` rises on every new or canceled
    // request, and a worker publishes only when its own job is still current --
    // so a late answer to a question nobody asked can never be handed back.
    std::jthread path_worker_;
    PathRequest path_request_{};
    std::uint64_t path_job_ = 0u;
    bool path_running_ = false;
    bool path_ready_ = false;
    PathResult path_result_{};
};

} // namespace accessxi::collision
