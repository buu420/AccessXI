#include <Ashita.h>

#include <Windows.h>
#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace
{
    constexpr const wchar_t* DefaultLogFileName = L"pol-monitor.log";
    constexpr const wchar_t* DefaultReloadedSpeechQueueFileName = L"pol-reloaded-native-speech.queue";

    constexpr uintptr_t AppRuntimeBase = 0x04810000u;
    constexpr uintptr_t PmlSharedFocusEventRva = 0x0005BBF5u;
    constexpr uintptr_t PmlSelectFocusEventRva = 0x00081D59u;
    constexpr uintptr_t NativeSelectionRegisterRva = 0x00009E62u;
    constexpr uintptr_t SelectedIndexSetterRva = 0x001DD903u;
    constexpr uintptr_t PmlIndexedChildAtRva = 0x00102B3Bu;
    constexpr uintptr_t PmlCurrentChildSetterRva = 0x000044F1u;
    constexpr uintptr_t PmlTextSetterRva = 0x00064156u;
    constexpr uintptr_t PmlGlobalFocusManagerRva = 0x004E13C8u;
    constexpr uintptr_t PreloginMemberNameAccessorRva = 0x0001CFB1u;
    constexpr uintptr_t PreloginMemberNameWideGlobalRva = 0x0048E592u;
    constexpr unsigned long long KnownUpdatedAppDllSize = 4335104ull;
    constexpr unsigned long long KnownUpdatedAppDllFnv64 = 0x07E88E8067FEF6CCull;
    constexpr DWORD AddMemberContextCacheTtlMs = 60000;

    using AccessXiPolSpeechSinkV1 = void (__stdcall *)(
        const char* utf8_text,
        int interrupt,
        void* context);

    constexpr int AccessXiPolInitializeOk = 1;
    constexpr int AccessXiPolInitializeAlreadyReady = 2;
    constexpr int AccessXiPolInitializeAppDllMissing = -1;
    constexpr int AccessXiPolInitializeUnsupportedBuild = -2;
    constexpr int AccessXiPolInitializeBusy = -3;

    std::atomic<bool> g_reloaded_speech_queue_enabled{ false };
    std::atomic<bool> g_reloaded_native_worker_running{ false };
    std::atomic<bool> g_pml_focus_event_hook_installed{ false };
    std::atomic<bool> g_native_focus_dispatch_hooks_installed{ false };
    std::atomic<bool> g_native_selection_truth_hooks_installed{ false };
    std::atomic<bool> g_appdll_fingerprint_ok_logged{ false };
    std::atomic<bool> g_appdll_fingerprint_mismatch_logged{ false };
    std::atomic<AccessXiPolSpeechSinkV1> g_speech_sink_v1{ nullptr };
    std::atomic<void*> g_speech_sink_context_v1{ nullptr };
    std::atomic<int> g_native_initialize_state{ 0 };

    std::mutex g_log_lock;
    std::mutex g_candidate_lock;
    std::mutex g_current_child_lock;
    std::mutex g_speech_lock;
    std::mutex g_add_member_context_cache_lock;
    void* g_pml_shared_focus_event_trampoline = nullptr;
    void* g_pml_select_focus_event_trampoline = nullptr;
    void* g_selected_index_setter_trampoline = nullptr;
    void* g_pml_current_child_setter_trampoline = nullptr;

    struct PreloginPmlFocusCandidate
    {
        std::string source;
        std::string label;
        void* manager = nullptr;
        void* focused_object = nullptr;
        bool current_child = false;
        bool focused_flag = false;
        bool snapshot_current_child = false;
        DWORD tick = 0;
    };

    struct PreloginCurrentChildSnapshot
    {
        void* manager = nullptr;
        void* requested_child = nullptr;
        uintptr_t current_child = 0;
        DWORD tick = 0;
    };

    struct PreloginRect
    {
        int left = 0;
        int top = 0;
        int right = 0;
        int bottom = 0;
    };

    struct PreloginAtlasGeometry
    {
        int left;
        int top;
        int right;
        int bottom;
        const char* label;
        uint32_t resource;
    };

    struct PreloginNativeTextCandidate
    {
        std::string value;
        uint32_t offset = 0;
        int source_rank = 0;
    };

    struct AddMemberContextCacheEntry
    {
        uintptr_t object = 0;
        PreloginRect rect{};
        bool have_rect = false;
        bool result = false;
        DWORD tick = 0;
    };

    bool g_pending_pml_focus_candidate_valid = false;
    PreloginPmlFocusCandidate g_pending_pml_focus_candidate;
    bool g_pending_current_child_snapshot_valid = false;
    PreloginCurrentChildSnapshot g_pending_current_child_snapshot;
    std::string g_last_spoken_prelogin_label;
    void* g_last_spoken_prelogin_object = nullptr;
    DWORD g_last_spoken_prelogin_tick = 0;
    uintptr_t g_last_processed_prelogin_current_child = 0;
    DWORD g_last_processed_prelogin_current_child_tick = 0;
    uintptr_t g_last_sampled_prelogin_focus_manager = 0;
    uintptr_t g_last_sampled_prelogin_focus_child = 0;
    AddMemberContextCacheEntry g_add_member_context_cache[32]{};
    uint32_t g_add_member_context_cache_cursor = 0;
    std::atomic<int> g_current_child_detail_budget{ 6 };
    std::atomic<int> g_current_child_no_label_budget{ 2 };
    std::atomic<int> g_current_child_rejected_log_budget{ 6 };
    std::atomic<int> g_current_child_candidate_log_budget{ 10 };
    std::atomic<int> g_pml_coalesced_log_budget{ 10 };
    std::atomic<int> g_atlas_geometry_conflict_log_budget{ 10 };
    std::atomic<int> g_selected_index_no_label_log_budget{ 24 };
    std::atomic<int> g_startup_member_probe_budget{ 6 };
    std::atomic<int> g_startup_member_model_probe_budget{ 12 };

    std::wstring read_environment_wide(const wchar_t* name)
    {
        if (name == nullptr || name[0] == 0)
            return {};

        const DWORD needed = GetEnvironmentVariableW(name, nullptr, 0);
        if (needed == 0)
            return {};

        std::wstring value(static_cast<size_t>(needed), L'\0');
        const DWORD copied = GetEnvironmentVariableW(name, value.data(), needed);
        if (copied == 0)
            return {};

        value.resize(static_cast<size_t>(copied));
        return value;
    }

    void trim_trailing_slashes(std::wstring& path)
    {
        while (!path.empty() && (path.back() == L'\\' || path.back() == L'/'))
            path.pop_back();
    }

    std::wstring path_join(std::wstring left, const wchar_t* right)
    {
        trim_trailing_slashes(left);
        if (left.empty())
            return right == nullptr ? std::wstring{} : std::wstring(right);
        if (right == nullptr || right[0] == 0)
            return left;
        return left + L"\\" + right;
    }

    std::wstring parent_directory(const std::wstring& path)
    {
        const size_t pos = path.find_last_of(L"\\/");
        if (pos == std::wstring::npos)
            return {};
        return path.substr(0, pos);
    }

    std::wstring diagnostic_log_directory()
    {
        std::wstring configured = read_environment_wide(L"ACCESSXI_POL_LOG_DIR");
        if (!configured.empty())
            return configured;

        std::wstring user_profile = read_environment_wide(L"USERPROFILE");
        if (!user_profile.empty())
            return path_join(path_join(user_profile, L"AccessXI"), L"logs");

        std::wstring temp = read_environment_wide(L"TEMP");
        if (!temp.empty())
            return path_join(path_join(temp, L"AccessXI"), L"logs");

        return L".";
    }

    std::wstring diagnostic_log_path()
    {
        return path_join(diagnostic_log_directory(), DefaultLogFileName);
    }

    std::wstring reloaded_speech_queue_path()
    {
        std::wstring configured = read_environment_wide(L"ACCESSXI_POL_SPEECH_QUEUE");
        if (!configured.empty())
            return configured;

        return path_join(diagnostic_log_directory(), DefaultReloadedSpeechQueueFileName);
    }

    void log_line(const char* text)
    {
        if (text == nullptr)
            return;

        std::lock_guard<std::mutex> guard(g_log_lock);
        const std::wstring log_directory = diagnostic_log_directory();
        CreateDirectoryW(log_directory.c_str(), nullptr);

        SYSTEMTIME now{};
        GetLocalTime(&now);

        const std::wstring log_path = diagnostic_log_path();
        FILE* file = nullptr;
        if (_wfopen_s(&file, log_path.c_str(), L"ab") != 0 || file == nullptr)
            return;

        std::fprintf(
            file,
            "%04u-%02u-%02u %02u:%02u:%02u.%03u %s\r\n",
            now.wYear,
            now.wMonth,
            now.wDay,
            now.wHour,
            now.wMinute,
            now.wSecond,
            now.wMilliseconds,
            text);
        std::fclose(file);
    }

    std::string narrow_from_wide(const wchar_t* value)
    {
        if (value == nullptr || value[0] == 0)
            return {};

        const int needed = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
        if (needed <= 1)
            return {};

        std::string output(static_cast<size_t>(needed - 1), '\0');
        WideCharToMultiByte(CP_UTF8, 0, value, -1, output.data(), needed, nullptr, nullptr);
        return output;
    }

    bool file_fnv64(const wchar_t* path, unsigned long long* size, unsigned long long* fingerprint)
    {
        if (path == nullptr || path[0] == 0 || size == nullptr || fingerprint == nullptr)
            return false;

        HANDLE file = CreateFileW(
            path,
            GENERIC_READ,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            OPEN_EXISTING,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
            return false;

        LARGE_INTEGER file_size{};
        if (!GetFileSizeEx(file, &file_size) || file_size.QuadPart < 0)
        {
            CloseHandle(file);
            return false;
        }

        unsigned long long hash = 14695981039346656037ull;
        uint8_t buffer[32768]{};
        DWORD read = 0;
        BOOL read_ok = FALSE;
        while ((read_ok = ReadFile(file, buffer, static_cast<DWORD>(sizeof(buffer)), &read, nullptr)) && read > 0)
        {
            for (DWORD i = 0; i < read; ++i)
            {
                hash ^= static_cast<unsigned long long>(buffer[i]);
                hash *= 1099511628211ull;
            }
        }

        CloseHandle(file);
        if (!read_ok)
            return false;

        *size = static_cast<unsigned long long>(file_size.QuadPart);
        *fingerprint = hash;
        return true;
    }

    bool app_module_matches_known_updated_pol_build(HMODULE app, const char* reason)
    {
        if (app == nullptr)
            return false;

        wchar_t path[MAX_PATH]{};
        const DWORD copied = GetModuleFileNameW(app, path, MAX_PATH);
        if (copied == 0 || copied >= MAX_PATH)
        {
            if (!g_appdll_fingerprint_mismatch_logged.exchange(true))
                log_line("PRELOGIN_APPDLL fingerprint-unavailable reason=module-path");
            return false;
        }

        unsigned long long size = 0;
        unsigned long long fingerprint = 0;
        if (!file_fnv64(path, &size, &fingerprint))
        {
            if (!g_appdll_fingerprint_mismatch_logged.exchange(true))
            {
                std::string line = std::string("PRELOGIN_APPDLL fingerprint-unavailable reason=file-read hook=") +
                    (reason == nullptr ? "" : reason) +
                    " path=\"" +
                    narrow_from_wide(path) +
                    "\"";
                log_line(line.c_str());
            }
            return false;
        }

        const bool matches = size == KnownUpdatedAppDllSize && fingerprint == KnownUpdatedAppDllFnv64;
        if (matches)
        {
            if (!g_appdll_fingerprint_ok_logged.exchange(true))
            {
                char line[256]{};
                std::snprintf(
                    line,
                    sizeof(line) - 1,
                    "PRELOGIN_APPDLL fingerprint-ok hook=%s size=%llu fnv64=%016llX",
                    reason == nullptr ? "" : reason,
                    size,
                    fingerprint);
                log_line(line);
            }
            return true;
        }

        if (!g_appdll_fingerprint_mismatch_logged.exchange(true))
        {
            std::string line = std::string("PRELOGIN_APPDLL fingerprint-mismatch hook=") +
                (reason == nullptr ? "" : reason) +
                " size=" +
                std::to_string(size) +
                " fnv64=";
            char hash_text[17]{};
            std::snprintf(hash_text, sizeof(hash_text), "%016llX", fingerprint);
            line += hash_text;
            line += " expectedSize=" + std::to_string(KnownUpdatedAppDllSize);
            line += " expectedFnv64=07E88E8067FEF6CC path=\"";
            line += narrow_from_wide(path);
            line += "\" action=skip-native-hooks update=finish-playonline-update";
            log_line(line.c_str());
        }
        return false;
    }

    std::string lower_copy(std::string value)
    {
        std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
            return static_cast<char>(std::tolower(ch));
        });
        return value;
    }

    std::string trim_ascii(std::string value)
    {
        while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front())))
            value.erase(value.begin());
        while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back())))
            value.pop_back();
        return value;
    }

    std::string clean_text(const char* text, int count)
    {
        if (text == nullptr)
            return {};

        const size_t length = count < 0 ? std::strlen(text) : static_cast<size_t>(count);
        std::string value(text, text + length);
        for (char& ch : value)
        {
            const auto byte = static_cast<unsigned char>(ch);
            if ((byte < 0x20 || byte > 0x7e) && ch != '\t')
                ch = ' ';
        }
        return trim_ascii(value);
    }

    std::string clean_wide_text(const wchar_t* text, int count)
    {
        if (text == nullptr)
            return {};

        const size_t length = count < 0 ? std::wcslen(text) : static_cast<size_t>(count);
        std::wstring wide(text, text + length);
        for (wchar_t& ch : wide)
        {
            if ((ch < 0x20 || ch > 0x7e) && ch != L'\t')
                ch = L' ';
        }
        return trim_ascii(narrow_from_wide(wide.c_str()));
    }

    bool copy_memory_safely(void* destination, const void* source, size_t size)
    {
        if (destination == nullptr || source == nullptr || size == 0)
            return false;

        __try
        {
            std::memcpy(destination, source, size);
            return true;
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            return false;
        }
    }

    bool read_ptr_safely(const void* address, uintptr_t* value)
    {
        if (value == nullptr)
            return false;
        return copy_memory_safely(value, address, sizeof(*value));
    }

    bool read_u32_safely(const void* address, uint32_t* value)
    {
        if (value == nullptr)
            return false;
        return copy_memory_safely(value, address, sizeof(*value));
    }

    std::string read_wide_text_safely(const wchar_t* value, size_t max_chars)
    {
        if (value == nullptr || max_chars == 0)
            return {};

        wchar_t buffer[64]{};
        const size_t capped = std::min(max_chars, (sizeof(buffer) / sizeof(buffer[0])) - 1);
        bool terminated = false;
        for (size_t index = 0; index < capped; ++index)
        {
            wchar_t ch = 0;
            if (!copy_memory_safely(&ch, value + index, sizeof(ch)))
                return {};

            if (ch == 0)
            {
                terminated = true;
                break;
            }

            buffer[index] = ch;
        }

        if (!terminated || buffer[0] == 0)
            return {};

        return clean_wide_text(buffer, -1);
    }

    bool useful_text(const std::string& value)
    {
        if (value.size() < 2 || value.size() > 120)
            return false;

        int letters = 0;
        for (const char ch : value)
        {
            if (std::isalpha(static_cast<unsigned char>(ch)))
                ++letters;
        }
        return letters >= 2;
    }

    bool native_prelogin_atlas_label(const std::string& value)
    {
        static const char* const labels[] = {
            "Network",
            "Next",
            "Cancel",
            "Language",
            "Keyboard",
            "Yes",
            "No",
            "Start PlayOnline Registration!",
            "For PlayOnline Members!",
            "Member List",
            "Log In",
            "Settings",
            "Delete",
            "Back",
            "Information",
            "Guest Login",
            "Add Member",
            "Check Files",
            "Join PlayOnline",
            "Network Settings",
            "Security Settings",
            "Language Settings",
            "Quick Manuals",
            "Exit Viewer",
            "Auxiliary Network Settings",
            "Connection check",
            "Proxy server",
            "Proxy server address",
            "Port",
            "Security proxy",
            "OK",
            "Enter Member Password",
            "Login Information",
            "Member Information",
            "Member Name",
            "PlayOnline ID",
            "Set Password",
            "PlayOnline Password",
            "Member Password",
            "Confirm Password",
            "Square Enix ID",
            "Square Enix Password",
            "One-Time Password",
            "Connect to PlayOnline",
            "Automatically log in at startup",
            "Connect",
            "Register"
        };

        for (const char* label : labels)
        {
            if (value == label)
                return true;
        }
        return false;
    }

    bool prelogin_setup_form_value_cell_label(const char* source_text, const std::string& label)
    {
        UNREFERENCED_PARAMETER(source_text);
        return label == "Use" ||
            label == "Do not use" ||
            label == "Do Not Use" ||
            label == "Disable" ||
            label == "Enable" ||
            label == "Version Update" ||
            label == "Not set" ||
            label == "Port";
    }

    bool prelogin_add_member_value_label(const std::string& label)
    {
        return label == "PlayOnline Password" ||
            label == "Confirm Password" ||
            label == "Save" ||
            label == "Not set" ||
            label == "Use" ||
            label == "Do Not Use";
    }

    bool prelogin_add_member_button_label(const std::string& label)
    {
        return label == "Register" ||
            label == "Cancel";
    }

    bool prelogin_member_dynamic_label(const std::string& label)
    {
        if (!useful_text(label))
            return false;
        if (native_prelogin_atlas_label(label))
            return false;
        if (label.size() > 32)
            return false;
        if (label.front() == ' ' || label.back() == ' ')
            return false;
        if (label.find("  ") != std::string::npos)
            return false;

        int alnum_count = 0;
        int space_count = 0;
        int token_alnum_count = 0;
        int shortest_space_token_alnum_count = 64;
        int current_alnum_run = 0;
        int longest_alnum_run = 0;
        for (const char ch : label)
        {
            const auto byte = static_cast<unsigned char>(ch);
            if (std::isalnum(byte))
            {
                ++alnum_count;
                ++token_alnum_count;
                ++current_alnum_run;
                longest_alnum_run = std::max(longest_alnum_run, current_alnum_run);
                continue;
            }

            current_alnum_run = 0;
            if (ch == ' ')
            {
                ++space_count;
                shortest_space_token_alnum_count = std::min(shortest_space_token_alnum_count, token_alnum_count);
                token_alnum_count = 0;
                continue;
            }
            if (ch != ' ' && ch != '-' && ch != '_')
                return false;
        }
        shortest_space_token_alnum_count = std::min(shortest_space_token_alnum_count, token_alnum_count);

        if (alnum_count < 4)
            return false;
        if (space_count > 1)
            return false;
        if (space_count > 0 && shortest_space_token_alnum_count < 2)
            return false;
        if (space_count * 3 > alnum_count)
            return false;
        if (longest_alnum_run < 2)
            return false;

        const std::string lower = lower_copy(label);
        if (lower == "play" || lower == "pla" || lower == "pol" || lower == "online" || lower == "ccomponent" ||
            lower == "playonline viewer")
            return false;
        if (lower == "***" || lower == "null")
            return false;
        if (lower.find("get_") == 0 ||
            lower.find("system.") != std::string::npos ||
            lower.find("firstw") != std::string::npos)
            return false;
        if (lower.find("http") != std::string::npos ||
            lower.find(".pml") != std::string::npos ||
            lower.find(".esd") != std::string::npos ||
            lower.find(".tm2") != std::string::npos ||
            lower.find("regularmember") != std::string::npos ||
            lower.find("regularmenber") != std::string::npos ||
            lower.find("window") != std::string::npos ||
            lower.find("wnd") != std::string::npos ||
            lower.find("xbox_") != std::string::npos ||
            lower.find("sys_") != std::string::npos ||
            lower.find("::") != std::string::npos ||
            lower.find("\\") != std::string::npos ||
            lower.find("/") != std::string::npos)
        {
            return false;
        }

        return true;
    }

    bool native_post_login_surface_active();

    using MemberNameAccessor_t = const wchar_t* (__cdecl*)(void);

    const wchar_t* call_native_prelogin_member_name_accessor(MemberNameAccessor_t accessor)
    {
        const wchar_t* wide_name = nullptr;
        __try
        {
            wide_name = accessor == nullptr ? nullptr : accessor();
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            return nullptr;
        }
        return wide_name;
    }

    std::string read_native_prelogin_member_name(void)
    {
        HMODULE app = GetModuleHandleA("app.dll");
        if (app == nullptr)
            return {};

        auto* app_base = reinterpret_cast<uint8_t*>(app);
        const auto accessor = reinterpret_cast<MemberNameAccessor_t>(app_base + PreloginMemberNameAccessorRva);
        const wchar_t* wide_name = call_native_prelogin_member_name_accessor(accessor);

        std::string label = read_wide_text_safely(wide_name, 32);
        if (prelogin_member_dynamic_label(label))
            return label;

        label = read_wide_text_safely(reinterpret_cast<const wchar_t*>(app_base + PreloginMemberNameWideGlobalRva), 32);
        if (!prelogin_member_dynamic_label(label))
            return {};
        return label;
    }

    bool prelogin_add_member_field_geometry_label(const std::string& label)
    {
        return label == "Member Name" ||
            label == "PlayOnline ID" ||
            label == "Set Password" ||
            label == "Member Password" ||
            label == "Confirm Password" ||
            label == "Square Enix ID" ||
            label == "What is a Square Enix ID" ||
            label == "One-Time Password";
    }

    bool prelogin_pml_focus_candidate_label_allowed(const char* source_text, const std::string& label)
    {
        if (!useful_text(label))
            return false;

        const std::string lower = lower_copy(label);
        if (lower == "play" || lower == "pla" || lower == "pol" || lower == "online")
            return false;
        if (lower.find("http") != std::string::npos || lower.find(".pml") != std::string::npos || lower.find(".esd") != std::string::npos)
            return false;

        if (source_text != nullptr && std::strcmp(source_text, "direct-fields") == 0)
            return prelogin_setup_form_value_cell_label(source_text, label);

        if (source_text != nullptr && std::strcmp(source_text, "add-member") == 0)
            return native_prelogin_atlas_label(label) || prelogin_add_member_value_label(label);

        if (source_text != nullptr && std::strcmp(source_text, "member-dynamic") == 0)
            return prelogin_member_dynamic_label(label);

        if (source_text != nullptr && std::strcmp(source_text, "startup-member-dynamic") == 0)
            return prelogin_member_dynamic_label(label);

        if (source_text != nullptr && std::strcmp(source_text, "selected-member-dynamic") == 0)
            return prelogin_member_dynamic_label(label);

        return native_prelogin_atlas_label(label);
    }

    bool prelogin_ambiguous_command_cluster(const std::vector<PreloginNativeTextCandidate>& candidates, int best_source_rank)
    {
        auto count_labels = [&candidates, best_source_rank](const char* const* labels, size_t label_count) {
            size_t count = 0;
            for (size_t label_index = 0; label_index < label_count; ++label_index)
            {
                const char* label = labels[label_index];
                for (const auto& candidate : candidates)
                {
                    if (candidate.source_rank != best_source_rank)
                        continue;
                    if (candidate.value == label)
                    {
                        ++count;
                        break;
                    }
                }
            }
            return count;
        };

        static const char* const password_commands[] = {
            "Settings",
            "Connect",
            "Cancel"
        };
        if (count_labels(password_commands, sizeof(password_commands) / sizeof(password_commands[0])) > 1)
            return true;

        return false;
    }

    void append_reloaded_speech_queue(const std::string& text)
    {
        if (text.empty())
            return;

        const std::wstring queue_path = reloaded_speech_queue_path();
        const std::wstring queue_directory = parent_directory(queue_path);
        if (!queue_directory.empty())
            CreateDirectoryW(queue_directory.c_str(), nullptr);

        FILE* file = nullptr;
        if (_wfopen_s(&file, queue_path.c_str(), L"ab") != 0 || file == nullptr)
            return;

        std::string line = text;
        for (char& ch : line)
        {
            if (ch == '\r' || ch == '\n')
                ch = ' ';
        }

        std::fprintf(file, "%s\r\n", line.c_str());
        std::fclose(file);
    }

    bool dispatch_speech_sink_v1(const std::string& text, int interrupt) noexcept
    {
        const auto sink = g_speech_sink_v1.load(std::memory_order_acquire);
        if (sink == nullptr)
            return false;

        void* const context = g_speech_sink_context_v1.load(std::memory_order_acquire);
        try
        {
            sink(text.c_str(), interrupt, context);
        }
        catch (...)
        {
            // Never let a consumer exception escape back through a native focus hook.
        }
        return true;
    }

    void speak_prelogin_label(const char* reason, const std::string& label, void* focused_object)
    {
        std::lock_guard<std::mutex> guard(g_speech_lock);
        if (label.empty())
            return;

        const DWORD now = GetTickCount();
        if (label == g_last_spoken_prelogin_label &&
            (focused_object == g_last_spoken_prelogin_object ||
             (g_last_spoken_prelogin_tick != 0 && (now - g_last_spoken_prelogin_tick) <= 100)))
        {
            return;
        }

        g_last_spoken_prelogin_label = label;
        g_last_spoken_prelogin_object = focused_object;
        g_last_spoken_prelogin_tick = now;

        char line[256]{};
        std::snprintf(line, sizeof(line) - 1, "PRELOGIN_SPEAK queue reason=%s text=%s", reason == nullptr ? "" : reason, label.c_str());
        log_line(line);

        if (!dispatch_speech_sink_v1(label, 1) && g_reloaded_speech_queue_enabled.load())
            append_reloaded_speech_queue(label);
    }

    void clear_prelogin_duplicate_guard(void)
    {
        std::lock_guard<std::mutex> guard(g_speech_lock);
        g_last_spoken_prelogin_label.clear();
        g_last_spoken_prelogin_object = nullptr;
        g_last_spoken_prelogin_tick = 0;
    }

    bool prelogin_pml_focus_current_child(void* manager, void* focused_object)
    {
        if (manager == nullptr || focused_object == nullptr)
            return false;

        uintptr_t child = 0;
        if (read_ptr_safely(static_cast<const uint8_t*>(manager) + 0x164, &child) && child == reinterpret_cast<uintptr_t>(focused_object))
            return true;

        uintptr_t focus160 = 0;
        if (read_ptr_safely(static_cast<const uint8_t*>(manager) + 0x160, &focus160) && focus160 == reinterpret_cast<uintptr_t>(focused_object))
            return true;

        uintptr_t focus1c0 = 0;
        if (read_ptr_safely(static_cast<const uint8_t*>(manager) + 0x1c0, &focus1c0) && focus1c0 == reinterpret_cast<uintptr_t>(focused_object))
            return true;

        return false;
    }

    bool read_prelogin_object_rect(void* object, PreloginRect* rect)
    {
        if (object == nullptr || rect == nullptr)
            return false;

        uint32_t left = 0;
        uint32_t top = 0;
        uint32_t right = 0;
        uint32_t bottom = 0;
        if (!read_u32_safely(static_cast<const uint8_t*>(object) + 0x54, &left) ||
            !read_u32_safely(static_cast<const uint8_t*>(object) + 0x58, &top) ||
            !read_u32_safely(static_cast<const uint8_t*>(object) + 0x5C, &right) ||
            !read_u32_safely(static_cast<const uint8_t*>(object) + 0x60, &bottom))
        {
            return false;
        }

        rect->left = static_cast<int32_t>(left);
        rect->top = static_cast<int32_t>(top);
        rect->right = static_cast<int32_t>(right);
        rect->bottom = static_cast<int32_t>(bottom);
        return rect->right > rect->left &&
            rect->bottom > rect->top &&
            rect->left > -256 &&
            rect->top > -256 &&
            rect->right < 2048 &&
            rect->bottom < 2048;
    }

    bool rect_matches_exactly_or_nearly(const PreloginRect& left, const PreloginAtlasGeometry& right)
    {
        const int tolerance = 1;
        return std::abs(left.left - right.left) <= tolerance &&
            std::abs(left.top - right.top) <= tolerance &&
            std::abs(left.right - right.right) <= tolerance &&
            std::abs(left.bottom - right.bottom) <= tolerance;
    }

    bool native_prelogin_startup_member_list_focus_rect(void* object)
    {
        PreloginRect rect{};
        if (!read_prelogin_object_rect(object, &rect))
            return false;

        static const PreloginAtlasGeometry entries[] = {
            { 0, 0, 392, 232, "startup member list", 0x04B570D8u }
        };

        for (const auto& entry : entries)
        {
            if (rect_matches_exactly_or_nearly(rect, entry))
                return true;
        }

        return false;
    }

    auto best_native_pml_dynamic_text_from_object(void* object) -> std::string;
    bool prelogin_rect_equal(const PreloginRect& left, const PreloginRect& right);

    std::string native_prelogin_dynamic_label_from_member_model_link(uintptr_t object)
    {
        if (object < 0x10000)
            return {};

        static const uintptr_t linked_label_offsets[] = {
            0x0B4u,
            0x0B8u,
            0x114u,
            0x124u,
            0x128u,
            0x184u,
            0x18Cu,
            0x1E4u,
            0x2C0u,
            0x2CCu
        };

        for (const uintptr_t linked_label_offset : linked_label_offsets)
        {
            uintptr_t linked_object = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(object + linked_label_offset), &linked_object))
                continue;
            if (linked_object == 0 || linked_object == object || linked_object < 0x10000)
                continue;

            std::string label = best_native_pml_dynamic_text_from_object(reinterpret_cast<void*>(linked_object));
            if (prelogin_member_dynamic_label(label))
                return label;
        }

        return {};
    }

    std::string native_prelogin_startup_member_name_from_model_fields(void* object)
    {
        if (!native_prelogin_startup_member_list_focus_rect(object))
            return {};

        const uintptr_t base = reinterpret_cast<uintptr_t>(object);
        if (base == 0)
            return {};

        std::vector<uintptr_t> roots;
        roots.push_back(base);

        static const uintptr_t same_rect_child_offsets[] = {
            0x154u,
            0x158u
        };

        PreloginRect base_rect{};
        const bool have_base_rect = read_prelogin_object_rect(object, &base_rect);
        for (const uintptr_t same_rect_child_offset : same_rect_child_offsets)
        {
            uintptr_t child = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(base + same_rect_child_offset), &child))
                continue;
            if (child == 0 || child == base || child < 0x10000)
                continue;

            PreloginRect child_rect{};
            if (have_base_rect &&
                read_prelogin_object_rect(reinterpret_cast<void*>(child), &child_rect) &&
                prelogin_rect_equal(base_rect, child_rect) &&
                std::find(roots.begin(), roots.end(), child) == roots.end())
            {
                roots.push_back(child);
            }
        }

        for (const uintptr_t root : roots)
        {
            for (uintptr_t offset = 0x2A8u; offset <= 0x318u; offset += 4)
            {
                uintptr_t model_object = 0;
                if (!read_ptr_safely(reinterpret_cast<const void*>(root + offset), &model_object))
                    continue;
                if (model_object == 0 || model_object == root || model_object < 0x10000)
                    continue;

                std::string label = native_prelogin_dynamic_label_from_member_model_link(model_object);
                if (!prelogin_member_dynamic_label(label))
                    continue;

                char line[256]{};
                std::snprintf(
                    line,
                    sizeof(line) - 1,
                    "PRELOGIN_STARTUPMEMBER_MODEL candidate root=0x%p field=%03X object=0x%p text=%s",
                    reinterpret_cast<void*>(root),
                    static_cast<unsigned>(offset),
                    reinterpret_cast<void*>(model_object),
                    label.c_str());
                log_line(line);
                return label;
            }
        }

        return {};
    }

    std::string native_prelogin_startup_member_name_from_child_slots(void* object)
    {
        if (object == nullptr)
            return {};

        static const uintptr_t slot_offsets[] = {
            0x2CCu,
            0x2C0u
        };

        for (const uintptr_t offset : slot_offsets)
        {
            uintptr_t child = 0;
            if (!read_ptr_safely(static_cast<const uint8_t*>(object) + offset, &child))
                continue;
            if (child == 0 || child == reinterpret_cast<uintptr_t>(object))
                continue;

            std::string label = best_native_pml_dynamic_text_from_object(reinterpret_cast<void*>(child));
            if (prelogin_member_dynamic_label(label) && g_current_child_rejected_log_budget.fetch_sub(1) > 0)
            {
                char line[256]{};
                std::snprintf(
                    line,
                    sizeof(line) - 1,
                    "PRELOGIN_STARTUPMEMBER_SLOT rejected offset=%03X text=%s",
                    static_cast<unsigned>(offset),
                    label.c_str());
                log_line(line);
            }
        }

        return {};
    }

    std::string native_prelogin_startup_member_name_from_focus(void* manager, void* current_child_object)
    {
        UNREFERENCED_PARAMETER(manager);
        if (!native_prelogin_startup_member_list_focus_rect(current_child_object))
            return {};

        std::string label = native_prelogin_startup_member_name_from_model_fields(current_child_object);
        if (label.empty())
            label = native_prelogin_startup_member_name_from_child_slots(current_child_object);
        if (label.empty())
            label = read_native_prelogin_member_name();
        if (!prelogin_member_dynamic_label(label))
            return {};
        return label;
    }

    bool native_prelogin_startup_member_list_atlas_focus(void* object, const std::string& geometry_label, uint32_t atlas_resource)
    {
        if (object == nullptr)
            return false;
        return geometry_label == "Member List" && atlas_resource == 0x04B54740u;
    }

    std::string native_prelogin_startup_member_name_from_atlas_member_list_focus(
        void* manager,
        void* current_child_object,
        const std::string& geometry_label,
        uint32_t atlas_resource)
    {
        UNREFERENCED_PARAMETER(manager);
        if (!native_prelogin_startup_member_list_atlas_focus(current_child_object, geometry_label, atlas_resource))
            return {};

        std::string label = native_prelogin_startup_member_name_from_model_fields(current_child_object);
        if (label.empty())
            label = native_prelogin_startup_member_name_from_child_slots(current_child_object);
        if (label.empty())
            label = read_native_prelogin_member_name();
        if (!prelogin_member_dynamic_label(label))
            return {};
        return label;
    }

    bool native_prelogin_startup_member_list_static_focus(void* object, const std::string& static_label, uint32_t label_source_offset, uint32_t atlas_resource)
    {
        if (object == nullptr)
            return false;
        if (static_label != "Member List")
            return false;
        if (label_source_offset != 0x114)
            return false;
        if (atlas_resource != 0)
            return false;
        return true;
    }

    std::string native_prelogin_startup_member_name_from_static_member_list_focus(
        void* manager,
        void* current_child_object,
        const std::string& static_label,
        uint32_t label_source_offset,
        uint32_t atlas_resource)
    {
        UNREFERENCED_PARAMETER(manager);
        if (!native_prelogin_startup_member_list_static_focus(current_child_object, static_label, label_source_offset, atlas_resource))
            return {};

        std::string label = native_prelogin_startup_member_name_from_model_fields(current_child_object);
        if (label.empty())
            label = native_prelogin_startup_member_name_from_child_slots(current_child_object);
        if (label.empty())
            label = read_native_prelogin_member_name();
        if (!prelogin_member_dynamic_label(label))
            return {};
        return label;
    }

    bool prelogin_rect_equal(const PreloginRect& left, const PreloginRect& right)
    {
        return left.left == right.left &&
            left.top == right.top &&
            left.right == right.right &&
            left.bottom == right.bottom;
    }

    bool prelogin_member_dynamic_value_rect(void* object)
    {
        PreloginRect rect{};
        if (!read_prelogin_object_rect(object, &rect))
            return false;

        static const PreloginAtlasGeometry entries[] = {
            { 104, 122, 429, 146, "member dynamic value", 0x04B57640u },
            { 104, 114, 428, 138, "member dynamic value", 0x04B574B0u }
        };

        for (const auto& entry : entries)
        {
            if (rect_matches_exactly_or_nearly(rect, entry))
                return true;
        }

        return false;
    }

    auto best_native_pml_text_from_object(void* object, const char* source_text, bool* ambiguous = nullptr) -> std::string;

    bool native_prelogin_object_or_children_have_label(void* object, const char* expected)
    {
        if (object == nullptr || expected == nullptr || expected[0] == 0)
            return false;

        if (best_native_pml_text_from_object(object, "current-child") == expected)
            return true;

        const uintptr_t base = reinterpret_cast<uintptr_t>(object);
        if (base == 0)
            return false;

        for (uintptr_t offset = 0x20; offset <= 0x220; offset += 4)
        {
            uintptr_t child = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(base + offset), &child))
                continue;
            if (child == 0 || child == base)
                continue;

            if (best_native_pml_text_from_object(reinterpret_cast<void*>(child), "current-child") == expected)
                return true;
        }

        return false;
    }

    bool native_prelogin_form_root_has_rect(void* root, const PreloginAtlasGeometry& target)
    {
        if (root == nullptr)
            return false;

        PreloginRect root_rect{};
        if (read_prelogin_object_rect(root, &root_rect) && rect_matches_exactly_or_nearly(root_rect, target))
            return true;

        const uintptr_t base = reinterpret_cast<uintptr_t>(root);
        if (base == 0)
            return false;

        for (uintptr_t offset = 0x20; offset <= 0x340; offset += 4)
        {
            uintptr_t child = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(base + offset), &child))
                continue;
            if (child == 0 || child == base)
                continue;

            PreloginRect child_rect{};
            if (read_prelogin_object_rect(reinterpret_cast<void*>(child), &child_rect) &&
                rect_matches_exactly_or_nearly(child_rect, target))
            {
                return true;
            }
        }

        return false;
    }

    bool native_prelogin_add_member_form_root_has_required_rects(void* root)
    {
        static const PreloginAtlasGeometry required[] = {
            { 315, 71, 461, 103, "Member Name", 0x04B59408u },
            { 315, 99, 461, 131, "PlayOnline ID", 0x04B59548u },
            { 311, 131, 495, 155, "Set Password", 0x04B59598u },
            { 315, 209, 461, 241, "Member Password", 0x04B59318u },
            { 315, 291, 461, 323, "Square Enix ID", 0x04B595E8u },
            { 311, 323, 495, 347, "One-Time Password", 0x04B59638u }
        };

        int hits = 0;
        int bottom_hits = 0;
        for (const auto& entry : required)
        {
            if (!native_prelogin_form_root_has_rect(root, entry))
                continue;

            ++hits;
            if (entry.top >= 291)
                ++bottom_hits;
        }

        return hits >= 5 && bottom_hits >= 2;
    }

    void native_prelogin_add_form_root_candidate(uintptr_t* candidates, size_t* count, uintptr_t value)
    {
        if (candidates == nullptr || count == nullptr || value == 0)
            return;

        for (size_t index = 0; index < *count; ++index)
        {
            if (candidates[index] == value)
                return;
        }

        if (*count >= 24)
            return;

        candidates[*count] = value;
        ++(*count);
    }

    bool
    native_prelogin_add_member_form_context_uncached(void* object);

    bool native_prelogin_add_member_form_context(void* object)
    {
        if (object == nullptr)
            return false;

        const uintptr_t key = reinterpret_cast<uintptr_t>(object);
        PreloginRect rect{};
        const bool have_rect = read_prelogin_object_rect(object, &rect);
        const DWORD now = GetTickCount();

        {
            std::lock_guard<std::mutex> guard(g_add_member_context_cache_lock);
            for (const auto& entry : g_add_member_context_cache)
            {
                if (entry.object != key)
                    continue;
                if (entry.have_rect != have_rect)
                    continue;
                if (have_rect && !prelogin_rect_equal(entry.rect, rect))
                    continue;
                if ((now - entry.tick) <= AddMemberContextCacheTtlMs)
                    return entry.result;
            }
        }

        const bool result = native_prelogin_add_member_form_context_uncached(object);

        {
            std::lock_guard<std::mutex> guard(g_add_member_context_cache_lock);
            const size_t slot_count = sizeof(g_add_member_context_cache) / sizeof(g_add_member_context_cache[0]);
            auto& entry = g_add_member_context_cache[g_add_member_context_cache_cursor % slot_count];
            ++g_add_member_context_cache_cursor;
            entry.object = key;
            entry.rect = rect;
            entry.have_rect = have_rect;
            entry.result = result;
            entry.tick = now;
        }

        return result;
    }

    bool native_prelogin_add_member_form_context_uncached(void* object)
    {
        if (object == nullptr)
            return false;

        const uintptr_t base = reinterpret_cast<uintptr_t>(object);
        uintptr_t candidates[24]{};
        size_t candidate_count = 0;
        native_prelogin_add_form_root_candidate(candidates, &candidate_count, base);

        for (int depth = 0; depth < 6; ++depth)
        {
            const size_t limit = candidate_count;
            for (size_t index = 0; index < limit; ++index)
            {
                const uintptr_t node = candidates[index];
                uintptr_t parents[] = { 0, 0 };
                read_ptr_safely(reinterpret_cast<const void*>(node + 0x154), &parents[0]);
                read_ptr_safely(reinterpret_cast<const void*>(node + 0x158), &parents[1]);

                for (uintptr_t parent : parents)
                {
                    if (parent == node)
                        continue;
                    native_prelogin_add_form_root_candidate(candidates, &candidate_count, parent);
                }
            }
        }

        for (size_t index = 0; index < candidate_count; ++index)
        {
            if (native_prelogin_add_member_form_root_has_required_rects(reinterpret_cast<void*>(candidates[index])))
                return true;
        }
        return false;
    }

    bool native_prelogin_add_member_button_object_tree_label(void* object, const std::string& label)
    {
        if (object == nullptr)
            return false;
        if (label != "Register" && label != "Cancel")
            return false;

        PreloginRect rect{};
        if (!read_prelogin_object_rect(object, &rect))
            return false;

        if (!(rect.top >= 360 && rect.bottom >= 380))
            return false;

        if (label == "Register")
            return rect.left >= 200 && rect.left <= 260 && rect.right >= 330 && rect.right <= 380;

        if (label == "Cancel")
            return rect.left >= 330 && rect.left <= 390 && rect.right >= 450 && rect.right <= 510;

        return false;
    }

    bool native_prelogin_add_member_inner_textbox_child(void* object)
    {
        PreloginRect rect{};
        if (!read_prelogin_object_rect(object, &rect))
            return false;

        return rect.left >= 0 &&
            rect.top >= 0 &&
            rect.left <= 8 &&
            rect.top <= 8 &&
            rect.right <= 160 &&
            rect.bottom <= 32;
    }

    bool native_prelogin_add_member_current_child_speech_allowed(void* manager, void* current_child_object, const char* label_source, const std::string& label, bool current_child_is_tiny)
    {
        if (label_source == nullptr)
            label_source = "";

        if (std::strcmp(label_source, "atlas-geometry") == 0)
            return true;

        if (std::strcmp(label_source, "add-member") == 0 && prelogin_add_member_value_label(label))
            return !current_child_is_tiny;

        if (std::strcmp(label_source, "add-member-button") == 0 && prelogin_add_member_button_label(label))
            return true;

        const bool manager_is_form_root = native_prelogin_add_member_form_root_has_required_rects(manager);
        const bool manager_has_form_context = native_prelogin_add_member_form_context(manager);
        const bool current_has_form_context = native_prelogin_add_member_form_context(current_child_object);

        if (!manager_is_form_root && !manager_has_form_context && !current_has_form_context)
            return true;

        if (label == "Add Member")
            return false;

        return native_prelogin_add_member_button_object_tree_label(current_child_object, label);
    }

    std::string native_prelogin_add_member_label_from_geometry(void* object, const PreloginRect& rect, uint32_t* resource)
    {
        static const PreloginAtlasGeometry entries[] = {
            { 29, 69, 61, 101, "Member Name", 0x04B59408u },
            { 315, 71, 461, 103, "Member Name", 0x04B59408u },
            { 315, 99, 461, 131, "PlayOnline ID", 0x04B59548u },
            { 311, 131, 495, 155, "Set Password", 0x04B59598u },
            { 315, 209, 461, 241, "Member Password", 0x04B59318u },
            { 315, 237, 461, 269, "Confirm Password", 0x00000000u },
            { 315, 291, 461, 323, "Square Enix ID", 0x04B595E8u },
            { 424, 305, 534, 329, "What is a Square Enix ID", 0x00000000u },
            { 311, 323, 495, 347, "One-Time Password", 0x04B59638u }
        };

        const PreloginAtlasGeometry* matched = nullptr;
        for (const auto& entry : entries)
        {
            if (rect_matches_exactly_or_nearly(rect, entry))
            {
                matched = &entry;
                break;
            }
        }

        if (matched == nullptr || !native_prelogin_add_member_form_context(object))
            return {};

        if (resource != nullptr)
            *resource = matched->resource;
        return matched->label;
    }

    std::string native_prelogin_atlas_label_from_geometry(void* object, uint32_t* resource)
    {
        if (resource != nullptr)
            *resource = 0;

        PreloginRect rect{};
        if (!read_prelogin_object_rect(object, &rect))
            return {};

        std::string add_member_label = native_prelogin_add_member_label_from_geometry(object, rect, resource);
        if (!add_member_label.empty())
            return add_member_label;

        static const PreloginAtlasGeometry entries[] = {
            { 6, -26, 218, 18, "Member List", 0x04B54740u },
            { 6, 6, 218, 50, "Information", 0x04B546D0u },
            { 6, 38, 218, 82, "Guest Login", 0x04B54660u },
            { 6, 70, 218, 114, "Add Member", 0x04B545F0u },
            { 6, 102, 218, 146, "Check Files", 0x04B54580u },
            { 6, 134, 218, 178, "Join PlayOnline", 0x04B54510u },
            { 6, 166, 218, 210, "Network Settings", 0x04B544A0u },
            { 6, 198, 218, 242, "Security Settings", 0x04B54430u },
            { 6, 230, 218, 274, "Language Settings", 0x04B543C0u },
            { 6, 262, 218, 306, "Quick Manuals", 0x04B54350u },
            { 32, 294, 218, 338, "Exit Viewer", 0x04B542E0u },
            { 6, 32, 196, 76, "Log In", 0x04B54BA8u },
            { 6, 64, 196, 108, "Settings", 0x04B54B38u },
            { 6, 96, 196, 140, "Delete", 0x04B54AC8u },
            { 6, 128, 196, 172, "Back", 0x04B54A58u },
            { 75, 246, 505, 286, "Start PlayOnline Registration!", 0x04B57D00u },
            { 75, 286, 505, 326, "For PlayOnline Members!", 0x04B57C90u },
            { 56, 339, 176, 371, "Network", 0x04B57C20u },
            { 56, 339, 176, 371, "Network", 0x04B581B0u },
            { 186, 339, 306, 371, "Cancel", 0x04B57BB0u },
            { 186, 339, 306, 371, "Next", 0x04B58140u },
            { 316, 339, 436, 371, "Cancel", 0x04B580D0u },
            { 446, 339, 566, 371, "Language", 0x04B58060u },
            { 36, 24, 450, 56, "Login Information", 0x04B575F0u },
            { 44, 54, 436, 78, "Member Information", 0x04B575A0u },
            { 106, 79, 278, 102, "PlayOnline ID", 0x04B573C0u },
            { 106, 88, 246, 114, "PlayOnline ID", 0x04B57410u },
            { 106, 99, 278, 121, "Square Enix ID", 0x04B57370u },
            { 54, 53, 314, 77, "Square Enix Password", 0x04B7B910u },
            { 54, 62, 314, 86, "Square Enix Password", 0x04B7BEC0u },
            { 318, 49, 464, 81, "Square Enix Password", 0x04B7B910u },
            { 54, 88, 314, 112, "One-Time Password", 0x04B7C078u },
            { 54, 105, 314, 129, "One-Time Password", 0x04B7B8C0u },
            { 54, 114, 314, 138, "One-Time Password", 0x04B7BE70u },
            { 164, 152, 268, 176, "Yes", 0x00000000u },
            { 268, 152, 372, 176, "No", 0x00000000u },
            { 36, 84, 472, 116, "Network Settings", 0x04B59DF8u },
            { 55, 140, 276, 164, "Proxy server address", 0x04B59DA8u },
            { 55, 166, 276, 190, "Port", 0x04B59D58u },
            { 55, 192, 276, 216, "Security proxy", 0x04B59D08u },
            { 55, 218, 276, 242, "Port", 0x04B59CB8u },
            { 252, 262, 356, 286, "OK", 0x04B59C48u },
            { 356, 262, 460, 286, "Cancel", 0x04B59BD8u },
            { 55, 114, 276, 138, "Proxy server", 0x04B59B88u },
            { 36, 24, 472, 56, "Auxiliary Network Settings", 0x04B59B38u },
            { 32, 54, 276, 78, "Connection check", 0x04B59AE8u },
            { 278, 54, 465, 78, "Connection check", 0x04B59AE8u },
            { 278, 114, 465, 138, "Proxy server", 0x04B59B88u }
        };

        const PreloginAtlasGeometry* matched = nullptr;
        for (const auto& entry : entries)
        {
            if (!rect_matches_exactly_or_nearly(rect, entry))
                continue;

            if (matched != nullptr && std::strcmp(matched->label, entry.label) != 0)
            {
                char line[256]{};
                std::snprintf(
                    line,
                    sizeof(line) - 1,
                    "PRELOGIN_ATLASGEOM ambiguous rect=%d,%d,%d,%d left=%s right=%s",
                    rect.left,
                    rect.top,
                    rect.right,
                    rect.bottom,
                    matched->label,
                    entry.label);
                log_line(line);
                return {};
            }

            matched = &entry;
        }

        if (matched == nullptr)
            return {};

        if (resource != nullptr)
            *resource = matched->resource;
        return matched->label;
    }

    void log_current_child_detail(void* manager, void* requested_child, void* current_child_object, const char* outcome)
    {
        if (g_current_child_detail_budget.fetch_sub(1) <= 0)
            return;

        PreloginRect rect{};
        const bool have_rect = read_prelogin_object_rect(current_child_object, &rect);
        uint32_t f154 = 0, f158 = 0, f160 = 0, f164 = 0, f188 = 0, f18c = 0, f190 = 0, f194 = 0, f198 = 0, f19c = 0;
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x154, &f154);
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x158, &f158);
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x160, &f160);
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x164, &f164);
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x188, &f188);
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x18C, &f18c);
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x190, &f190);
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x194, &f194);
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x198, &f198);
        read_u32_safely(static_cast<const uint8_t*>(current_child_object) + 0x19C, &f19c);

        char line[512]{};
        std::snprintf(
            line,
            sizeof(line) - 1,
            "PRELOGIN_CURRENTCHILDDETAIL outcome=%s manager=0x%p requested=0x%p current=0x%p rect=%s%d,%d,%d,%d +154=%08X +158=%08X +160=%08X +164=%08X +188=%08X +18C=%08X +190=%08X +194=%08X +198=%08X +19C=%08X",
            outcome == nullptr ? "" : outcome,
            manager,
            requested_child,
            current_child_object,
            have_rect ? "" : "none:",
            rect.left,
            rect.top,
            rect.right,
            rect.bottom,
            f154,
            f158,
            f160,
            f164,
            f188,
            f18c,
            f190,
            f194,
            f198,
            f19c);
        log_line(line);
    }

    bool prelogin_pml_focus_can_claim_burst(const char* source_text, void* manager, void* focused_object, const std::string& label, bool focused_flag, bool snapshot_current_child)
    {
        if (source_text == nullptr)
            source_text = "";

        if (!prelogin_pml_focus_candidate_label_allowed(source_text, label))
            return false;

        if (std::strcmp(source_text, "selected-index") == 0)
            return true;

        if (std::strcmp(source_text, "selected-member-dynamic") == 0)
            return focused_flag && prelogin_member_dynamic_label(label);

        const bool current_child = snapshot_current_child || prelogin_pml_focus_current_child(manager, focused_object);

        if (std::strcmp(source_text, "direct-fields") == 0)
            return current_child && prelogin_setup_form_value_cell_label(source_text, label);

        uintptr_t real_current_child = 0;
        if (!snapshot_current_child &&
            manager != nullptr &&
            focused_object != nullptr &&
            read_ptr_safely(static_cast<const uint8_t*>(manager) + 0x164, &real_current_child) &&
            real_current_child != 0 &&
            real_current_child != reinterpret_cast<uintptr_t>(focused_object))
        {
            log_line("PRELOGIN_PMLFOCUSGAIN untrusted-silent reason=different-current-child");
            return false;
        }

        if (current_child || focused_flag)
            return true;

        if (std::strcmp(source_text, "semantic") == 0)
            return false;

        return false;
    }

    bool prelogin_pending_pml_focus_candidate_trusted_for_drain(const PreloginPmlFocusCandidate& candidate)
    {
        const char* source_text = candidate.source.c_str();
        if (!prelogin_pml_focus_candidate_label_allowed(candidate.source.c_str(), candidate.label))
            return false;

        if (std::strcmp(source_text, "selected-index") == 0)
            return true;

        if (std::strcmp(source_text, "selected-member-dynamic") == 0)
            return candidate.focused_flag && prelogin_member_dynamic_label(candidate.label);

        if (std::strcmp(source_text, "direct-fields") == 0)
            return candidate.current_child && prelogin_setup_form_value_cell_label(source_text, candidate.label);

        return candidate.current_child &&
            (std::strcmp(source_text, "semantic") == 0 ||
             prelogin_pml_focus_can_claim_burst(source_text, candidate.manager, candidate.focused_object, candidate.label, candidate.focused_flag, candidate.snapshot_current_child));
    }

    bool speak_pending_prelogin_pml_focus_candidate(const char* reason)
    {
        PreloginPmlFocusCandidate candidate;
        {
            std::lock_guard<std::mutex> guard(g_candidate_lock);
            if (!g_pending_pml_focus_candidate_valid)
                return false;
            candidate = g_pending_pml_focus_candidate;
            g_pending_pml_focus_candidate_valid = false;
        }

        const bool trusted_candidate = prelogin_pending_pml_focus_candidate_trusted_for_drain(candidate);
        if (!trusted_candidate)
        {
            log_line("PRELOGIN_PMLFOCUSGAIN untrusted-silent reason=trusted-candidate-filter");
            return true;
        }

        if (g_pml_coalesced_log_budget.fetch_sub(1) > 0)
        {
            char line[256]{};
            std::snprintf(line, sizeof(line) - 1, "PRELOGIN_PMLFOCUSGAIN coalesced-speak reason=%s text=%s", reason == nullptr ? "" : reason, candidate.label.c_str());
            log_line(line);
        }
        speak_prelogin_label(reason, candidate.label, candidate.focused_object);
        return true;
    }

    auto native_post_login_surface_active() -> bool;
    auto process_current_child_candidate(const PreloginCurrentChildSnapshot& snapshot, const char* reason) -> void;

    bool speak_current_prelogin_native_focus(const char* reason)
    {
        if (native_post_login_surface_active())
            return false;

        HMODULE app = GetModuleHandleA("app.dll");
        if (app == nullptr)
            return false;

        auto* app_base = reinterpret_cast<uint8_t*>(app);
        uintptr_t manager_value = 0;
        if (!read_ptr_safely(app_base + PmlGlobalFocusManagerRva, &manager_value) || manager_value == 0)
        {
            g_last_sampled_prelogin_focus_manager = 0;
            g_last_sampled_prelogin_focus_child = 0;
            return false;
        }

        auto* manager = reinterpret_cast<void*>(manager_value);
        uintptr_t current_child = 0;
        if (!read_ptr_safely(static_cast<const uint8_t*>(manager) + 0x164, &current_child) || current_child == 0)
        {
            g_last_sampled_prelogin_focus_manager = manager_value;
            g_last_sampled_prelogin_focus_child = 0;
            return false;
        }

        if (g_last_sampled_prelogin_focus_manager == manager_value &&
            g_last_sampled_prelogin_focus_child == current_child)
        {
            return false;
        }

        if (g_last_processed_prelogin_current_child == current_child)
        {
            g_last_sampled_prelogin_focus_manager = manager_value;
            g_last_sampled_prelogin_focus_child = current_child;
            return false;
        }

        g_last_sampled_prelogin_focus_manager = manager_value;
        g_last_sampled_prelogin_focus_child = current_child;

        PreloginCurrentChildSnapshot snapshot;
        snapshot.manager = manager;
        snapshot.requested_child = reinterpret_cast<void*>(current_child);
        snapshot.current_child = current_child;
        snapshot.tick = GetTickCount();
        process_current_child_candidate(snapshot, reason);
        return true;
    }

    std::string read_native_pml_string_field(uintptr_t field)
    {
        if (field == 0)
            return {};

        uint32_t length = 0;
        uint32_t capacity = 0;
        read_u32_safely(reinterpret_cast<const void*>(field + 0x10), &length);
        read_u32_safely(reinterpret_cast<const void*>(field + 0x14), &capacity);
        if (length == 0 || length > 120)
            return {};

        uintptr_t text_ptr = field;
        if (capacity >= 8)
        {
            uintptr_t heap_ptr = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(field), &heap_ptr) || heap_ptr == 0)
                return {};
            text_ptr = heap_ptr;
        }

        char buffer[128]{};
        const size_t wanted = std::min(static_cast<size_t>(length), sizeof(buffer) - 1);
        if (!copy_memory_safely(buffer, reinterpret_cast<const void*>(text_ptr), wanted))
            return {};
        return clean_text(buffer, static_cast<int>(wanted));
    }

    std::string read_native_pml_wide_string_field(uintptr_t field)
    {
        if (field == 0)
            return {};

        uint32_t length = 0;
        uint32_t capacity = 0;
        read_u32_safely(reinterpret_cast<const void*>(field + 0x10), &length);
        read_u32_safely(reinterpret_cast<const void*>(field + 0x14), &capacity);
        if (length == 0 || length > 120)
            return {};

        uintptr_t text_ptr = field;
        if (capacity >= 8)
        {
            uintptr_t heap_ptr = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(field), &heap_ptr) || heap_ptr == 0)
                return {};
            text_ptr = heap_ptr;
        }

        wchar_t buffer[128]{};
        const size_t wanted = std::min(static_cast<size_t>(length), (sizeof(buffer) / sizeof(buffer[0])) - 1);
        if (!copy_memory_safely(buffer, reinterpret_cast<const void*>(text_ptr), wanted * sizeof(wchar_t)))
            return {};
        return clean_wide_text(buffer, static_cast<int>(wanted));
    }

    std::string read_native_pml_c_string_pointer(uintptr_t pointer)
    {
        if (pointer < 0x10000)
            return {};

        char buffer[128]{};
        if (!copy_memory_safely(buffer, reinterpret_cast<const void*>(pointer), sizeof(buffer) - 1))
            return {};
        buffer[sizeof(buffer) - 1] = 0;
        return clean_text(buffer, -1);
    }

    std::string read_native_pml_wide_string_pointer(uintptr_t pointer)
    {
        if (pointer < 0x10000)
            return {};

        wchar_t buffer[128]{};
        const size_t max_chars = (sizeof(buffer) / sizeof(buffer[0])) - 1;
        if (!copy_memory_safely(buffer, reinterpret_cast<const void*>(pointer), max_chars * sizeof(wchar_t)))
            return {};
        buffer[max_chars] = 0;
        return clean_wide_text(buffer, -1);
    }

    bool prelogin_probe_candidate_label(const std::string& value)
    {
        if (!useful_text(value))
            return false;
        if (value.size() > 80)
            return false;

        const std::string lower = lower_copy(value);
        if (lower.find("http") != std::string::npos ||
            lower.find(".pml") != std::string::npos ||
            lower.find(".esd") != std::string::npos ||
            lower.find(".tm2") != std::string::npos ||
            lower.find("\\") != std::string::npos ||
            lower.find("/") != std::string::npos)
        {
            return false;
        }

        return true;
    }

    void log_startup_member_model_probe(void* object)
    {
        if (g_startup_member_model_probe_budget.fetch_sub(1) <= 0)
            return;
        if (!native_prelogin_startup_member_list_focus_rect(object))
            return;

        const uintptr_t base = reinterpret_cast<uintptr_t>(object);
        if (base == 0)
            return;

        std::vector<uintptr_t> roots;
        roots.push_back(base);

        PreloginRect base_rect{};
        const bool have_base_rect = read_prelogin_object_rect(object, &base_rect);
        static const uintptr_t same_rect_child_offsets[] = {
            0x154u,
            0x158u
        };

        for (const uintptr_t same_rect_child_offset : same_rect_child_offsets)
        {
            uintptr_t child = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(base + same_rect_child_offset), &child))
                continue;
            if (child == 0 || child == base || child < 0x10000)
                continue;

            PreloginRect child_rect{};
            if (have_base_rect &&
                read_prelogin_object_rect(reinterpret_cast<void*>(child), &child_rect) &&
                prelogin_rect_equal(base_rect, child_rect) &&
                std::find(roots.begin(), roots.end(), child) == roots.end())
            {
                roots.push_back(child);
            }
        }

        int object_budget = 24;
        int text_budget = 64;

        auto log_model_object = [&object_budget](const char* scope, uintptr_t root, uintptr_t field_offset, uintptr_t model_object, uintptr_t link_offset) {
            if (object_budget <= 0)
                return;
            --object_budget;

            PreloginRect rect{};
            const bool have_rect = read_prelogin_object_rect(reinterpret_cast<void*>(model_object), &rect);
            uintptr_t vtable = 0;
            read_ptr_safely(reinterpret_cast<const void*>(model_object), &vtable);

            char line[512]{};
            std::snprintf(
                line,
                sizeof(line) - 1,
                "PRELOGIN_STARTUPMEMBER_MODEL probe scope=%s root=0x%p field=%03X link=%03X object=0x%p vtable=0x%p rect=%s%d,%d,%d,%d",
                scope == nullptr ? "" : scope,
                reinterpret_cast<void*>(root),
                static_cast<unsigned>(field_offset),
                static_cast<unsigned>(link_offset),
                reinterpret_cast<void*>(model_object),
                reinterpret_cast<void*>(vtable),
                have_rect ? "" : "none:",
                rect.left,
                rect.top,
                rect.right,
                rect.bottom);
            log_line(line);
        };

        auto log_model_text = [&text_budget](const char* scope, uintptr_t root, uintptr_t field_offset, uintptr_t model_object, uintptr_t link_offset, uintptr_t text_offset, const char* kind, const std::string& value) {
            if (text_budget <= 0 || !prelogin_probe_candidate_label(value))
                return;
            --text_budget;

            char line[512]{};
            std::snprintf(
                line,
                sizeof(line) - 1,
                "PRELOGIN_STARTUPMEMBER_MODEL probe scope=%s root=0x%p field=%03X link=%03X object=0x%p offset=%03X kind=%s dynamic=%d atlas=%d text=%s",
                scope == nullptr ? "" : scope,
                reinterpret_cast<void*>(root),
                static_cast<unsigned>(field_offset),
                static_cast<unsigned>(link_offset),
                reinterpret_cast<void*>(model_object),
                static_cast<unsigned>(text_offset),
                kind == nullptr ? "" : kind,
                prelogin_member_dynamic_label(value) ? 1 : 0,
                native_prelogin_atlas_label(value) ? 1 : 0,
                value.c_str());
            log_line(line);
        };

        auto scan_model_text = [&log_model_text](const char* scope, uintptr_t root, uintptr_t field_offset, uintptr_t model_object, uintptr_t link_offset) {
            static const uintptr_t text_offsets[] = {
                0x0B4u,
                0x0B8u,
                0x0C4u,
                0x114u,
                0x124u,
                0x128u,
                0x140u,
                0x154u,
                0x158u,
                0x18Cu,
                0x190u,
                0x194u,
                0x19Cu,
                0x1A0u,
                0x1A8u,
                0x1E4u,
                0x2C0u,
                0x2CCu
            };

            for (const uintptr_t text_offset : text_offsets)
            {
                std::string value = read_native_pml_string_field(model_object + text_offset);
                log_model_text(scope, root, field_offset, model_object, link_offset, text_offset, "field-c", value);

                value = read_native_pml_wide_string_field(model_object + text_offset);
                log_model_text(scope, root, field_offset, model_object, link_offset, text_offset, "field-w", value);

                uintptr_t pointer = 0;
                if (!read_ptr_safely(reinterpret_cast<const void*>(model_object + text_offset), &pointer) ||
                    pointer == 0 ||
                    pointer == model_object ||
                    pointer < 0x10000)
                {
                    continue;
                }

                value = read_native_pml_c_string_pointer(pointer);
                log_model_text(scope, root, field_offset, model_object, link_offset, text_offset, "ptr-c", value);

                value = read_native_pml_wide_string_pointer(pointer);
                log_model_text(scope, root, field_offset, model_object, link_offset, text_offset, "ptr-w", value);
            }
        };

        static const uintptr_t linked_label_offsets[] = {
            0x0B4u,
            0x0B8u,
            0x114u,
            0x124u,
            0x128u,
            0x184u,
            0x18Cu,
            0x1E4u,
            0x2C0u,
            0x2CCu
        };

        for (const uintptr_t root : roots)
        {
            for (uintptr_t offset = 0x2A8u; offset <= 0x318u; offset += 4)
            {
                if (object_budget <= 0 && text_budget <= 0)
                    return;

                uintptr_t model_object = 0;
                if (!read_ptr_safely(reinterpret_cast<const void*>(root + offset), &model_object))
                    continue;
                if (model_object == 0 || model_object == root || model_object < 0x10000)
                    continue;

                log_model_object("model", root, offset, model_object, 0);
                scan_model_text("model", root, offset, model_object, 0);

                for (const uintptr_t linked_label_offset : linked_label_offsets)
                {
                    if (object_budget <= 0 && text_budget <= 0)
                        return;

                    uintptr_t linked_object = 0;
                    if (!read_ptr_safely(reinterpret_cast<const void*>(model_object + linked_label_offset), &linked_object))
                        continue;
                    if (linked_object == 0 || linked_object == model_object || linked_object < 0x10000)
                        continue;

                    log_model_object("linked", root, offset, linked_object, linked_label_offset);
                    scan_model_text("linked", root, offset, linked_object, linked_label_offset);
                }
            }
        }
    }

    void log_startup_member_probe(void* manager, void* current_child_object)
    {
        if (g_startup_member_probe_budget.fetch_sub(1) <= 0)
            return;

        const uintptr_t current = reinterpret_cast<uintptr_t>(current_child_object);
        const uintptr_t manager_address = reinterpret_cast<uintptr_t>(manager);
        if (current == 0)
            return;

        int child_budget = 16;
        int current_text_budget = 18;
        int manager_text_budget = 10;
        int child_text_budget = 48;

        auto log_member_source = [](const char* source, const std::string& value) {
            char line[512]{};
            std::snprintf(
                line,
                sizeof(line) - 1,
                "PRELOGIN_STARTUPMEMBER_PROBE member-source source=%s dynamic=%d atlas=%d text=%s",
                source == nullptr ? "" : source,
                prelogin_member_dynamic_label(value) ? 1 : 0,
                native_prelogin_atlas_label(value) ? 1 : 0,
                value.empty() ? "<empty>" : value.c_str());
            log_line(line);
        };

        HMODULE app = GetModuleHandleA("app.dll");
        if (app != nullptr)
        {
            auto* app_base = reinterpret_cast<uint8_t*>(app);
            const auto accessor = reinterpret_cast<MemberNameAccessor_t>(app_base + PreloginMemberNameAccessorRva);
            const wchar_t* wide_name = call_native_prelogin_member_name_accessor(accessor);
            log_member_source("accessor", read_wide_text_safely(wide_name, 64));
            log_member_source("global", read_wide_text_safely(reinterpret_cast<const wchar_t*>(app_base + PreloginMemberNameWideGlobalRva), 64));
        }

        log_startup_member_model_probe(reinterpret_cast<void*>(current));

        auto log_object = [](const char* scope, uintptr_t object, uint32_t via_offset) {
            PreloginRect rect{};
            const bool have_rect = read_prelogin_object_rect(reinterpret_cast<void*>(object), &rect);
            uintptr_t vtable = 0;
            read_ptr_safely(reinterpret_cast<const void*>(object), &vtable);

            char line[512]{};
            std::snprintf(
                line,
                sizeof(line) - 1,
                "PRELOGIN_STARTUPMEMBER_PROBE object scope=%s object=0x%p via=%03X vtable=0x%p rect=%s%d,%d,%d,%d",
                scope == nullptr ? "" : scope,
                reinterpret_cast<void*>(object),
                static_cast<unsigned>(via_offset),
                reinterpret_cast<void*>(vtable),
                have_rect ? "" : "none:",
                rect.left,
                rect.top,
                rect.right,
                rect.bottom);
            log_line(line);
        };

        auto log_text = [](const char* scope, uintptr_t object, uint32_t offset, const char* kind, const std::string& value, int* text_budget) {
            if (text_budget == nullptr || *text_budget <= 0 || !prelogin_probe_candidate_label(value))
                return;

            --(*text_budget);
            char line[512]{};
            std::snprintf(
                line,
                sizeof(line) - 1,
                "PRELOGIN_STARTUPMEMBER_PROBE text scope=%s object=0x%p offset=%03X kind=%s dynamic=%d atlas=%d text=%s",
                scope == nullptr ? "" : scope,
                reinterpret_cast<void*>(object),
                static_cast<unsigned>(offset),
                kind == nullptr ? "" : kind,
                prelogin_member_dynamic_label(value) ? 1 : 0,
                native_prelogin_atlas_label(value) ? 1 : 0,
                value.c_str());
            log_line(line);
        };

        auto scan_texts = [&log_text](const char* scope, uintptr_t object, int* text_budget) {
            if (object == 0)
                return;

            for (uintptr_t offset = 0x20; offset <= 0x420; offset += 4)
            {
                std::string value = read_native_pml_string_field(object + offset);
                log_text(scope, object, static_cast<uint32_t>(offset), "field-c", value, text_budget);

                value = read_native_pml_wide_string_field(object + offset);
                log_text(scope, object, static_cast<uint32_t>(offset), "field-w", value, text_budget);

                uintptr_t pointer = 0;
                if (!read_ptr_safely(reinterpret_cast<const void*>(object + offset), &pointer) || pointer == 0 || pointer == object)
                    continue;

                value = read_native_pml_c_string_pointer(pointer);
                log_text(scope, object, static_cast<uint32_t>(offset), "ptr-c", value, text_budget);

                value = read_native_pml_wide_string_pointer(pointer);
                log_text(scope, object, static_cast<uint32_t>(offset), "ptr-w", value, text_budget);
            }
        };

        log_object("current", current, 0);
        scan_texts("current", current, &current_text_budget);

        if (manager_address != 0 && manager_address != current)
        {
            log_object("manager", manager_address, 0);
            scan_texts("manager", manager_address, &manager_text_budget);
        }

        struct ProbeChild
        {
            uintptr_t object;
            uint32_t via_offset;
            bool same_rect;
        };
        std::vector<ProbeChild> child_candidates;
        PreloginRect current_rect{};
        const bool have_current_rect = read_prelogin_object_rect(reinterpret_cast<void*>(current), &current_rect);

        for (uintptr_t offset = 0x20; offset <= 0x420; offset += 4)
        {
            uintptr_t child = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(current + offset), &child))
                continue;
            if (child == 0 || child == current || child < 0x10000)
                continue;

            PreloginRect rect{};
            if (!read_prelogin_object_rect(reinterpret_cast<void*>(child), &rect))
                continue;

            bool duplicate = false;
            for (const auto& existing : child_candidates)
            {
                if (existing.object == child)
                {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate)
                continue;

            child_candidates.push_back(ProbeChild{
                child,
                static_cast<uint32_t>(offset),
                have_current_rect && prelogin_rect_equal(rect, current_rect)
            });
        }

        std::stable_sort(child_candidates.begin(), child_candidates.end(), [](const ProbeChild& left, const ProbeChild& right) {
            if (left.same_rect != right.same_rect)
                return !left.same_rect;
            return left.via_offset < right.via_offset;
        });

        for (const auto& child : child_candidates)
        {
            if (child_budget <= 0 || child_text_budget <= 0)
                break;

            --child_budget;
            log_object("child", child.object, child.via_offset);
            int per_child_text_budget = std::min(12, child_text_budget);
            const int before_child_scan = per_child_text_budget;
            scan_texts("child", child.object, &per_child_text_budget);
            child_text_budget -= before_child_scan - per_child_text_budget;
        }
    }

    void add_unique_allowed_candidate(std::vector<PreloginNativeTextCandidate>* candidates, const char* source_text, const std::string& value, uint32_t offset, int source_rank)
    {
        if (candidates == nullptr)
            return;
        if (!prelogin_pml_focus_candidate_label_allowed(source_text, value))
            return;

        for (auto& candidate : *candidates)
        {
            if (candidate.value != value)
                continue;

            if (source_rank < candidate.source_rank ||
                (source_rank == candidate.source_rank && offset < candidate.offset))
            {
                candidate.offset = offset;
                candidate.source_rank = source_rank;
            }
            return;
        }

        PreloginNativeTextCandidate candidate{};
        candidate.value = value;
        candidate.offset = offset;
        candidate.source_rank = source_rank;
        candidates->push_back(candidate);
    }

    std::string best_native_pml_text_from_object(void* object, const char* source_text, bool* ambiguous)
    {
        if (ambiguous != nullptr)
            *ambiguous = false;

        const uintptr_t base = reinterpret_cast<uintptr_t>(object);
        if (base == 0)
            return {};

        std::vector<PreloginNativeTextCandidate> candidates;
        for (uintptr_t offset = 0x20; offset <= 0x420; offset += 4)
        {
            auto value = read_native_pml_string_field(base + offset);
            if (value.empty())
                value = read_native_pml_wide_string_field(base + offset);
            add_unique_allowed_candidate(&candidates, source_text, value, static_cast<uint32_t>(offset), 0);

            uintptr_t pointer = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(base + offset), &pointer) || pointer == 0 || pointer == base)
                continue;

            value = read_native_pml_c_string_pointer(pointer);
            add_unique_allowed_candidate(&candidates, source_text, value, static_cast<uint32_t>(offset), 1);

            value = read_native_pml_wide_string_pointer(pointer);
            add_unique_allowed_candidate(&candidates, source_text, value, static_cast<uint32_t>(offset), 1);
        }

        if (candidates.empty())
            return {};

        int best_source_rank = candidates.front().source_rank;
        for (const auto& candidate : candidates)
            best_source_rank = std::min(best_source_rank, candidate.source_rank);

        if (prelogin_ambiguous_command_cluster(candidates, best_source_rank))
        {
            if (ambiguous != nullptr)
                *ambiguous = true;
            return {};
        }

        std::sort(candidates.begin(), candidates.end(), [](const PreloginNativeTextCandidate& left, const PreloginNativeTextCandidate& right) {
            if (left.source_rank != right.source_rank)
                return left.source_rank < right.source_rank;

            const bool left_native = native_prelogin_atlas_label(left.value);
            const bool right_native = native_prelogin_atlas_label(right.value);
            if (left_native != right_native)
                return left_native > right_native;

            if (left.offset != right.offset)
                return left.offset < right.offset;

            return left.value < right.value;
        });
        return candidates.front().value;
    }

    void add_unique_dynamic_candidate(std::vector<std::string>* candidates, const std::string& value)
    {
        if (candidates == nullptr)
            return;
        if (!prelogin_member_dynamic_label(value))
            return;
        if (std::find(candidates->begin(), candidates->end(), value) == candidates->end())
            candidates->push_back(value);
    }

    std::string best_native_pml_dynamic_text_from_object(void* object)
    {
        const uintptr_t base = reinterpret_cast<uintptr_t>(object);
        if (base == 0)
            return {};

        std::vector<std::string> candidates;
        for (uintptr_t offset = 0x20; offset <= 0x420; offset += 4)
        {
            auto value = read_native_pml_string_field(base + offset);
            if (value.empty())
                value = read_native_pml_wide_string_field(base + offset);
            if (prelogin_member_dynamic_label(value))
                add_unique_dynamic_candidate(&candidates, value);

            uintptr_t pointer = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(base + offset), &pointer) || pointer == 0 || pointer == base)
                continue;

            value = read_native_pml_c_string_pointer(pointer);
            if (prelogin_member_dynamic_label(value))
                add_unique_dynamic_candidate(&candidates, value);

            value = read_native_pml_wide_string_pointer(pointer);
            if (prelogin_member_dynamic_label(value))
                add_unique_dynamic_candidate(&candidates, value);
        }

        if (candidates.empty())
            return {};

        std::sort(candidates.begin(), candidates.end(), [](const std::string& left, const std::string& right) {
            if (left.size() != right.size())
                return left.size() < right.size();
            return left < right;
        });
        return candidates.front();
    }

    bool native_prelogin_object_tree_has_dynamic_member_value(void* object)
    {
        if (object == nullptr)
            return false;
        if (prelogin_member_dynamic_value_rect(object))
            return true;

        const uintptr_t base = reinterpret_cast<uintptr_t>(object);
        if (base == 0)
            return false;

        for (uintptr_t offset = 0x20; offset <= 0x220; offset += 4)
        {
            uintptr_t child = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(base + offset), &child))
                continue;
            if (child == 0 || child == base)
                continue;

            if (prelogin_member_dynamic_value_rect(reinterpret_cast<void*>(child)))
                return true;
        }

        return false;
    }

    std::string best_native_pml_dynamic_text_from_object_tree(void* object)
    {
        if (object == nullptr)
            return {};
        if (prelogin_member_dynamic_value_rect(object))
        {
            std::string value = best_native_pml_dynamic_text_from_object(object);
            if (!value.empty())
                return value;
        }

        const uintptr_t base = reinterpret_cast<uintptr_t>(object);
        if (base == 0)
            return {};

        for (uintptr_t offset = 0x20; offset <= 0x220; offset += 4)
        {
            uintptr_t child = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(base + offset), &child))
                continue;
            if (child == 0 || child == base)
                continue;

            if (!prelogin_member_dynamic_value_rect(reinterpret_cast<void*>(child)))
                continue;

            std::string value = best_native_pml_dynamic_text_from_object(reinterpret_cast<void*>(child));
            if (!value.empty())
                return value;
        }

        return {};
    }

    bool native_prelogin_member_access_context(void* object)
    {
        if (object == nullptr)
            return false;
        if (prelogin_member_dynamic_value_rect(object))
            return true;
        if (!native_prelogin_object_tree_has_dynamic_member_value(object))
            return false;

        size_t corroborating_labels = 0;
        if (native_prelogin_object_or_children_have_label(object, "Login Information"))
            ++corroborating_labels;
        if (native_prelogin_object_or_children_have_label(object, "Member Information"))
            ++corroborating_labels;
        if (native_prelogin_object_or_children_have_label(object, "PlayOnline ID"))
            ++corroborating_labels;
        if (native_prelogin_object_or_children_have_label(object, "Square Enix ID"))
            ++corroborating_labels;

        return corroborating_labels >= 2;
    }

    std::string best_native_pml_text_from_object_tree(void* object, const char* source_text, uint32_t* source_offset)
    {
        if (source_offset != nullptr)
            *source_offset = 0;

        bool direct_ambiguous = false;
        std::string direct = best_native_pml_text_from_object(object, source_text, &direct_ambiguous);
        if (direct_ambiguous)
            return {};
        if (!direct.empty())
            return direct;

        const uintptr_t base = reinterpret_cast<uintptr_t>(object);
        if (base == 0)
            return {};

        for (uintptr_t offset = 0x20; offset <= 0x220; offset += 4)
        {
            uintptr_t child = 0;
            if (!read_ptr_safely(reinterpret_cast<const void*>(base + offset), &child))
                continue;
            if (child == 0 || child == base)
                continue;

            bool child_ambiguous = false;
            std::string child_label = best_native_pml_text_from_object(reinterpret_cast<void*>(child), source_text, &child_ambiguous);
            if (child_ambiguous)
                return {};
            if (child_label.empty())
                continue;

            if (source_offset != nullptr)
                *source_offset = static_cast<uint32_t>(offset);
            return child_label;
        }

        return {};
    }

    void remember_focus_candidate(const char* source_text, void* manager, void* focused_object, bool focused_flag)
    {
        if (focused_object == nullptr)
            return;

        std::string label = best_native_pml_text_from_object(focused_object, source_text);
        if (label.empty())
            label = best_native_pml_text_from_object(manager, source_text);
        if (label.empty())
            return;

        PreloginPmlFocusCandidate candidate;
        candidate.source = source_text == nullptr ? "semantic" : source_text;
        candidate.label = label;
        candidate.manager = manager;
        candidate.focused_object = focused_object;
        candidate.current_child = prelogin_pml_focus_current_child(manager, focused_object);
        candidate.focused_flag = focused_flag;
        candidate.tick = GetTickCount();

        if (!prelogin_pml_focus_can_claim_burst(candidate.source.c_str(), manager, focused_object, label, focused_flag, false))
            return;

        {
            std::lock_guard<std::mutex> guard(g_candidate_lock);
            g_pending_pml_focus_candidate = candidate;
            g_pending_pml_focus_candidate_valid = true;
        }

        speak_pending_prelogin_pml_focus_candidate("focus-event");
    }

    bool install_inline_jump(void* target, void* hook, size_t patch_size, void** trampoline)
    {
        if (target == nullptr || hook == nullptr || trampoline == nullptr || patch_size < 5)
            return false;
        if (*trampoline != nullptr)
            return true;

        auto* gateway = static_cast<uint8_t*>(VirtualAlloc(nullptr, patch_size + 5, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
        if (gateway == nullptr)
            return false;

        std::memcpy(gateway, target, patch_size);
        gateway[patch_size] = 0xE9;
        *reinterpret_cast<int32_t*>(gateway + patch_size + 1) =
            static_cast<int32_t>((reinterpret_cast<uint8_t*>(target) + patch_size) - (gateway + patch_size + 5));

        DWORD old_protect = 0;
        if (!VirtualProtect(target, patch_size, PAGE_EXECUTE_READWRITE, &old_protect))
            return false;

        auto* bytes = static_cast<uint8_t*>(target);
        bytes[0] = 0xE9;
        *reinterpret_cast<int32_t*>(bytes + 1) =
            static_cast<int32_t>(reinterpret_cast<uint8_t*>(hook) - (bytes + 5));
        for (size_t i = 5; i < patch_size; ++i)
            bytes[i] = 0x90;

        DWORD unused = 0;
        VirtualProtect(target, patch_size, old_protect, &unused);
        FlushInstructionCache(GetCurrentProcess(), target, patch_size);
        *trampoline = gateway;
        return true;
    }

    bool native_post_login_surface_active()
    {
        return GetModuleHandleA("FFXiMain.dll") != nullptr || GetModuleHandleA("ffximain.dll") != nullptr;
    }

    void record_native_selection_register(void* model)
    {
        if (native_post_login_surface_active())
            return;

        char line[128]{};
        std::snprintf(line, sizeof(line) - 1, "SELTRUTHREG model=0x%p", model);
        log_line(line);
    }

    void record_native_selection_interval(void* model, int first, int last)
    {
        if (native_post_login_surface_active())
            return;

        char line[160]{};
        if (model != nullptr && first <= last)
            std::snprintf(line, sizeof(line) - 1, "SELTRUTHSET model=0x%p first=%d last=%d", model, first, last);
        else
            std::snprintf(line, sizeof(line) - 1, "SELTRUTHMISS model=0x%p first=%d last=%d", model, first, last);
        log_line(line);
    }

    void __stdcall record_selection_model_range_change(void* model, int first, int last)
    {
        record_native_selection_interval(model, first, last);
    }

    using PmlIndexedChildAt_t = uintptr_t(__thiscall*)(void*, uint32_t);

    uintptr_t selected_child_from_native_index(void* model, uint32_t stored_index)
    {
        if (model == nullptr || stored_index > 10000u)
            return 0;

        HMODULE app = GetModuleHandleA("app.dll");
        if (app == nullptr)
            return 0;

        auto* app_base = reinterpret_cast<uint8_t*>(app);
        const auto lookup = reinterpret_cast<PmlIndexedChildAt_t>(app_base + PmlIndexedChildAtRva);
        uintptr_t slot = 0;

        __try
        {
            slot = lookup(static_cast<uint8_t*>(model) + 0x294, stored_index);
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            return 0;
        }

        if (slot == 0)
            return 0;

        uintptr_t selected_child = 0;
        if (!read_ptr_safely(reinterpret_cast<const void*>(slot), &selected_child))
            return 0;
        return selected_child;
    }

    void remember_selected_index_candidate(void* model, uint32_t requested_index)
    {
        if (native_post_login_surface_active())
            return;
        if (model == nullptr)
            return;

        uint32_t stored_index = requested_index;
        read_u32_safely(static_cast<const uint8_t*>(model) + 0x2A4, &stored_index);

        void* selected_child = reinterpret_cast<void*>(selected_child_from_native_index(model, stored_index));
        std::string label;
        const char* label_source = "selected-index";
        if (selected_child != nullptr)
            label = best_native_pml_text_from_object(selected_child, "selected-index");

        if (label.empty() && selected_child != nullptr && prelogin_member_dynamic_value_rect(selected_child))
        {
            label = best_native_pml_dynamic_text_from_object(selected_child);
            if (!label.empty())
                label_source = "selected-member-dynamic";
        }

        if (label.empty())
        {
            if (g_selected_index_no_label_log_budget.fetch_sub(1) > 0)
            {
                PreloginRect selected_rect{};
                const bool have_selected_rect = read_prelogin_object_rect(selected_child, &selected_rect);
                char line[256]{};
                std::snprintf(
                    line,
                    sizeof(line) - 1,
                    "PRELOGIN_SELECTEDINDEX no-label model=0x%p requested=%u stored=%u child=0x%p rect=%d,%d,%d,%d haveRect=%d",
                    model,
                    static_cast<unsigned>(requested_index),
                    static_cast<unsigned>(stored_index),
                    selected_child,
                    selected_rect.left,
                    selected_rect.top,
                    selected_rect.right,
                    selected_rect.bottom,
                    have_selected_rect ? 1 : 0);
                log_line(line);
            }
            clear_prelogin_duplicate_guard();
            return;
        }

        if (!prelogin_pml_focus_can_claim_burst(label_source, model, selected_child, label, true, false))
        {
            char line[256]{};
            std::snprintf(
                line,
                sizeof(line) - 1,
                "PRELOGIN_SELECTEDINDEX rejected model=0x%p requested=%u stored=%u child=0x%p text=%s",
                model,
                static_cast<unsigned>(requested_index),
                static_cast<unsigned>(stored_index),
                selected_child,
                label.c_str());
            log_line(line);
            clear_prelogin_duplicate_guard();
            return;
        }

        char line[256]{};
        std::snprintf(
            line,
            sizeof(line) - 1,
            "PRELOGIN_SELECTEDINDEX candidate model=0x%p requested=%u stored=%u child=0x%p text=%s",
            model,
            static_cast<unsigned>(requested_index),
            static_cast<unsigned>(stored_index),
            selected_child,
            label.c_str());
        log_line(line);

        PreloginPmlFocusCandidate candidate;
        candidate.source = label_source;
        candidate.label = label;
        candidate.manager = model;
        candidate.focused_object = selected_child;
        candidate.current_child = false;
        candidate.focused_flag = true;
        candidate.tick = GetTickCount();

        {
            std::lock_guard<std::mutex> guard(g_candidate_lock);
            g_pending_pml_focus_candidate = candidate;
            g_pending_pml_focus_candidate_valid = true;
        }

        speak_pending_prelogin_pml_focus_candidate("selected-index");
    }

    using SelectedIndexSetter_t = void(__thiscall*)(void*, uint32_t);

    void __fastcall hook_selected_index_setter(void* self, void*, uint32_t index)
    {
        const auto original = reinterpret_cast<SelectedIndexSetter_t>(g_selected_index_setter_trampoline);
        if (original != nullptr)
            original(self, index);

        remember_selected_index_candidate(self, index);
    }

    void remember_current_child_candidate(void* manager, void* requested_child)
    {
        if (native_post_login_surface_active())
            return;
        if (manager == nullptr)
            return;

        uintptr_t current_child = reinterpret_cast<uintptr_t>(requested_child);
        read_ptr_safely(static_cast<const uint8_t*>(manager) + 0x164, &current_child);

        PreloginCurrentChildSnapshot snapshot;
        snapshot.manager = manager;
        snapshot.requested_child = requested_child;
        snapshot.current_child = current_child;
        snapshot.tick = GetTickCount();

        {
            std::lock_guard<std::mutex> guard(g_current_child_lock);
            g_pending_current_child_snapshot = snapshot;
            g_pending_current_child_snapshot_valid = true;
        }
    }

    void process_current_child_candidate(const PreloginCurrentChildSnapshot& snapshot, const char* reason)
    {
        if (native_post_login_surface_active())
            return;

        void* manager = snapshot.manager;
        void* requested_child = snapshot.requested_child;
        uintptr_t current_child = snapshot.current_child;
        if (manager == nullptr)
            return;

        if (current_child == 0)
        {
            g_last_processed_prelogin_current_child = 0;
            g_last_processed_prelogin_current_child_tick = 0;
            clear_prelogin_duplicate_guard();
            return;
        }

        void* current_child_object = reinterpret_cast<void*>(current_child);
        const DWORD now = GetTickCount();
        if (current_child == g_last_processed_prelogin_current_child &&
            g_last_processed_prelogin_current_child_tick != 0 &&
            (now - g_last_processed_prelogin_current_child_tick) <= 150)
        {
            return;
        }

        g_last_processed_prelogin_current_child = current_child;
        g_last_processed_prelogin_current_child_tick = now;

        const bool current_child_is_tiny = native_prelogin_add_member_inner_textbox_child(current_child_object);
        uint32_t label_source_offset = 0;
        uint32_t atlas_resource = 0;
        std::string member_dynamic_label;
        if (native_prelogin_member_access_context(current_child_object))
            member_dynamic_label = best_native_pml_dynamic_text_from_object_tree(current_child_object);
        std::string geometry_label = native_prelogin_atlas_label_from_geometry(current_child_object, &atlas_resource);
        std::string label = member_dynamic_label;
        const bool member_dynamic_focus = !member_dynamic_label.empty();
        const char* label_source = member_dynamic_focus ? "member-dynamic" : "object-tree";
        const bool startup_member_focus_rect = native_prelogin_startup_member_list_focus_rect(current_child_object);
        if (startup_member_focus_rect)
            log_startup_member_probe(manager, current_child_object);
        if (label.empty() && startup_member_focus_rect)
        {
            label = native_prelogin_startup_member_name_from_focus(manager, current_child_object);
            if (!label.empty())
                label_source = "startup-member-dynamic";
        }
        const bool startup_member_atlas_focus =
            native_prelogin_startup_member_list_atlas_focus(current_child_object, geometry_label, atlas_resource);
        if (label.empty() && startup_member_atlas_focus)
        {
            label = native_prelogin_startup_member_name_from_atlas_member_list_focus(
                manager,
                current_child_object,
                geometry_label,
                atlas_resource);
            label_source = "startup-member-dynamic";
        }
        if (label.empty() && !startup_member_atlas_focus && !startup_member_focus_rect)
            label = best_native_pml_text_from_object_tree(current_child_object, "current-child", &label_source_offset);
        bool startup_member_static_focus = false;
        if (!member_dynamic_focus && std::strcmp(label_source, "object-tree") == 0)
            startup_member_static_focus = native_prelogin_startup_member_list_static_focus(current_child_object, label, label_source_offset, atlas_resource);
        if (startup_member_static_focus)
        {
            std::string startup_member_label = native_prelogin_startup_member_name_from_static_member_list_focus(manager, current_child_object, label, label_source_offset, atlas_resource);
            if (!startup_member_label.empty())
            {
                label = startup_member_label;
                label_source = "startup-member-dynamic";
                label_source_offset = 0;
            }
            else
            {
                label.clear();
                label_source = "startup-member-dynamic";
            }
        }
        const bool add_member_context = native_prelogin_add_member_form_context(manager) ||
            native_prelogin_add_member_form_context(current_child_object);
        const bool add_member_field_geometry_focus = add_member_context &&
            !geometry_label.empty() &&
            prelogin_add_member_field_geometry_label(geometry_label);

        if (add_member_field_geometry_focus)
        {
            if (!label.empty() && label != geometry_label)
            {
                char conflict[256]{};
                std::snprintf(
                    conflict,
                    sizeof(conflict) - 1,
                    "PRELOGIN_ATLASGEOM prefer-add-member-field-geometry resource=%08X objectText=%s geometryText=%s",
                    static_cast<unsigned>(atlas_resource),
                    label.c_str(),
                    geometry_label.c_str());
                if (g_atlas_geometry_conflict_log_budget.fetch_sub(1) > 0)
                    log_line(conflict);
            }
            label = geometry_label;
            label_source = "atlas-geometry";
        }

        bool add_member_value_candidate = add_member_context && prelogin_add_member_value_label(label);
        bool add_member_value_focus = add_member_value_candidate && !current_child_is_tiny;
        bool add_member_button_candidate = add_member_context && prelogin_add_member_button_label(label);
        bool add_member_button_focus = add_member_button_candidate &&
            !add_member_field_geometry_focus &&
            (native_prelogin_add_member_button_object_tree_label(current_child_object, label) ||
             (label == "Register" &&
              current_child_is_tiny &&
              label_source_offset == 0x114 &&
              native_prelogin_add_member_form_root_has_required_rects(manager)));
        if (add_member_value_focus)
            label_source = "add-member";
        else if (add_member_button_focus)
            label_source = "add-member-button";

        if (add_member_context && label.empty())
        {
            label = best_native_pml_text_from_object_tree(current_child_object, "add-member", &label_source_offset);
            add_member_value_candidate = add_member_context && prelogin_add_member_value_label(label);
            add_member_value_focus = add_member_value_candidate && !current_child_is_tiny;
            add_member_button_candidate = add_member_context && prelogin_add_member_button_label(label);
            add_member_button_focus = add_member_button_candidate &&
                !add_member_field_geometry_focus &&
                (native_prelogin_add_member_button_object_tree_label(current_child_object, label) ||
                 (label == "Register" &&
                  current_child_is_tiny &&
                  label_source_offset == 0x114 &&
                  native_prelogin_add_member_form_root_has_required_rects(manager)));
            if (add_member_value_focus)
                label_source = "add-member";
            else if (add_member_button_focus)
                label_source = "add-member-button";
        }

        if (!geometry_label.empty() && !add_member_value_focus && !add_member_button_focus && !member_dynamic_focus && !startup_member_atlas_focus)
        {
            if (!label.empty() && label != geometry_label)
            {
                char conflict[256]{};
                std::snprintf(
                    conflict,
                    sizeof(conflict) - 1,
                    "PRELOGIN_ATLASGEOM prefer-focused-geometry resource=%08X objectText=%s geometryText=%s",
                    static_cast<unsigned>(atlas_resource),
                    label.c_str(),
                    geometry_label.c_str());
            if (g_atlas_geometry_conflict_log_budget.fetch_sub(1) > 0)
                log_line(conflict);
            }
            label = geometry_label;
            label_source = "atlas-geometry";
        }

        if (label.empty() && prelogin_member_dynamic_value_rect(current_child_object))
        {
            label = best_native_pml_dynamic_text_from_object(current_child_object);
            if (!label.empty())
                label_source = "member-dynamic";
        }

        if (label.empty())
        {
            if (g_current_child_no_label_budget.fetch_sub(1) > 0)
            {
                log_current_child_detail(manager, requested_child, current_child_object, "no-label");
                char line[256]{};
                std::snprintf(
                    line,
                    sizeof(line) - 1,
                    "PRELOGIN_CURRENTCHILD no-label manager=0x%p requested=0x%p current=0x%p sourceOffset=%03X",
                    manager,
                    requested_child,
                    current_child_object,
                    static_cast<unsigned>(label_source_offset));
                log_line(line);
            }
            clear_prelogin_duplicate_guard();
            return;
        }

        if (!native_prelogin_add_member_current_child_speech_allowed(manager, current_child_object, label_source, label, current_child_is_tiny))
        {
            if (g_current_child_rejected_log_budget.fetch_sub(1) > 0)
            {
                char line[256]{};
                std::snprintf(
                    line,
                    sizeof(line) - 1,
                    "PRELOGIN_CURRENTCHILD rejected reason=add-member-inner-child manager=0x%p requested=0x%p current=0x%p source=%s text=%s",
                    manager,
                    requested_child,
                    current_child_object,
                    label_source,
                    label.c_str());
                log_line(line);
            }
            return;
        }

        const char* candidate_source =
            (std::strcmp(label_source, "add-member") == 0 ||
             std::strcmp(label_source, "add-member-button") == 0 ||
             std::strcmp(label_source, "member-dynamic") == 0 ||
             std::strcmp(label_source, "startup-member-dynamic") == 0) ? label_source : "current-child";
        if (!prelogin_pml_focus_can_claim_burst(candidate_source, manager, current_child_object, label, true, true))
        {
            log_current_child_detail(manager, requested_child, current_child_object, "rejected");
            char line[256]{};
            std::snprintf(
                line,
                sizeof(line) - 1,
                "PRELOGIN_CURRENTCHILD rejected manager=0x%p requested=0x%p current=0x%p source=%s resource=%08X sourceOffset=%03X text=%s",
                manager,
                requested_child,
                current_child_object,
                label_source,
                static_cast<unsigned>(atlas_resource),
                static_cast<unsigned>(label_source_offset),
                label.c_str());
            log_line(line);
            clear_prelogin_duplicate_guard();
            return;
        }

        if (g_current_child_candidate_log_budget.fetch_sub(1) > 0)
        {
            char line[256]{};
            std::snprintf(
                line,
                sizeof(line) - 1,
                "PRELOGIN_CURRENTCHILD candidate manager=0x%p requested=0x%p current=0x%p source=%s resource=%08X sourceOffset=%03X text=%s",
                manager,
                requested_child,
                current_child_object,
                label_source,
                static_cast<unsigned>(atlas_resource),
                static_cast<unsigned>(label_source_offset),
                label.c_str());
            log_line(line);
        }

        PreloginPmlFocusCandidate candidate;
        candidate.source = candidate_source;
        candidate.label = label;
        candidate.manager = manager;
        candidate.focused_object = current_child_object;
        candidate.current_child = true;
        candidate.focused_flag = true;
        candidate.snapshot_current_child = true;
        candidate.tick = GetTickCount();

        {
            std::lock_guard<std::mutex> guard(g_candidate_lock);
            g_pending_pml_focus_candidate = candidate;
            g_pending_pml_focus_candidate_valid = true;
        }

        speak_pending_prelogin_pml_focus_candidate(reason == nullptr ? "current-child" : reason);
    }

    bool process_queued_current_child_candidate(const char* reason)
    {
        PreloginCurrentChildSnapshot snapshot;
        {
            std::lock_guard<std::mutex> guard(g_current_child_lock);
            if (!g_pending_current_child_snapshot_valid)
                return false;
            snapshot = g_pending_current_child_snapshot;
            g_pending_current_child_snapshot_valid = false;
        }

        process_current_child_candidate(snapshot, reason);
        return true;
    }

    using PmlCurrentChildSetter_t = void(__thiscall*)(void*, void*, void*);

    void __fastcall hook_pml_current_child_setter(void* self, void*, void* new_child, void* update_context)
    {
        const auto original = reinterpret_cast<PmlCurrentChildSetter_t>(g_pml_current_child_setter_trampoline);
        if (original != nullptr)
            original(self, new_child, update_context);

        remember_current_child_candidate(self, new_child);
    }

    void install_native_selection_truth_hooks_once()
    {
        if (g_native_selection_truth_hooks_installed.exchange(true))
            return;

        HMODULE app = GetModuleHandleA("app.dll");
        if (app == nullptr)
        {
            g_native_selection_truth_hooks_installed.store(false);
            return;
        }

        if (!app_module_matches_known_updated_pol_build(app, "selection-truth"))
            return;

        auto* app_base = reinterpret_cast<uint8_t*>(app);
        auto* register_target = app_base + 0x00009E62u;
        UNREFERENCED_PARAMETER(register_target);
        auto* current_child_target = app_base + PmlCurrentChildSetterRva;
        auto* selected_index_target = app_base + SelectedIndexSetterRva;

        if (!install_inline_jump(current_child_target, reinterpret_cast<void*>(&hook_pml_current_child_setter), 7, &g_pml_current_child_setter_trampoline))
        {
            g_native_selection_truth_hooks_installed.store(false);
            log_line("PRELOGIN_CURRENTCHILD hook-install-failed rva=000044F1");
            return;
        }

        if (!install_inline_jump(selected_index_target, reinterpret_cast<void*>(&hook_selected_index_setter), 7, &g_selected_index_setter_trampoline))
        {
            g_native_selection_truth_hooks_installed.store(false);
            log_line("PRELOGIN_SELECTEDINDEX hook-install-failed rva=001DD903");
            return;
        }

        log_line("SELTRUTHREG install native-selection-register-only");
        log_line("PRELOGIN_CURRENTCHILD hook-installed rva=000044F1");
        log_line("PRELOGIN_SELECTEDINDEX hook-installed rva=001DD903 child-lookup-rva=00102B3B");
        log_line("PRELOGIN_TEXTSETTER hook-disabled rva=00064156 reason=crash-stability");
    }

    using PmlFocusEvent_t = void(__thiscall*)(void*, void*);

    bool focus_event_matches(void* self, void* event_info, void** focused_object)
    {
        if (event_info == nullptr)
            return false;

        uint32_t event_code = 0;
        if (!read_u32_safely(static_cast<const uint8_t*>(event_info) + 0x24, &event_code) || event_code != 0x400001u)
            return false;

        uintptr_t focused = 0;
        if (!read_ptr_safely(static_cast<const uint8_t*>(event_info) + 0x30, &focused) || focused == 0)
            return false;

        if (focused_object != nullptr)
            *focused_object = reinterpret_cast<void*>(focused);

        return self != nullptr;
    }

    bool focus_receiver_flag(void* self, void* focused_object)
    {
        if (self == nullptr || focused_object == nullptr)
            return false;

        uintptr_t value = 0;
        if (read_ptr_safely(static_cast<const uint8_t*>(self) + 0x160, &value) && value == reinterpret_cast<uintptr_t>(focused_object))
            return true;
        if (read_ptr_safely(static_cast<const uint8_t*>(self) + 0x1c0, &value) && value == reinterpret_cast<uintptr_t>(focused_object))
            return true;
        return false;
    }

    void __fastcall hook_pml_shared_focus_event(void* self, void*, void* event_info)
    {
        const auto original = reinterpret_cast<PmlFocusEvent_t>(g_pml_shared_focus_event_trampoline);
        if (original != nullptr)
            original(self, event_info);

        void* focused_object = nullptr;
        if (focus_event_matches(self, event_info, &focused_object))
            remember_focus_candidate("semantic", self, focused_object, focus_receiver_flag(self, focused_object));
    }

    void __fastcall hook_pml_select_focus_event(void* self, void*, void* event_info)
    {
        const auto original = reinterpret_cast<PmlFocusEvent_t>(g_pml_select_focus_event_trampoline);
        if (original != nullptr)
            original(self, event_info);

        void* focused_object = nullptr;
        if (focus_event_matches(self, event_info, &focused_object))
            remember_focus_candidate("semantic", self, focused_object, focus_receiver_flag(self, focused_object));
    }

    void install_pml_focus_event_call_hook_once()
    {
        if (g_pml_focus_event_hook_installed.exchange(true))
            return;

        HMODULE app = GetModuleHandleA("app.dll");
        if (app == nullptr)
        {
            g_pml_focus_event_hook_installed.store(false);
            return;
        }

        if (!app_module_matches_known_updated_pol_build(app, "focus-event"))
            return;

        auto* app_base = reinterpret_cast<uint8_t*>(app);
        bool ok = true;
        ok = install_inline_jump(app_base + PmlSharedFocusEventRva, reinterpret_cast<void*>(&hook_pml_shared_focus_event), 11, &g_pml_shared_focus_event_trampoline) && ok;
        ok = install_inline_jump(app_base + PmlSelectFocusEventRva, reinterpret_cast<void*>(&hook_pml_select_focus_event), 11, &g_pml_select_focus_event_trampoline) && ok;

        if (!ok)
        {
            g_pml_focus_event_hook_installed.store(false);
            log_line("PRELOGIN_PMLFOCUSGAIN hook-install-failed");
            return;
        }

        log_line("PRELOGIN_PMLFOCUSGAIN hook-installed rva=0005BBF5,00081D59");
    }

    void install_native_focus_event_dispatch_hooks_once()
    {
        if (g_native_focus_dispatch_hooks_installed.exchange(true))
            return;
        install_pml_focus_event_call_hook_once();
        log_line("PRELOGIN_NATIVEFOCUS dispatch-hooks-installed");
    }

    void reset_prelogin_runtime_speech_state(const char* reason)
    {
        {
            std::lock_guard<std::mutex> guard(g_candidate_lock);
            g_pending_pml_focus_candidate_valid = false;
        }
        {
            std::lock_guard<std::mutex> guard(g_current_child_lock);
            g_pending_current_child_snapshot_valid = false;
            g_pending_current_child_snapshot = {};
            g_last_processed_prelogin_current_child = 0;
            g_last_processed_prelogin_current_child_tick = 0;
            g_last_sampled_prelogin_focus_manager = 0;
            g_last_sampled_prelogin_focus_child = 0;
        }
        {
            std::lock_guard<std::mutex> guard(g_speech_lock);
            g_last_spoken_prelogin_label.clear();
            g_last_spoken_prelogin_object = nullptr;
            g_last_spoken_prelogin_tick = 0;
        }

        char line[160]{};
        std::snprintf(line, sizeof(line) - 1, "PRELOGIN reset reason=%s", reason == nullptr ? "" : reason);
        log_line(line);
    }

    void run_reloaded_native_hook_iteration()
    {
        install_native_focus_event_dispatch_hooks_once();
        install_pml_focus_event_call_hook_once();
        install_native_selection_truth_hooks_once();
        process_queued_current_child_candidate("reloaded-native-current-child");
        speak_pending_prelogin_pml_focus_candidate("reloaded-native-focus");
        speak_current_prelogin_native_focus("reloaded-native-focus");
    }

    void start_reloaded_native_hook_worker_once()
    {
        bool expected = false;
        if (!g_reloaded_native_worker_running.compare_exchange_strong(expected, true))
            return;

        std::thread([] {
            log_line("AccessXI POL Reloaded native hook worker started");
            while (g_reloaded_native_worker_running.load())
            {
                run_reloaded_native_hook_iteration();
                Sleep(20);
            }
        }).detach();
    }
}

class AccessXiPolPlugin final : public IPolPlugin
{
public:
    const char* GetName(void) const override { return "accessxi_pol_nvda"; }
    const char* GetAuthor(void) const override { return "buu42 and Codex"; }
    const char* GetDescription(void) const override { return "PlayOnline accessibility native focus bridge."; }
    const char* GetLink(void) const override { return "local"; }
    double GetVersion(void) const override { return 0.10; }
    double GetInterfaceVersion(void) const override { return ASHITA_INTERFACE_VERSION; }
    uint32_t GetFlags(void) const override { return static_cast<uint32_t>(Ashita::PluginFlags::UseCommands); }

    bool Initialize(IAshitaCore* core, ILogManager* logger, const uint32_t id) override
    {
        UNREFERENCED_PARAMETER(core);
        UNREFERENCED_PARAMETER(logger);
        UNREFERENCED_PARAMETER(id);
        log_line("AccessXI POL plugin initialized; Reloaded path owns pre-login speech.");
        return true;
    }

    void Release(void) override
    {
        log_line("AccessXI POL plugin releasing.");
    }

    bool HandleCommand(int32_t mode, const char* command, bool injected) override
    {
        UNREFERENCED_PARAMETER(mode);
        UNREFERENCED_PARAMETER(command);
        UNREFERENCED_PARAMETER(injected);
        return false;
    }
};

extern "C" __declspec(dllexport) IPolPlugin* __stdcall expCreatePolPlugin(const char* args)
{
    UNREFERENCED_PARAMETER(args);
    return new AccessXiPolPlugin();
}

extern "C" __declspec(dllexport) void __stdcall expDestroyPlugin(void* instance)
{
    delete static_cast<AccessXiPolPlugin*>(instance);
}

extern "C" __declspec(dllexport) double __stdcall expGetInterfaceVersion(void)
{
    return ASHITA_INTERFACE_VERSION;
}

extern "C" __declspec(dllexport) int __stdcall AccessXI_POL_SetSpeechSinkV1(
    AccessXiPolSpeechSinkV1 sink,
    void* context)
{
    if (sink == nullptr && context != nullptr)
        return 0;

    if (sink == nullptr)
    {
        g_speech_sink_v1.store(nullptr, std::memory_order_release);
        g_speech_sink_context_v1.store(nullptr, std::memory_order_release);
        return 1;
    }

    g_speech_sink_context_v1.store(context, std::memory_order_release);
    g_speech_sink_v1.store(sink, std::memory_order_release);
    return 1;
}

extern "C" __declspec(dllexport) int __stdcall AccessXI_POL_InitializeV2(void)
{
    const int current_state = g_native_initialize_state.load(std::memory_order_acquire);
    if (current_state == 2)
        return AccessXiPolInitializeAlreadyReady;
    if (current_state == 3)
        return AccessXiPolInitializeUnsupportedBuild;

    int expected_state = 0;
    if (!g_native_initialize_state.compare_exchange_strong(
            expected_state,
            1,
            std::memory_order_acq_rel,
            std::memory_order_acquire))
    {
        return expected_state == 2
            ? AccessXiPolInitializeAlreadyReady
            : AccessXiPolInitializeBusy;
    }

    HMODULE app_module = GetModuleHandleW(L"app.dll");
    if (app_module == nullptr)
    {
        g_native_initialize_state.store(0, std::memory_order_release);
        return AccessXiPolInitializeAppDllMissing;
    }
    if (!app_module_matches_known_updated_pol_build(app_module, "native-initialize-v2"))
    {
        g_native_initialize_state.store(3, std::memory_order_release);
        return AccessXiPolInitializeUnsupportedBuild;
    }

    log_line("AccessXI POL native V2 initializing");
    {
        const std::wstring log_directory = diagnostic_log_directory();
        const std::wstring queue_path = reloaded_speech_queue_path();
        const std::string line = "AccessXI POL native diagnostics mode=V2 log_dir=\"" +
            narrow_from_wide(log_directory.c_str()) +
            "\" queue=\"" +
            narrow_from_wide(queue_path.c_str()) +
            "\"";
        log_line(line.c_str());
    }
    reset_prelogin_runtime_speech_state("InitializeV2");
    install_native_focus_event_dispatch_hooks_once();
    install_pml_focus_event_call_hook_once();
    install_native_selection_truth_hooks_once();
    start_reloaded_native_hook_worker_once();
    g_native_initialize_state.store(2, std::memory_order_release);
    log_line("AccessXI POL native V2 hooks installed");
    return AccessXiPolInitializeOk;
}

extern "C" __declspec(dllexport) void __stdcall AccessXI_POL_ReloadedInitialize(void)
{
    g_reloaded_speech_queue_enabled.store(true);
    log_line("AccessXI POL Reloaded native initializing");
    const int result = AccessXI_POL_InitializeV2();
    if (result == AccessXiPolInitializeAlreadyReady)
        log_line("AccessXI POL Reloaded native already initialized");
    else if (result == AccessXiPolInitializeOk)
        log_line("AccessXI POL Reloaded native hooks installed");
}
