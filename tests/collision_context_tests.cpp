#include "collision_native/collision_api.h"

#include <chrono>
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

void wait_for_ready(void* context, const std::uint64_t generation)
{
    for (int attempt = 0; attempt < 2400; ++attempt)
    {
        AXILoadStatus status{};
        status.struct_size = sizeof(status);
        CHECK(AXI_PollLoadZone(context, generation, &status) == AXI_RESULT_OK);
        CHECK(status.generation == generation);
        if (status.state == AXI_LOAD_READY)
        {
            CHECK(status.zone_id == 190u);
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
    throw std::runtime_error("Collision worker did not become ready within 60 seconds.");
}

} // namespace

int wmain(const int argc, wchar_t** argv)
{
    try
    {
        CHECK(argc == 2);
        CHECK(AXI_GetAbiVersion() == 2u);

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
        wait_for_ready(context, generation);

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
        CHECK(guide_path.status == AXI_PATH_READY);
        CHECK(guide_path.point_count > 2u);
        CHECK(guide_path.total_length > 350.0f);

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
