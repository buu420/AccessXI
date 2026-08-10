#include "collision_native/file_snapshot.h"

#include <algorithm>
#include <array>
#include <iomanip>
#include <limits>
#include <memory>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

#include <Windows.h>
#include <bcrypt.h>

namespace accessxi::collision {
namespace {

class UniqueHandle final
{
public:
    explicit UniqueHandle(HANDLE handle = INVALID_HANDLE_VALUE) noexcept
        : handle_(handle)
    {
    }

    ~UniqueHandle()
    {
        if (handle_ != INVALID_HANDLE_VALUE && handle_ != nullptr)
        {
            CloseHandle(handle_);
        }
    }

    UniqueHandle(const UniqueHandle&) = delete;
    UniqueHandle& operator=(const UniqueHandle&) = delete;

    HANDLE get() const noexcept
    {
        return handle_;
    }

private:
    HANDLE handle_;
};

class AlgorithmHandle final
{
public:
    ~AlgorithmHandle()
    {
        if (handle != nullptr)
        {
            BCryptCloseAlgorithmProvider(handle, 0);
        }
    }

    BCRYPT_ALG_HANDLE handle = nullptr;
};

class HashHandle final
{
public:
    ~HashHandle()
    {
        if (handle != nullptr)
        {
            BCryptDestroyHash(handle);
        }
    }

    BCRYPT_HASH_HANDLE handle = nullptr;
};

std::string windows_error(const char* operation)
{
    return std::string(operation) + " failed with Win32 error " + std::to_string(GetLastError()) + ".";
}

void reject_reparse_path(const std::filesystem::path& input)
{
    if (!input.is_absolute())
    {
        throw CollisionError("Collision source path must be absolute.");
    }

    const std::filesystem::path normalized = input.lexically_normal();
    std::filesystem::path current = normalized.root_path();
    for (const auto& component : normalized.relative_path())
    {
        if (component == L"." || component.empty())
        {
            continue;
        }
        if (component == L"..")
        {
            throw CollisionError("Collision source path contains a parent traversal.");
        }

        current /= component;
        const DWORD attributes = GetFileAttributesW(current.c_str());
        if (attributes == INVALID_FILE_ATTRIBUTES)
        {
            throw CollisionError(windows_error("GetFileAttributesW"));
        }
        if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
        {
            throw CollisionError("Collision source path contains a reparse component.");
        }
    }
}

BY_HANDLE_FILE_INFORMATION file_information(HANDLE handle)
{
    BY_HANDLE_FILE_INFORMATION information{};
    if (!GetFileInformationByHandle(handle, &information))
    {
        throw CollisionError(windows_error("GetFileInformationByHandle"));
    }
    return information;
}

bool same_file_information(
    const BY_HANDLE_FILE_INFORMATION& left,
    const BY_HANDLE_FILE_INFORMATION& right) noexcept
{
    return left.dwVolumeSerialNumber == right.dwVolumeSerialNumber
        && left.nFileIndexLow == right.nFileIndexLow
        && left.nFileIndexHigh == right.nFileIndexHigh
        && left.nFileSizeLow == right.nFileSizeLow
        && left.nFileSizeHigh == right.nFileSizeHigh
        && left.ftLastWriteTime.dwLowDateTime == right.ftLastWriteTime.dwLowDateTime
        && left.ftLastWriteTime.dwHighDateTime == right.ftLastWriteTime.dwHighDateTime;
}

std::string sha256_hex(const std::vector<std::uint8_t>& bytes)
{
    AlgorithmHandle algorithm;
    NTSTATUS status = BCryptOpenAlgorithmProvider(
        &algorithm.handle,
        BCRYPT_SHA256_ALGORITHM,
        nullptr,
        0);
    if (status < 0)
    {
        throw CollisionError("BCryptOpenAlgorithmProvider failed.");
    }

    DWORD object_size = 0;
    DWORD returned = 0;
    status = BCryptGetProperty(
        algorithm.handle,
        BCRYPT_OBJECT_LENGTH,
        reinterpret_cast<PUCHAR>(&object_size),
        sizeof(object_size),
        &returned,
        0);
    if (status < 0 || returned != sizeof(object_size) || object_size == 0)
    {
        throw CollisionError("BCrypt SHA-256 object length is unavailable.");
    }

    DWORD digest_size = 0;
    returned = 0;
    status = BCryptGetProperty(
        algorithm.handle,
        BCRYPT_HASH_LENGTH,
        reinterpret_cast<PUCHAR>(&digest_size),
        sizeof(digest_size),
        &returned,
        0);
    if (status < 0 || returned != sizeof(digest_size) || digest_size != 32u)
    {
        throw CollisionError("BCrypt SHA-256 digest length is invalid.");
    }

    std::vector<std::uint8_t> object(object_size);
    HashHandle hash;
    status = BCryptCreateHash(
        algorithm.handle,
        &hash.handle,
        object.data(),
        static_cast<ULONG>(object.size()),
        nullptr,
        0,
        0);
    if (status < 0)
    {
        throw CollisionError("BCryptCreateHash failed.");
    }

    std::size_t offset = 0;
    while (offset < bytes.size())
    {
        const std::size_t chunk_size = std::min<std::size_t>(
            bytes.size() - offset,
            std::numeric_limits<ULONG>::max());
        status = BCryptHashData(
            hash.handle,
            const_cast<PUCHAR>(bytes.data() + offset),
            static_cast<ULONG>(chunk_size),
            0);
        if (status < 0)
        {
            throw CollisionError("BCryptHashData failed.");
        }
        offset += chunk_size;
    }

    std::array<std::uint8_t, 32> digest{};
    status = BCryptFinishHash(hash.handle, digest.data(), static_cast<ULONG>(digest.size()), 0);
    if (status < 0)
    {
        throw CollisionError("BCryptFinishHash failed.");
    }

    std::ostringstream output;
    output << std::hex << std::setfill('0');
    for (const std::uint8_t value : digest)
    {
        output << std::setw(2) << static_cast<unsigned int>(value);
    }
    return output.str();
}

} // namespace

FileSnapshot read_stable_snapshot(const std::filesystem::path& path)
{
    reject_reparse_path(path);

    UniqueHandle handle(CreateFileW(
        path.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN | FILE_FLAG_OPEN_REPARSE_POINT,
        nullptr));
    if (handle.get() == INVALID_HANDLE_VALUE)
    {
        throw CollisionError(windows_error("CreateFileW"));
    }

    const BY_HANDLE_FILE_INFORMATION before = file_information(handle.get());
    if ((before.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0
        || (before.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
    {
        throw CollisionError("Collision source must be a regular non-reparse file.");
    }

    const std::uint64_t length =
        (static_cast<std::uint64_t>(before.nFileSizeHigh) << 32u)
        | static_cast<std::uint64_t>(before.nFileSizeLow);
    if (length > static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max())
        || length > static_cast<std::uint64_t>(std::numeric_limits<std::int32_t>::max()))
    {
        throw CollisionError("Collision source is too large for the x86 process.");
    }

    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(length));
    std::size_t offset = 0;
    while (offset < bytes.size())
    {
        const DWORD request = static_cast<DWORD>(std::min<std::size_t>(bytes.size() - offset, 1024u * 1024u));
        DWORD received = 0;
        if (!ReadFile(handle.get(), bytes.data() + offset, request, &received, nullptr))
        {
            throw CollisionError(windows_error("ReadFile"));
        }
        if (received == 0)
        {
            throw CollisionError("Collision source ended before its recorded size.");
        }
        offset += received;
    }

    std::uint8_t extra = 0;
    DWORD extra_received = 0;
    if (!ReadFile(handle.get(), &extra, 1, &extra_received, nullptr))
    {
        throw CollisionError(windows_error("ReadFile final length check"));
    }
    if (extra_received != 0)
    {
        throw CollisionError("Collision source grew while it was being read.");
    }

    const BY_HANDLE_FILE_INFORMATION after = file_information(handle.get());
    if (!same_file_information(before, after))
    {
        throw CollisionError("Collision source identity changed while it was being read.");
    }

    std::error_code error;
    const std::filesystem::path canonical = std::filesystem::weakly_canonical(path, error);
    if (error || canonical.empty())
    {
        throw CollisionError("Collision source canonical path is unavailable.");
    }

    FileSnapshot snapshot;
    snapshot.canonical_path = canonical;
    snapshot.identity = FileIdentity{
        before.nFileSizeLow,
        before.nFileSizeHigh,
        before.ftLastWriteTime.dwLowDateTime,
        before.ftLastWriteTime.dwHighDateTime,
    };
    snapshot.sha256_hex = sha256_hex(bytes);
    snapshot.bytes = std::move(bytes);
    return snapshot;
}

} // namespace accessxi::collision
