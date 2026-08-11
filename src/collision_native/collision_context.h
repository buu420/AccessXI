#pragma once

#include "collision_native/collision_api.h"

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

private:
    struct LoadedZone;

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
};

} // namespace accessxi::collision
