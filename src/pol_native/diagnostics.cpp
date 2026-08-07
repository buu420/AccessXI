#include "pol_native/diagnostics.h"

#include <Windows.h>
#include <cstdio>
#include <filesystem>
#include <string>

namespace accessxi::pol_native
{
    namespace
    {
        std::string safe_record(std::string_view event)
        {
            std::string output;
            output.reserve(event.size());
            for (const unsigned char value : event)
            {
                if (value == '\r' || value == '\n' || value == '\t')
                {
                    output.push_back(' ');
                    continue;
                }
                if (value < 0x20u || value == 0x7Fu)
                    continue;
                output.push_back(static_cast<char>(value));
            }
            return output;
        }
    }

    Diagnostics::Diagnostics(std::filesystem::path log_directory)
    {
        if (log_directory.empty())
            log_directory = default_log_directory();
        startup_log_path_ = log_directory / L"pol-native-startup.log";
        speech_log_path_ = log_directory / L"pol-native-speech.log";
    }

    void Diagnostics::startup(std::string_view event) noexcept
    {
        append(startup_log_path_, event);
    }

    void Diagnostics::speech(std::string_view event) noexcept
    {
        append(speech_log_path_, event);
    }

    const std::filesystem::path& Diagnostics::startup_log_path() const noexcept
    {
        return startup_log_path_;
    }

    const std::filesystem::path& Diagnostics::speech_log_path() const noexcept
    {
        return speech_log_path_;
    }

    std::filesystem::path Diagnostics::default_log_directory()
    {
        wchar_t profile[32768]{};
        const DWORD copied = GetEnvironmentVariableW(
            L"USERPROFILE",
            profile,
            static_cast<DWORD>(sizeof(profile) / sizeof(profile[0])));
        if (copied == 0 || copied >= sizeof(profile) / sizeof(profile[0]))
            return std::filesystem::temp_directory_path() / L"AccessXI" / L"logs";
        return std::filesystem::path(profile) / L"AccessXI" / L"logs";
    }

    void Diagnostics::append(const std::filesystem::path& path, std::string_view event) noexcept
    {
        try
        {
            const std::string record = safe_record(event);
            std::lock_guard<std::mutex> guard(lock_);
            std::filesystem::create_directories(path.parent_path());

            FILE* file = nullptr;
            if (_wfopen_s(&file, path.c_str(), L"ab") != 0 || file == nullptr)
                return;

            SYSTEMTIME time{};
            GetLocalTime(&time);
            std::fprintf(
                file,
                "%04u-%02u-%02uT%02u:%02u:%02u.%03u %s\r\n",
                time.wYear,
                time.wMonth,
                time.wDay,
                time.wHour,
                time.wMinute,
                time.wSecond,
                time.wMilliseconds,
                record.c_str());
            std::fclose(file);
        }
        catch (...)
        {
        }
    }
}
