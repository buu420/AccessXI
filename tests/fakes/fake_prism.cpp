#include <prism.h>

#include <Windows.h>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <string>

struct PrismContext
{
    int marker = 1;
};

struct PrismBackend
{
    PrismBackendId id = PRISM_BACKEND_INVALID;
    bool best = false;
};

namespace
{
    std::atomic<unsigned long> g_output_count{0};

    std::string environment(const char* name)
    {
        char value[1024]{};
        const DWORD copied = GetEnvironmentVariableA(name, value, static_cast<DWORD>(sizeof(value)));
        if (copied == 0 || copied >= sizeof(value))
            return {};
        return std::string(value, copied);
    }

    void log_line(const char* format, ...)
    {
        const std::string path = environment("ACCESSXI_FAKE_PRISM_LOG");
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

    const char* backend_name(PrismBackendId id, bool best)
    {
        if (best)
            return "BEST";
        if (id == PRISM_BACKEND_NVDA)
            return "NVDA";
        if (id == PRISM_BACKEND_JAWS)
            return "JAWS";
        if (id == PRISM_BACKEND_UIA)
            return "UIA";
        return "UNKNOWN";
    }
}

extern "C" PRISM_API PrismContext* PRISM_CALL prism_init(PrismConfig*)
{
    log_line("init tid=%lu", GetCurrentThreadId());
    if (environment("ACCESSXI_FAKE_PRISM_CONTEXT_FAIL") == "1")
        return nullptr;
    return new PrismContext();
}

extern "C" PRISM_API void PRISM_CALL prism_shutdown(PrismContext* context)
{
    log_line("shutdown tid=%lu", GetCurrentThreadId());
    delete context;
}

extern "C" PRISM_API PrismBackend* PRISM_CALL prism_registry_create(
    PrismContext*,
    PrismBackendId id)
{
    log_line("create name=%s tid=%lu", backend_name(id, false), GetCurrentThreadId());
    auto* backend = new PrismBackend();
    backend->id = id;
    return backend;
}

extern "C" PRISM_API PrismBackend* PRISM_CALL prism_registry_create_best(PrismContext*)
{
    log_line("create-best tid=%lu", GetCurrentThreadId());
    auto* backend = new PrismBackend();
    backend->best = true;
    return backend;
}

extern "C" PRISM_API PrismError PRISM_CALL prism_backend_initialize(PrismBackend* backend)
{
    if (backend == nullptr)
        return PRISM_ERROR_INVALID_PARAM;
    const char* name = backend_name(backend->id, backend->best);
    const bool succeeds = environment("ACCESSXI_FAKE_PRISM_SUCCESS_BACKEND") == name;
    log_line("backend-initialize name=%s result=%s tid=%lu", name, succeeds ? "ok" : "fail", GetCurrentThreadId());
    return succeeds ? PRISM_OK : PRISM_ERROR_BACKEND_NOT_AVAILABLE;
}

extern "C" PRISM_API void PRISM_CALL prism_backend_free(PrismBackend* backend)
{
    log_line("backend-free tid=%lu", GetCurrentThreadId());
    delete backend;
}

extern "C" PRISM_API const char* PRISM_CALL prism_backend_name(PrismBackend* backend)
{
    return backend == nullptr ? "" : backend_name(backend->id, backend->best);
}

extern "C" PRISM_API PrismError PRISM_CALL prism_backend_output(
    PrismBackend*,
    const char* text,
    bool interrupt)
{
    const unsigned long output = g_output_count.fetch_add(1) + 1;
    const bool fail = environment("ACCESSXI_FAKE_PRISM_FAIL_FIRST_OUTPUT") == "1" && output == 1;
    log_line(
        "output count=%lu interrupt=%d result=%s tid=%lu text=%s",
        output,
        interrupt ? 1 : 0,
        fail ? "fail" : "ok",
        GetCurrentThreadId(),
        text == nullptr ? "" : text);
    return fail ? PRISM_ERROR_SPEAK_FAILURE : PRISM_OK;
}

extern "C" PRISM_API PrismError PRISM_CALL prism_backend_stop(PrismBackend*)
{
    log_line("stop tid=%lu", GetCurrentThreadId());
    return PRISM_OK;
}
