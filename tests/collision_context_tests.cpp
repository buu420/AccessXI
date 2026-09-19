#include "collision_native/collision_api.h"

#include <chrono>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace fs = std::filesystem;

namespace {

void check(const bool condition, const char* expression, const int line)
{
    if (!condition)
    {
        throw std::runtime_error(
            std::string("CHECK failed at line ") + std::to_string(line) + ": " + expression);
    }
}

#define CHECK(expression) check(static_cast<bool>(expression), #expression, __LINE__)

void wait_for_ready(
    void* context,
    const std::uint64_t generation,
    const std::uint32_t expected_zone)
{
    for (int attempt = 0; attempt < 3600; ++attempt)
    {
        AXILoadStatus status{};
        status.struct_size = sizeof(status);
        CHECK(AXI_PollLoadZone(context, generation, &status) == AXI_RESULT_OK);
        CHECK(status.generation == generation);
        if (status.state == AXI_LOAD_READY)
        {
            CHECK(status.zone_id == expected_zone);
            CHECK(status.progress_percent == 100u);
            CHECK(status.dat_sha256[0] != '\0');
            CHECK(status.settings_sha256[0] != '\0');
            return;
        }
        if (status.state == AXI_LOAD_FAILED)
        {
            throw std::runtime_error(std::string("Collision worker failed: ") + status.message);
        }
        CHECK(status.state == AXI_LOAD_PENDING);
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
    }
    throw std::runtime_error("Collision worker did not become ready within 90 seconds.");
}

// ASYNCHRONOUS PATH QUERY CONTRACT.
//
// AXI_FindPathAsync exists because the zone 197 contact profile can spend
// seconds inside one query and AXI_FindPath runs it on the caller's thread. The
// checks below are about the contract rather than the route: pending before
// ready, a different question never receiving the old answer, and -- the one
// that would be a memory bug rather than a wrong route -- nothing written
// through a caller buffer that has already gone away.
AXIPathResult make_path_result()
{
    AXIPathResult result{};
    result.struct_size = sizeof(result);
    return result;
}

// Collects an asynchronous query, asserting it reported pending at least once.
AXIPathResult await_async_path(
    void* context,
    const std::uint64_t generation,
    const AXIVec3 start,
    const AXIVec3 destination,
    const float radius,
    std::vector<AXIVec3>& points,
    bool& saw_pending)
{
    saw_pending = false;
    for (int attempt = 0; attempt < 6000; ++attempt)
    {
        AXIPathResult result = make_path_result();
        const std::int32_t code = AXI_FindPathAsync(
            context, generation, start, destination, radius,
            points.data(), static_cast<std::uint32_t>(points.size()), &result);
        CHECK(code == AXI_RESULT_OK);
        if (result.status == AXI_PATH_PENDING)
        {
            saw_pending = true;
            CHECK(result.point_count == 0u);
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
            continue;
        }
        CHECK(result.status == AXI_PATH_READY || result.status == AXI_PATH_UNREACHABLE);
        return result;
    }
    throw std::runtime_error("asynchronous path query never completed");
}

void run_async_path_tests(const wchar_t* ffxi_root)
{
    void* context = AXI_CreateContext();
    CHECK(context != nullptr);
    std::uint64_t generation = 0u;
    const fs::path cache_root = fs::temp_directory_path() / L"accessxi-collision-async-test";
    CHECK(AXI_BeginLoadZone(context, 190u, ffxi_root, cache_root.c_str(), &generation)
        == AXI_RESULT_OK);
    wait_for_ready(context, generation, 190u);

    const AXIVec3 start{-115.008f, -0.051f, 218.328f};
    const AXIVec3 destination{1.000f, -1.419f, -103.608f};
    std::vector<AXIVec3> points(512u);

    // A stale generation is refused before any worker is considered.
    {
        AXIPathResult result = make_path_result();
        CHECK(AXI_FindPathAsync(
            context, generation + 1000u, start, destination, 8.0f,
            points.data(), static_cast<std::uint32_t>(points.size()), &result)
            == AXI_RESULT_STALE_GENERATION);
    }

    // Invalid arguments are refused the same way the synchronous export does.
    {
        AXIPathResult result = make_path_result();
        CHECK(AXI_FindPathAsync(
            context, generation, start, destination, 8.0f, nullptr, 8u, &result)
            == AXI_RESULT_INVALID_ARGUMENT);
        CHECK(AXI_FindPathAsync(
            context, generation, start, destination, 8.0f, points.data(), 0u, &result)
            == AXI_RESULT_INVALID_ARGUMENT);
        CHECK(AXI_FindPathAsync(
            nullptr, generation, start, destination, 8.0f, points.data(), 8u, &result)
            == AXI_RESULT_INVALID_ARGUMENT);
    }

    // Pending, then ready, with the points only appearing at the end.
    bool saw_pending = false;
    const AXIPathResult ready = await_async_path(
        context, generation, start, destination, 8.0f, points, saw_pending);
    CHECK(saw_pending);
    CHECK(ready.status == AXI_PATH_READY);
    CHECK(ready.point_count >= 2u);
    CHECK(ready.total_length > 0.0f);

    // The same route asked synchronously must agree, and must never report
    // pending -- ABI 3 callers only understand the first two status values.
    {
        AXIPathResult synchronous = make_path_result();
        std::vector<AXIVec3> synchronous_points(512u);
        CHECK(AXI_FindPath(
            context, generation, start, destination, 8.0f,
            synchronous_points.data(),
            static_cast<std::uint32_t>(synchronous_points.size()), &synchronous)
            == AXI_RESULT_OK);
        CHECK(synchronous.status == AXI_PATH_READY);
        CHECK(synchronous.status != AXI_PATH_PENDING);
        CHECK(synchronous.point_count == ready.point_count);
    }

    // NOTHING IS WRITTEN THROUGH A BUFFER THE CALLER HAS FINISHED WITH.
    //
    // The first call hands over a buffer and gets pending back; the result is
    // then collected through a DIFFERENT buffer. The first must still hold its
    // sentinels, or the worker captured a pointer it had no right to keep.
    {
        const AXIVec3 sentinel{-12345.0f, -23456.0f, -34567.0f};
        std::vector<AXIVec3> abandoned(512u, sentinel);
        AXIPathResult first = make_path_result();
        CHECK(AXI_FindPathAsync(
            context, generation, start, AXIVec3{1.0f, -1.419f, -100.0f}, 8.0f,
            abandoned.data(), static_cast<std::uint32_t>(abandoned.size()), &first)
            == AXI_RESULT_OK);
        CHECK(first.status == AXI_PATH_PENDING);

        std::vector<AXIVec3> collected(512u);
        bool pending_again = false;
        const AXIPathResult second = await_async_path(
            context, generation, start, AXIVec3{1.0f, -1.419f, -100.0f}, 8.0f,
            collected, pending_again);
        CHECK(second.status == AXI_PATH_READY || second.status == AXI_PATH_UNREACHABLE);
        for (const AXIVec3& value : abandoned)
        {
            CHECK(value.x == sentinel.x && value.y == sentinel.y && value.z == sentinel.z);
        }
    }

    // A DIFFERENT QUESTION NEVER RECEIVES THE OLD ANSWER.
    //
    // Start one query, immediately ask for a different destination, and confirm
    // the second reports pending rather than handing back the first's result.
    {
        const AXIVec3 first_destination{1.000f, -1.419f, -103.608f};
        const AXIVec3 second_destination{-115.0f, -0.051f, 200.0f};
        AXIPathResult first = make_path_result();
        CHECK(AXI_FindPathAsync(
            context, generation, start, first_destination, 8.0f,
            points.data(), static_cast<std::uint32_t>(points.size()), &first)
            == AXI_RESULT_OK);
        CHECK(first.status == AXI_PATH_PENDING);

        AXIPathResult second = make_path_result();
        CHECK(AXI_FindPathAsync(
            context, generation, start, second_destination, 8.0f,
            points.data(), static_cast<std::uint32_t>(points.size()), &second)
            == AXI_RESULT_OK);
        CHECK(second.status == AXI_PATH_PENDING);
        CHECK(second.point_count == 0u);

        std::vector<AXIVec3> second_points(512u);
        bool pending_again = false;
        const AXIPathResult finished = await_async_path(
            context, generation, start, second_destination, 8.0f,
            second_points, pending_again);
        // Whatever it answers, it is an answer about the SECOND destination.
        if (finished.status == AXI_PATH_READY)
        {
            const AXIVec3& last = second_points[finished.point_count - 1u];
            const float dx = last.x - second_destination.x;
            const float dz = last.z - second_destination.z;
            CHECK(std::sqrt(dx * dx + dz * dz) <= 40.0f);
        }
    }

    // Cancellation leaves the context usable, and the next request starts over.
    {
        AXIPathResult result = make_path_result();
        CHECK(AXI_FindPathAsync(
            context, generation, start, destination, 8.0f,
            points.data(), static_cast<std::uint32_t>(points.size()), &result)
            == AXI_RESULT_OK);
        CHECK(result.status == AXI_PATH_PENDING);
        CHECK(AXI_CancelFindPath(context, generation) == AXI_RESULT_OK);
        CHECK(AXI_CancelFindPath(context, generation) == AXI_RESULT_OK);
        CHECK(AXI_CancelFindPath(context, generation + 1000u) == AXI_RESULT_STALE_GENERATION);

        AXIPathResult restarted = make_path_result();
        CHECK(AXI_FindPathAsync(
            context, generation, start, destination, 8.0f,
            points.data(), static_cast<std::uint32_t>(points.size()), &restarted)
            == AXI_RESULT_OK);
        CHECK(restarted.status == AXI_PATH_PENDING);
    }

    // A ZONE CHANGE WHILE A QUERY IS IN FLIGHT.
    //
    // The old generation must be refused rather than answered, and the worker
    // must have been stopped and joined rather than left holding the old zone.
    {
        std::uint64_t next_generation = 0u;
        CHECK(AXI_BeginLoadZone(context, 101u, ffxi_root, cache_root.c_str(), &next_generation)
            == AXI_RESULT_OK);
        CHECK(next_generation != generation);
        AXIPathResult stale = make_path_result();
        CHECK(AXI_FindPathAsync(
            context, generation, start, destination, 8.0f,
            points.data(), static_cast<std::uint32_t>(points.size()), &stale)
            == AXI_RESULT_STALE_GENERATION);
        CHECK(AXI_CancelFindPath(context, generation) == AXI_RESULT_STALE_GENERATION);
    }

    // Destroying a context with a query in flight must not hang or crash.
    AXI_DestroyContext(context);

    void* doomed = AXI_CreateContext();
    CHECK(doomed != nullptr);
    std::uint64_t doomed_generation = 0u;
    CHECK(AXI_BeginLoadZone(doomed, 190u, ffxi_root, cache_root.c_str(), &doomed_generation)
        == AXI_RESULT_OK);
    wait_for_ready(doomed, doomed_generation, 190u);
    AXIPathResult doomed_result = make_path_result();
    std::vector<AXIVec3> doomed_points(512u);
    CHECK(AXI_FindPathAsync(
        doomed, doomed_generation, start, destination, 8.0f,
        doomed_points.data(), static_cast<std::uint32_t>(doomed_points.size()), &doomed_result)
        == AXI_RESULT_OK);
    CHECK(doomed_result.status == AXI_PATH_PENDING);
    AXI_DestroyContext(doomed);
}


} // namespace

int wmain(const int argc, wchar_t** argv)
{
    try
    {
        CHECK(argc == 2);
        CHECK(AXI_GetAbiVersion() == 3u);

        // Canceling during DAT decode/build must not make the addon thread wait
        // for the full terrain build when the player zones or unloads.
        {
            void* canceled_context = AXI_CreateContext();
            CHECK(canceled_context != nullptr);
            std::uint64_t canceled_generation = 0u;
            const fs::path canceled_cache = fs::temp_directory_path()
                / L"accessxi-collision-cancel-test";
            CHECK(AXI_BeginLoadZone(
                canceled_context,
                190u,
                argv[1],
                canceled_cache.c_str(),
                &canceled_generation) == AXI_RESULT_OK);
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            const auto cancel_start = std::chrono::steady_clock::now();
            CHECK(AXI_CancelLoad(canceled_context, canceled_generation) == AXI_RESULT_OK);
            AXI_DestroyContext(canceled_context);
            const auto cancel_elapsed = std::chrono::steady_clock::now() - cancel_start;
            CHECK(cancel_elapsed < std::chrono::seconds(2));
        }

        run_async_path_tests(argv[1]);

        void* context = AXI_CreateContext();
        CHECK(context != nullptr);

        std::uint64_t generation = 0u;
        const fs::path cache_root = fs::temp_directory_path() / L"accessxi-collision-context-test";
        CHECK(AXI_BeginLoadZone(
            context,
            190u,
            argv[1],
            cache_root.c_str(),
            &generation) == AXI_RESULT_OK);
        CHECK(generation != 0u);
        wait_for_ready(context, generation, 190u);

        AXISweepResult sweep{};
        sweep.struct_size = sizeof(sweep);
        CHECK(AXI_SweepCapsule(
            context,
            generation,
            AXIVec3{-136.382f, -1.129f, 202.791f},
            AXIVec3{-143.982f, 6.071f, 151.191f},
            0.40f,
            1.80f,
            &sweep) == AXI_RESULT_OK);
        CHECK(sweep.clear == 0);

        std::vector<AXIVec3> points(512u);
        AXIPathResult path{};
        path.struct_size = sizeof(path);
        CHECK(AXI_FindPath(
            context,
            generation,
            AXIVec3{-115.008f, -0.051f, 218.328f},
            AXIVec3{1.000f, -1.419f, -103.608f},
            8.0f,
            points.data(),
            static_cast<std::uint32_t>(points.size()),
            &path) == AXI_RESULT_OK);
        CHECK(path.status == AXI_PATH_READY);
        CHECK(path.point_count > 2u);
        CHECK(path.point_count <= points.size());
        CHECK(path.total_length > 0.0f);

        // The user's return leg from the Tombstone/scales area to the King
        // Ranperre's Tomb Survival Guide must also be a real collision path,
        // not the former straight line through the interior wall.
        AXIPathResult guide_path{};
        guide_path.struct_size = sizeof(guide_path);
        CHECK(AXI_FindPath(
            context,
            generation,
            AXIVec3{1.000f, -1.419f, -103.608f},
            AXIVec3{-119.000f, 0.000f, 248.500f},
            8.0f,
            points.data(),
            static_cast<std::uint32_t>(points.size()),
            &guide_path) == AXI_RESULT_OK);
        if (guide_path.status != AXI_PATH_READY)
        {
            throw std::runtime_error(std::string("Guide path failed: ") + guide_path.reason);
        }
        CHECK(guide_path.status == AXI_PATH_READY);
        CHECK(guide_path.point_count > 2u);
        CHECK(guide_path.total_length > 350.0f);

        // East Ronfaure is the first outdoor terrain used immediately after
        // the Tomb mission leg.  It must build in the same Win32 context
        // without exhausting the game's address space or poisoning retries.
        std::uint64_t east_ronfaure_generation = 0u;
        CHECK(AXI_BeginLoadZone(
            context,
            101u,
            argv[1],
            cache_root.c_str(),
            &east_ronfaure_generation) == AXI_RESULT_OK);
        CHECK(east_ronfaure_generation != generation);
        wait_for_ready(context, east_ronfaure_generation, 101u);

        // Exact live 2026-08-11 return leg: the player was in East Ronfaure
        // heading for Ambrotien, so the first destination is the Southern San
        // d'Oria zone line.  The graph-paired reverse landing is the final
        // walkable approach before the raw transition trigger.
        AXIPathResult southern_sandoria_landing_path{};
        southern_sandoria_landing_path.struct_size = sizeof(southern_sandoria_landing_path);
        CHECK(AXI_FindPath(
            context,
            east_ronfaure_generation,
            AXIVec3{188.462f, 0.417f, -430.106f},
            AXIVec3{86.131f, 65.817f, 273.861f},
            8.0f,
            points.data(),
            static_cast<std::uint32_t>(points.size()),
            &southern_sandoria_landing_path) == AXI_RESULT_OK);
        if (southern_sandoria_landing_path.status != AXI_PATH_READY)
        {
            throw std::runtime_error(
                std::string("East Ronfaure zoneline approach failed: ")
                + southern_sandoria_landing_path.reason);
        }
        CHECK(southern_sandoria_landing_path.point_count > 2u);
        CHECK(southern_sandoria_landing_path.total_length > 500.0f);

        // Exact live 2026-08-11 West Ronfaure failure after the player moved
        // while collision terrain was still building.  The ordinary 8-yalm
        // query cannot cross the small generated-component seam at Ghelsba,
        // but the bounded 20-yalm zoneline landing must remain reachable and
        // its short tail to the real transition trigger must be collision-free.
        std::uint64_t west_ronfaure_generation = 0u;
        CHECK(AXI_BeginLoadZone(
            context,
            100u,
            argv[1],
            cache_root.c_str(),
            &west_ronfaure_generation) == AXI_RESULT_OK);
        CHECK(west_ronfaure_generation != east_ronfaure_generation);
        wait_for_ready(context, west_ronfaure_generation, 100u);

        AXIPathResult ghelsba_landing_path{};
        ghelsba_landing_path.struct_size = sizeof(ghelsba_landing_path);
        CHECK(AXI_FindPath(
            context,
            west_ronfaure_generation,
            AXIVec3{-450.579f, 66.155f, 456.175f},
            AXIVec3{-738.178f, 67.173f, 619.325f},
            20.0f,
            points.data(),
            static_cast<std::uint32_t>(points.size()),
            &ghelsba_landing_path) == AXI_RESULT_OK);
        if (ghelsba_landing_path.status != AXI_PATH_READY)
        {
            throw std::runtime_error(
                std::string("West Ronfaure widened zoneline approach failed: ")
                + ghelsba_landing_path.reason);
        }
        CHECK(ghelsba_landing_path.point_count > 2u);
        const AXIVec3 ghelsba_projected_end =
            points[ghelsba_landing_path.point_count - 1u];
        const AXIVec3 ghelsba_line{-740.570f, 68.478f, 623.341f};
        AXIVec3 current = ghelsba_projected_end;
        bool found_terminal_boundary = false;
        for (int attempt = 0; attempt < 64; ++attempt)
        {
            AXISweepResult contact{};
            contact.struct_size = sizeof(contact);
            CHECK(AXI_SweepCapsule(
                context,
                west_ronfaure_generation,
                current,
                ghelsba_line,
                0.40f,
                1.80f,
                &contact) == AXI_RESULT_OK);
            CHECK(contact.clear == 0);
            const float dx = ghelsba_line.x - current.x;
            const float dy = ghelsba_line.y - current.y;
            const float dz = ghelsba_line.z - current.z;
            const float remaining = std::sqrt(dx * dx + dy * dy + dz * dz);
            CHECK(contact.fraction >= 0.0f && contact.fraction <= 1.0f);
            if (contact.normal.y >= 0.50f)
            {
                const float next_fraction = contact.fraction + 0.10f / remaining;
                CHECK(next_fraction < 1.0f);
                current = AXIVec3{
                    current.x + dx * next_fraction,
                    current.y + dy * next_fraction,
                    current.z + dz * next_fraction,
                };
                continue;
            }
            const float horizontal_normal = std::sqrt(
                contact.normal.x * contact.normal.x
                + contact.normal.z * contact.normal.z);
            const float distance_after_contact = remaining * (1.0f - contact.fraction);
            found_terminal_boundary = std::fabs(contact.normal.y) <= 0.25f
                && horizontal_normal >= 0.95f
                && distance_after_contact <= 20.5f;
            break;
        }
        CHECK(found_terminal_boundary);

        AXI_DestroyContext(context);
        std::cout << "collision context tests passed\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
