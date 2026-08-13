#include "collision_native/collision_context.h"

#include "collision_native/collision_types.h"
#include "collision_native/collision_world.h"
#include "collision_native/file_snapshot.h"
#include "collision_native/mzb_parser.h"
#include "collision_native/recast_zone.h"
#include "collision_native/rom_resolver.h"

#include <algorithm>
#include <cstring>
#include <filesystem>
#include <memory>
#include <string>
#include <system_error>
#include <utility>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace accessxi::collision {
namespace {

template <std::size_t Size>
void copy_text(char (&destination)[Size], const std::string& source) noexcept
{
    static_assert(Size > 0u);
    const std::size_t count = std::min(source.size(), Size - 1u);
    if (count != 0u)
    {
        std::memcpy(destination, source.data(), count);
    }
    destination[count] = '\0';
}

Vec3 copy_vector(const AXIVec3 value)
{
    return Vec3{value.x, value.y, value.z};
}

AXIVec3 copy_vector(const Vec3 value)
{
    return AXIVec3{value.x, value.y, value.z};
}

} // namespace

struct CollisionContext::LoadedZone final
{
    LoadedZone(
        const std::uint32_t id,
        std::string accepted_sha256,
        ParsedZoneMesh parsed_mesh,
        const std::stop_token stop_token)
        : zone_id(id),
          dat_sha256(std::move(accepted_sha256)),
          collision_world(parsed_mesh),
          recast_zone(parsed_mesh, collision_world, stop_token)
    {
    }

    std::uint32_t zone_id;
    std::string dat_sha256;
    CollisionWorld collision_world;
    RecastZone recast_zone;
};

CollisionContext::CollisionContext() = default;

CollisionContext::~CollisionContext()
{
    for (std::jthread& worker : workers_)
    {
        worker.request_stop();
    }
    workers_.clear();
}

std::int32_t CollisionContext::begin_load(
    const std::uint32_t zone_id,
    const std::filesystem::path& ffxi_root,
    const std::filesystem::path& cache_root,
    std::uint64_t& generation)
{
    if (zone_id == 0u || !ffxi_root.is_absolute())
    {
        return AXI_RESULT_INVALID_ARGUMENT;
    }

    {
        const std::lock_guard<std::mutex> lock(mutex_);
        if ((state_ == AXI_LOAD_PENDING || state_ == AXI_LOAD_READY)
            && zone_id_ == zone_id
            && ffxi_root_ == ffxi_root)
        {
            generation = generation_;
            return AXI_RESULT_OK;
        }
        for (std::jthread& worker : workers_)
        {
            worker.request_stop();
        }
        ++generation_;
        if (generation_ == 0u)
        {
            ++generation_;
        }
        generation = generation_;
        zone_id_ = zone_id;
        ffxi_root_ = ffxi_root;
        ready_.reset();
        state_ = AXI_LOAD_PENDING;
        progress_ = 1u;
        message_ = "Reading installed FFXI terrain.";
        dat_sha256_.clear();
    }

    workers_.emplace_back(
        [this, generation, zone_id, ffxi_root, cache_root](const std::stop_token stop_token) {
            run_worker(stop_token, generation, zone_id, ffxi_root, cache_root);
        });
    return AXI_RESULT_OK;
}

std::int32_t CollisionContext::cancel(const std::uint64_t generation)
{
    const std::lock_guard<std::mutex> lock(mutex_);
    if (generation != generation_)
    {
        return AXI_RESULT_STALE_GENERATION;
    }
    for (std::jthread& worker : workers_)
    {
        worker.request_stop();
    }
    ready_.reset();
    state_ = AXI_LOAD_CANCELED;
    progress_ = 0u;
    message_ = "Terrain mapping was canceled.";
    return AXI_RESULT_OK;
}

void CollisionContext::update_pending(
    const std::uint64_t generation,
    const std::uint32_t progress,
    std::string message)
{
    const std::lock_guard<std::mutex> lock(mutex_);
    if (generation == generation_ && state_ == AXI_LOAD_PENDING)
    {
        progress_ = progress;
        message_ = std::move(message);
    }
}

void CollisionContext::run_worker(
    const std::stop_token stop_token,
    const std::uint64_t generation,
    const std::uint32_t zone_id,
    std::filesystem::path ffxi_root,
    std::filesystem::path cache_root)
{
    try
    {
        // Terrain extraction is deliberately background work. Keep it below
        // the game/render threads so the first map of a zone does not make
        // movement or speech feel sluggish.
        (void)SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
        if (!cache_root.empty())
        {
            std::error_code error;
            std::filesystem::create_directories(cache_root, error);
            if (error)
            {
                throw CollisionError("Terrain cache directory is unavailable.");
            }
        }
        const auto dat_path = resolve_zone_model_dat(ffxi_root, zone_id);
        FileSnapshot snapshot = read_stable_snapshot(dat_path);
        if (stop_token.stop_requested())
        {
            return;
        }
        update_pending(generation, 25u, "Decoding installed FFXI collision geometry.");
        ParsedZoneMesh mesh = parse_zone_collision(snapshot, zone_id, stop_token);
        std::string accepted_sha256 = snapshot.sha256_hex;
        // The parser has accepted and hashed these exact DAT bytes.  Release
        // the large input snapshot before Recast allocates its tile working
        // sets inside FFXI's constrained 32-bit address space.
        std::vector<std::uint8_t>().swap(snapshot.bytes);
        if (stop_token.stop_requested())
        {
            return;
        }
        update_pending(generation, 55u, "Building player-sized walkable terrain.");
        auto loaded = std::make_shared<LoadedZone>(
            zone_id,
            std::move(accepted_sha256),
            std::move(mesh),
            stop_token);
        if (stop_token.stop_requested())
        {
            return;
        }

        const std::lock_guard<std::mutex> lock(mutex_);
        if (generation == generation_ && state_ == AXI_LOAD_PENDING)
        {
            dat_sha256_ = loaded->dat_sha256;
            ready_ = std::move(loaded);
            progress_ = 100u;
            state_ = AXI_LOAD_READY;
            message_ = "Installed FFXI terrain is ready.";
        }
    }
    catch (const std::exception& error)
    {
        const std::lock_guard<std::mutex> lock(mutex_);
        if (generation == generation_ && state_ == AXI_LOAD_PENDING)
        {
            ready_.reset();
            progress_ = 0u;
            state_ = AXI_LOAD_FAILED;
            message_ = error.what();
        }
    }
}

std::int32_t CollisionContext::poll(
    const std::uint64_t generation,
    AXILoadStatus& status) const
{
    const std::lock_guard<std::mutex> lock(mutex_);
    if (generation != generation_)
    {
        return AXI_RESULT_STALE_GENERATION;
    }
    status.state = state_;
    status.zone_id = zone_id_;
    status.progress_percent = progress_;
    status.generation = generation_;
    copy_text(status.message, message_);
    copy_text(status.dat_sha256, dat_sha256_);
    copy_text(status.settings_sha256, RecastZone::settings_digest());
    return AXI_RESULT_OK;
}

std::shared_ptr<const CollisionContext::LoadedZone> CollisionContext::ready_zone(
    const std::uint64_t generation,
    std::int32_t& result) const
{
    const std::lock_guard<std::mutex> lock(mutex_);
    if (generation != generation_)
    {
        result = AXI_RESULT_STALE_GENERATION;
        return {};
    }
    if (state_ != AXI_LOAD_READY || ready_ == nullptr)
    {
        result = AXI_RESULT_NOT_READY;
        return {};
    }
    result = AXI_RESULT_OK;
    return ready_;
}

std::int32_t CollisionContext::sweep(
    const std::uint64_t generation,
    const AXIVec3 start,
    const AXIVec3 end,
    const float radius,
    const float height,
    AXISweepResult& result) const
{
    std::int32_t code = AXI_RESULT_OK;
    const auto loaded = ready_zone(generation, code);
    if (loaded == nullptr)
    {
        return code;
    }
    const SweepResult value = loaded->collision_world.sweep_capsule(
        copy_vector(start),
        copy_vector(end),
        radius,
        height);
    result.clear = value.clear ? 1 : 0;
    result.fraction = value.fraction;
    result.point = copy_vector(value.point);
    result.normal = copy_vector(value.normal);
    result.triangle_index = value.triangle_index;
    return AXI_RESULT_OK;
}

std::int32_t CollisionContext::find_path(
    const std::uint64_t generation,
    const AXIVec3 start,
    const AXIVec3 destination,
    const float arrival_radius,
    AXIVec3* points,
    const std::uint32_t capacity,
    AXIPathResult& result) const
{
    if (points == nullptr || capacity == 0u)
    {
        return AXI_RESULT_INVALID_ARGUMENT;
    }
    std::int32_t code = AXI_RESULT_OK;
    const auto loaded = ready_zone(generation, code);
    if (loaded == nullptr)
    {
        return code;
    }
    const PathResult path = loaded->recast_zone.find_path(
        copy_vector(start),
        copy_vector(destination),
        arrival_radius,
        capacity);
    result.status = path.status == PathStatus::ready ? AXI_PATH_READY : AXI_PATH_UNREACHABLE;
    result.point_count = static_cast<std::uint32_t>(path.points.size());
    result.total_length = path.total_length;
    result.projected_start = copy_vector(path.projected_start);
    result.projected_end = copy_vector(path.projected_end);
    copy_text(result.reason, path.reason);
    if (path.points.size() > capacity)
    {
        return AXI_RESULT_BUFFER_TOO_SMALL;
    }
    for (std::size_t index = 0; index < path.points.size(); ++index)
    {
        points[index] = copy_vector(path.points[index]);
    }
    return AXI_RESULT_OK;
}

} // namespace accessxi::collision
