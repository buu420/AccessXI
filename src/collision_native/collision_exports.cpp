#include "collision_native/collision_api.h"

#include "collision_native/collision_context.h"

#include <filesystem>
#include <new>

namespace {

accessxi::collision::CollisionContext* checked_context(void* context) noexcept
{
    return static_cast<accessxi::collision::CollisionContext*>(context);
}

} // namespace

static_assert(sizeof(void*) == 4, "AccessXI collision navigation must be built for Win32/x86.");

extern "C" std::uint32_t AXI_COLLISION_CALL AXI_GetAbiVersion() noexcept
{
    return 3u;
}

extern "C" void* AXI_COLLISION_CALL AXI_CreateContext() noexcept
{
    return new (std::nothrow) accessxi::collision::CollisionContext{};
}

extern "C" void AXI_COLLISION_CALL AXI_DestroyContext(void* context) noexcept
{
    delete checked_context(context);
}

extern "C" std::int32_t AXI_COLLISION_CALL AXI_BeginLoadZone(
    void* context,
    const std::uint32_t zone_id,
    const wchar_t* ffxi_root,
    const wchar_t* cache_root,
    std::uint64_t* generation) noexcept
{
    if (context == nullptr || ffxi_root == nullptr || generation == nullptr)
    {
        return AXI_RESULT_INVALID_ARGUMENT;
    }
    try
    {
        const std::filesystem::path cache = cache_root == nullptr
            ? std::filesystem::path{}
            : std::filesystem::path(cache_root);
        return checked_context(context)->begin_load(zone_id, ffxi_root, cache, *generation);
    }
    catch (...)
    {
        return AXI_RESULT_FAILED;
    }
}

extern "C" std::int32_t AXI_COLLISION_CALL AXI_CancelLoad(
    void* context,
    const std::uint64_t generation) noexcept
{
    if (context == nullptr)
    {
        return AXI_RESULT_INVALID_ARGUMENT;
    }
    try
    {
        return checked_context(context)->cancel(generation);
    }
    catch (...)
    {
        return AXI_RESULT_FAILED;
    }
}

extern "C" std::int32_t AXI_COLLISION_CALL AXI_PollLoadZone(
    void* context,
    const std::uint64_t generation,
    AXILoadStatus* status) noexcept
{
    if (context == nullptr || status == nullptr || status->struct_size != sizeof(AXILoadStatus))
    {
        return AXI_RESULT_INVALID_ARGUMENT;
    }
    try
    {
        return checked_context(context)->poll(generation, *status);
    }
    catch (...)
    {
        return AXI_RESULT_FAILED;
    }
}

extern "C" std::int32_t AXI_COLLISION_CALL AXI_SweepCapsule(
    void* context,
    const std::uint64_t generation,
    const AXIVec3 start,
    const AXIVec3 end,
    const float radius,
    const float height,
    AXISweepResult* result) noexcept
{
    if (context == nullptr || result == nullptr || result->struct_size != sizeof(AXISweepResult))
    {
        return AXI_RESULT_INVALID_ARGUMENT;
    }
    try
    {
        return checked_context(context)->sweep(generation, start, end, radius, height, *result);
    }
    catch (...)
    {
        return AXI_RESULT_FAILED;
    }
}

extern "C" std::int32_t AXI_COLLISION_CALL AXI_FindPath(
    void* context,
    const std::uint64_t generation,
    const AXIVec3 start,
    const AXIVec3 destination,
    const float arrival_radius,
    AXIVec3* points,
    const std::uint32_t capacity,
    AXIPathResult* result) noexcept
{
    if (context == nullptr || result == nullptr || result->struct_size != sizeof(AXIPathResult))
    {
        return AXI_RESULT_INVALID_ARGUMENT;
    }
    try
    {
        return checked_context(context)->find_path(
            generation,
            start,
            destination,
            arrival_radius,
            points,
            capacity,
            *result);
    }
    catch (...)
    {
        return AXI_RESULT_FAILED;
    }
}
