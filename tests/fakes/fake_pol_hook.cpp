#include <Windows.h>
#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <string>

namespace
{
    using SpeechSinkV1 = void (__stdcall *)(const char*, int, void*);

    std::atomic<SpeechSinkV1> g_sink{nullptr};
    std::atomic<void*> g_context{nullptr};

    std::string environment(const char* name)
    {
        char value[2048]{};
        const DWORD copied = GetEnvironmentVariableA(name, value, static_cast<DWORD>(sizeof(value)));
        if (copied == 0 || copied >= sizeof(value))
            return {};
        return std::string(value, copied);
    }

    void log_line(const char* format, ...)
    {
        const std::string path = environment("ACCESSXI_FAKE_HOOK_LOG");
        if (path.empty())
            return;

        HANDLE file = CreateFileA(
            path.c_str(),
            FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            nullptr,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
        if (file == INVALID_HANDLE_VALUE)
            return;

        char line[2048]{};
        va_list arguments;
        va_start(arguments, format);
        const int length = vsnprintf(line, sizeof(line) - 3, format, arguments);
        va_end(arguments);
        if (length > 0)
        {
            const size_t used = static_cast<size_t>(length) < sizeof(line) - 3
                ? static_cast<size_t>(length)
                : sizeof(line) - 3;
            line[used] = '\r';
            line[used + 1] = '\n';
            DWORD written = 0;
            WriteFile(file, line, static_cast<DWORD>(used + 2), &written, nullptr);
        }
        CloseHandle(file);
    }

    int environment_integer(const char* name, int fallback)
    {
        const std::string value = environment(name);
        if (value.empty())
            return fallback;
        return std::atoi(value.c_str());
    }
}

#if !defined(ACCESSXI_FAKE_HOOK_OMIT_SINK)
extern "C" __declspec(dllexport) int __stdcall AccessXI_POL_SetSpeechSinkV1(
    SpeechSinkV1 sink,
    void* context)
{
    log_line("sink-register tid=%lu", GetCurrentThreadId());
    g_context.store(context, std::memory_order_release);
    g_sink.store(sink, std::memory_order_release);
    return 1;
}
#endif

#if !defined(ACCESSXI_FAKE_HOOK_OMIT_INIT)
extern "C" __declspec(dllexport) int __stdcall AccessXI_POL_InitializeV2()
{
    log_line("initialize-v2 tid=%lu", GetCurrentThreadId());
    SpeechSinkV1 sink = g_sink.load(std::memory_order_acquire);
    void* context = g_context.load(std::memory_order_acquire);
    const std::string text = environment("ACCESSXI_FAKE_HOOK_EMIT_TEXT");
    if (sink != nullptr && !text.empty())
    {
        std::string mutable_text = text;
        sink(mutable_text.c_str(), 1, context);
        std::fill(mutable_text.begin(), mutable_text.end(), 'X');
    }

    const int stress_count = environment_integer("ACCESSXI_FAKE_HOOK_STRESS_COUNT", 0);
    for (int index = 0; sink != nullptr && index < stress_count; ++index)
    {
        char line[64]{};
        std::snprintf(line, sizeof(line), "stress-%d", index);
        sink(line, 1, context);
    }
    return environment_integer("ACCESSXI_FAKE_HOOK_INIT_RESULT", 1);
}
#endif
