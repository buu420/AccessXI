#include "collision_native/rom_resolver.h"

#include "collision_native/file_snapshot.h"

#include <array>
#include <cstdint>
#include <filesystem>
#include <string>
#include <system_error>

namespace accessxi::collision {
namespace {

std::uint16_t read_u16(const std::vector<std::uint8_t>& bytes, const std::size_t offset)
{
    if (offset > bytes.size() || bytes.size() - offset < 2u)
    {
        throw CollisionError("FTABLE entry is truncated.");
    }
    return static_cast<std::uint16_t>(bytes[offset])
        | static_cast<std::uint16_t>(static_cast<std::uint16_t>(bytes[offset + 1u]) << 8u);
}

std::filesystem::path table_directory(const std::filesystem::path& root, const unsigned int index)
{
    return index == 1u ? root : root / (L"ROM" + std::to_wstring(index));
}

std::filesystem::path table_path(
    const std::filesystem::path& root,
    const unsigned int index,
    const wchar_t* stem)
{
    const std::wstring suffix = index == 1u ? L"" : std::to_wstring(index);
    return table_directory(root, index) / (std::wstring(stem) + suffix + L".DAT");
}

bool regular_file_exists(const std::filesystem::path& path)
{
    std::error_code error;
    const bool result = std::filesystem::is_regular_file(path, error);
    return !error && result;
}

} // namespace

std::uint32_t zone_model_file_id(const std::uint32_t zone_id)
{
    if (zone_id == 0u || zone_id > 4095u)
    {
        throw CollisionError("Zone ID is outside the supported FFXI range.");
    }
    return zone_id < 256u ? zone_id + 100u : zone_id + 83635u;
}

std::filesystem::path resolve_zone_model_dat(
    const std::filesystem::path& ffxi_root,
    const std::uint32_t zone_id)
{
    if (!ffxi_root.is_absolute())
    {
        throw CollisionError("FFXI root must be an absolute path.");
    }

    const std::uint32_t file_id = zone_model_file_id(zone_id);
    for (unsigned int table_index = 1u; table_index <= 9u; ++table_index)
    {
        const auto vtable_path = table_path(ffxi_root, table_index, L"VTABLE");
        const auto ftable_path = table_path(ffxi_root, table_index, L"FTABLE");
        const bool have_vtable = regular_file_exists(vtable_path);
        const bool have_ftable = regular_file_exists(ftable_path);
        if (!have_vtable && !have_ftable)
        {
            continue;
        }
        if (have_vtable != have_ftable)
        {
            throw CollisionError("FFXI VTABLE/FTABLE pair is incomplete.");
        }

        const FileSnapshot vtable = read_stable_snapshot(vtable_path);
        const FileSnapshot ftable = read_stable_snapshot(ftable_path);
        if (file_id >= vtable.bytes.size()
            || static_cast<std::uint64_t>(file_id) * 2u + 2u > ftable.bytes.size())
        {
            continue;
        }

        const std::uint8_t rom_index = vtable.bytes[file_id];
        if (rom_index == 0u)
        {
            continue;
        }
        if (rom_index > 9u)
        {
            throw CollisionError("VTABLE contains an unsupported ROM index.");
        }

        const std::uint16_t packed = read_u16(ftable.bytes, static_cast<std::size_t>(file_id) * 2u);
        const std::uint16_t directory = static_cast<std::uint16_t>(packed >> 7u);
        const std::uint16_t file = static_cast<std::uint16_t>(packed & 0x7fu);
        const std::filesystem::path rom_directory = rom_index == 1u
            ? ffxi_root / L"ROM"
            : ffxi_root / (L"ROM" + std::to_wstring(rom_index));
        const std::filesystem::path candidate =
            rom_directory / std::to_wstring(directory) / (std::to_wstring(file) + L".DAT");
        if (!regular_file_exists(candidate))
        {
            throw CollisionError("Resolved FFXI zone model DAT is missing.");
        }

        std::error_code error;
        const auto canonical = std::filesystem::weakly_canonical(candidate, error);
        if (error || canonical.empty())
        {
            throw CollisionError("Resolved FFXI zone model DAT path is invalid.");
        }
        return canonical;
    }

    throw CollisionError("No exact installed model DAT mapping exists for the zone.");
}

} // namespace accessxi::collision
