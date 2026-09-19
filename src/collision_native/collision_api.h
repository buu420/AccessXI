#pragma once

#include <cstdint>

#if !defined(_WIN32)
#error AccessXI collision navigation currently supports Windows only.
#endif

#if defined(ACCESSXI_COLLISION_NATIVE_EXPORTS)
#define AXI_COLLISION_API __declspec(dllexport)
#else
#define AXI_COLLISION_API __declspec(dllimport)
#endif

#define AXI_COLLISION_CALL __cdecl

enum : std::int32_t
{
    AXI_RESULT_OK = 0,
    AXI_RESULT_INVALID_ARGUMENT = -1,
    AXI_RESULT_STALE_GENERATION = -2,
    AXI_RESULT_NOT_READY = -3,
    AXI_RESULT_BUFFER_TOO_SMALL = -4,
    AXI_RESULT_FAILED = -5,
};

enum : std::int32_t
{
    AXI_LOAD_IDLE = 0,
    AXI_LOAD_PENDING = 1,
    AXI_LOAD_READY = 2,
    AXI_LOAD_FAILED = 3,
    AXI_LOAD_CANCELED = 4,
};

enum : std::int32_t
{
    AXI_PATH_UNREACHABLE = 0,
    AXI_PATH_READY = 1,
    // Only AXI_FindPathAsync reports this. The synchronous AXI_FindPath never
    // returns it, so an ABI 3 caller that only knows the first two values keeps
    // working unchanged.
    AXI_PATH_PENDING = 2,
};

struct AXIVec3 final
{
    float x;
    float y;
    float z;
};

#pragma pack(push, 4)
struct AXILoadStatus final
{
    std::uint32_t struct_size;
    std::int32_t state;
    std::uint32_t zone_id;
    std::uint32_t progress_percent;
    std::uint64_t generation;
    char message[256];
    char dat_sha256[65];
    char settings_sha256[65];
};
#pragma pack(pop)

static_assert(sizeof(AXILoadStatus) == 412u,
    "AXILoadStatus must match the explicitly packed LuaJIT FFI ABI.");

struct AXISweepResult final
{
    std::uint32_t struct_size;
    std::int32_t clear;
    float fraction;
    AXIVec3 point;
    AXIVec3 normal;
    std::int32_t triangle_index;
};

struct AXIPathResult final
{
    std::uint32_t struct_size;
    std::int32_t status;
    std::uint32_t point_count;
    float total_length;
    AXIVec3 projected_start;
    AXIVec3 projected_end;
    char reason[256];
};

extern "C"
{

AXI_COLLISION_API std::uint32_t AXI_COLLISION_CALL AXI_GetAbiVersion() noexcept;
AXI_COLLISION_API void* AXI_COLLISION_CALL AXI_CreateContext() noexcept;
AXI_COLLISION_API void AXI_COLLISION_CALL AXI_DestroyContext(void* context) noexcept;

AXI_COLLISION_API std::int32_t AXI_COLLISION_CALL AXI_BeginLoadZone(
    void* context,
    std::uint32_t zone_id,
    const wchar_t* ffxi_root,
    const wchar_t* cache_root,
    std::uint64_t* generation) noexcept;
AXI_COLLISION_API std::int32_t AXI_COLLISION_CALL AXI_CancelLoad(
    void* context,
    std::uint64_t generation) noexcept;
AXI_COLLISION_API std::int32_t AXI_COLLISION_CALL AXI_PollLoadZone(
    void* context,
    std::uint64_t generation,
    AXILoadStatus* status) noexcept;
AXI_COLLISION_API std::int32_t AXI_COLLISION_CALL AXI_SweepCapsule(
    void* context,
    std::uint64_t generation,
    AXIVec3 start,
    AXIVec3 end,
    float radius,
    float height,
    AXISweepResult* result) noexcept;
AXI_COLLISION_API std::int32_t AXI_COLLISION_CALL AXI_FindPath(
    void* context,
    std::uint64_t generation,
    AXIVec3 start,
    AXIVec3 destination,
    float arrival_radius,
    AXIVec3* points,
    std::uint32_t capacity,
    AXIPathResult* result) noexcept;

// ASYNCHRONOUS PATH QUERY.
//
// The zone 197 contact profile can spend seconds inside one query, and
// AXI_FindPath runs it on the calling thread -- which for the addon is the
// render thread. This starts the same query on one background worker per
// context and returns AXI_PATH_PENDING with no points written until it
// finishes; call it again with the SAME arguments to collect the result.
//
// Additive only: struct layouts and every existing export are unchanged, so the
// ABI version stays at 3 and a caller that never calls this sees no difference.
//
// Contract:
//   * A request whose (generation, start, destination, radius, capacity) differs
//     from the one in flight cancels that one and starts the new one. It can
//     never receive the older answer.
//   * At most one worker exists per context.
//   * Nothing is written through `points` until the result is collected, so the
//     buffer does not need to outlive the call that returns pending.
AXI_COLLISION_API std::int32_t AXI_COLLISION_CALL AXI_FindPathAsync(
    void* context,
    std::uint64_t generation,
    AXIVec3 start,
    AXIVec3 destination,
    float arrival_radius,
    AXIVec3* points,
    std::uint32_t capacity,
    AXIPathResult* result) noexcept;

// Abandons any in-flight asynchronous query for this generation. Safe to call
// when nothing is running.
AXI_COLLISION_API std::int32_t AXI_COLLISION_CALL AXI_CancelFindPath(
    void* context,
    std::uint64_t generation) noexcept;

}
