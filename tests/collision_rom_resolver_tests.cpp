#include "collision_native/file_snapshot.h"
#include "collision_native/rom_resolver.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include <Windows.h>

namespace fs = std::filesystem;
using accessxi::collision::CollisionError;
using accessxi::collision::read_stable_snapshot;
using accessxi::collision::resolve_zone_model_dat;
using accessxi::collision::zone_model_file_id;

namespace {

int failures = 0;

void check(const bool condition, const char* expression, const int line)
{
    if (condition)
    {
        return;
    }
    std::cerr << "FAIL line " << line << ": " << expression << '\n';
    ++failures;
}

template<typename Callable>
void check_throws(Callable&& callable, const char* expression, const int line)
{
    try
    {
        callable();
    }
    catch (const CollisionError&)
    {
        return;
    }
    catch (const std::exception& error)
    {
        std::cerr << "FAIL line " << line << ": " << expression
                  << " threw wrong exception: " << error.what() << '\n';
        ++failures;
        return;
    }

    std::cerr << "FAIL line " << line << ": " << expression << " did not throw\n";
    ++failures;
}

#define CHECK(expression) check(static_cast<bool>(expression), #expression, __LINE__)
#define CHECK_THROWS(expression) check_throws([&]() { static_cast<void>(expression); }, #expression, __LINE__)

class TemporaryDirectory final
{
public:
    TemporaryDirectory()
    {
        const auto nonce = std::chrono::steady_clock::now().time_since_epoch().count();
        path_ = fs::temp_directory_path() /
            (L"accessxi-collision-resolver-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(nonce));
        fs::create_directories(path_);
    }

    ~TemporaryDirectory()
    {
        std::error_code ignored;
        fs::remove_all(path_, ignored);
    }

    const fs::path& path() const noexcept
    {
        return path_;
    }

private:
    fs::path path_;
};

void write_bytes(const fs::path& path, const std::vector<std::uint8_t>& bytes)
{
    fs::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream)
    {
        throw std::runtime_error("Could not create test file.");
    }
    stream.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    if (!stream)
    {
        throw std::runtime_error("Could not write test file.");
    }
}

void stage_table(
    const fs::path& root,
    const std::wstring& table_directory,
    const std::wstring& suffix,
    const std::uint32_t file_id,
    const std::uint8_t rom_index,
    const std::uint16_t packed)
{
    std::vector<std::uint8_t> vtable(file_id + 1u, 0u);
    vtable[file_id] = rom_index;
    std::vector<std::uint8_t> ftable((file_id + 1u) * 2u, 0u);
    ftable[file_id * 2u] = static_cast<std::uint8_t>(packed & 0xffu);
    ftable[file_id * 2u + 1u] = static_cast<std::uint8_t>(packed >> 8u);

    const fs::path directory = table_directory.empty() ? root : root / table_directory;
    write_bytes(directory / (L"VTABLE" + suffix + L".DAT"), vtable);
    write_bytes(directory / (L"FTABLE" + suffix + L".DAT"), ftable);
}

void run_synthetic_resolver_tests()
{
    TemporaryDirectory temporary;
    const fs::path root = temporary.path();
    const std::uint32_t file_id = zone_model_file_id(190u);
    CHECK(file_id == 290u);
    CHECK(zone_model_file_id(256u) == 83891u);

    stage_table(root, L"", L"", file_id, 1u, static_cast<std::uint16_t>((3u << 7u) | 4u));
    write_bytes(root / L"ROM" / L"3" / L"4.DAT", { 1u, 2u, 3u });
    CHECK(resolve_zone_model_dat(root, 190u) == fs::weakly_canonical(root / L"ROM" / L"3" / L"4.DAT"));

    stage_table(root, L"ROM2", L"2", file_id, 2u, static_cast<std::uint16_t>((5u << 7u) | 6u));
    write_bytes(root / L"ROM2" / L"5" / L"6.DAT", { 4u, 5u, 6u });

    // The base table remains authoritative when it contains the file ID.
    CHECK(resolve_zone_model_dat(root, 190u) == fs::weakly_canonical(root / L"ROM" / L"3" / L"4.DAT"));

    std::vector<std::uint8_t> base_vtable(file_id + 1u, 0u);
    std::vector<std::uint8_t> base_ftable((file_id + 1u) * 2u, 0u);
    write_bytes(root / L"VTABLE.DAT", base_vtable);
    write_bytes(root / L"FTABLE.DAT", base_ftable);
    CHECK(resolve_zone_model_dat(root, 190u) == fs::weakly_canonical(root / L"ROM2" / L"5" / L"6.DAT"));

    CHECK_THROWS(resolve_zone_model_dat(root, 0u));
    CHECK_THROWS(resolve_zone_model_dat(root, 5000u));

    fs::remove(root / L"ROM2" / L"5" / L"6.DAT");
    CHECK_THROWS(resolve_zone_model_dat(root, 190u));
}

void run_snapshot_tests()
{
    TemporaryDirectory temporary;
    const fs::path path = temporary.path() / L"abc.dat";
    write_bytes(path, { static_cast<std::uint8_t>('a'), static_cast<std::uint8_t>('b'), static_cast<std::uint8_t>('c') });

    const auto snapshot = read_stable_snapshot(path);
    CHECK(snapshot.bytes.size() == 3u);
    CHECK(snapshot.sha256_hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    CHECK(snapshot.identity.size_low == 3u);
    CHECK(snapshot.identity.size_high == 0u);
    CHECK(snapshot.canonical_path == fs::weakly_canonical(path));

    CHECK_THROWS(read_stable_snapshot(temporary.path() / L"missing.dat"));
    CHECK_THROWS(read_stable_snapshot(temporary.path()));
}

void run_installed_zone_test(const fs::path& ffxi_root)
{
    const fs::path expected = fs::weakly_canonical(ffxi_root / L"ROM" / L"1" / L"14.DAT");
    const fs::path actual = resolve_zone_model_dat(ffxi_root, 190u);
    CHECK(actual == expected);

    const auto snapshot = read_stable_snapshot(actual);
    CHECK(snapshot.bytes.size() == 9536304u);
    CHECK(snapshot.sha256_hex.size() == 64u);
    CHECK(snapshot.identity.size_low == 9536304u);
    CHECK(snapshot.identity.size_high == 0u);
}

} // namespace

int main(const int argc, const char* const* argv)
{
    if (argc != 2)
    {
        std::cerr << "usage: collision_rom_resolver_tests <ffxi-root>\n";
        return 2;
    }

    run_synthetic_resolver_tests();
    run_snapshot_tests();
    run_installed_zone_test(fs::path(argv[1]));

    if (failures != 0)
    {
        std::cerr << failures << " collision resolver assertion(s) failed.\n";
        return 1;
    }

    std::cout << "collision ROM resolver tests passed\n";
    return 0;
}
