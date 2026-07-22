#pragma once

#include <filesystem>
#include <mutex>
#include <string_view>

namespace accessxi::pol_native
{
    class Diagnostics
    {
    public:
        explicit Diagnostics(std::filesystem::path log_directory = {});

        Diagnostics(const Diagnostics&) = delete;
        Diagnostics& operator=(const Diagnostics&) = delete;

        void startup(std::string_view event) noexcept;
        void speech(std::string_view event) noexcept;

        const std::filesystem::path& startup_log_path() const noexcept;
        const std::filesystem::path& speech_log_path() const noexcept;

        static std::filesystem::path default_log_directory();

    private:
        void append(const std::filesystem::path& path, std::string_view event) noexcept;

        std::filesystem::path startup_log_path_;
        std::filesystem::path speech_log_path_;
        std::mutex lock_;
    };
}
