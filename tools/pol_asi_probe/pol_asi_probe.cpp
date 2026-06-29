#include <windows.h>
#include <stdio.h>
#include <string.h>

static volatile LONG gBootstrapStarted = 0;

static void WriteBootstrapMarker(const char* eventName)
{
    char userProfile[MAX_PATH] = {};
    DWORD userProfileLength = GetEnvironmentVariableA("USERPROFILE", userProfile, MAX_PATH);
    if (userProfileLength == 0 || userProfileLength >= MAX_PATH)
        return;

    char accessXiDirectory[MAX_PATH] = {};
    snprintf(accessXiDirectory, MAX_PATH, "%s\\AccessXI", userProfile);
    CreateDirectoryA(accessXiDirectory, nullptr);

    char logDirectory[MAX_PATH] = {};
    snprintf(logDirectory, MAX_PATH, "%s\\logs", accessXiDirectory);
    CreateDirectoryA(logDirectory, nullptr);

    char logPath[MAX_PATH] = {};
    snprintf(logPath, MAX_PATH, "%s\\pol-reloaded-bootstrap.log", logDirectory);

    HANDLE file = CreateFileA(logPath, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return;

    SYSTEMTIME time = {};
    GetLocalTime(&time);

    char line[512] = {};
    int lineLength = snprintf(
        line,
        sizeof(line),
        "%04u-%02u-%02uT%02u:%02u:%02u.%03u AccessXI_POL_RELOADED_BOOTSTRAP %s pid=%lu\r\n",
        time.wYear,
        time.wMonth,
        time.wDay,
        time.wHour,
        time.wMinute,
        time.wSecond,
        time.wMilliseconds,
        eventName,
        GetCurrentProcessId());

    if (lineLength > 0)
    {
        DWORD written = 0;
        WriteFile(file, line, (DWORD)lineLength, &written, nullptr);
    }

    CloseHandle(file);
}

static void CallReloadedBootstrapper()
{
    char exePath[MAX_PATH] = {};
    if (GetModuleFileNameA(nullptr, exePath, MAX_PATH) == 0)
    {
        WriteBootstrapMarker("bootstrap-exe-path-failed");
        return;
    }

    char* lastSlash = strrchr(exePath, '\\');
    if (lastSlash == nullptr)
    {
        WriteBootstrapMarker("bootstrap-exe-directory-failed");
        return;
    }

    *lastSlash = '\0';

    char bootstrapperPath[MAX_PATH] = {};
    snprintf(bootstrapperPath, MAX_PATH, "%s\\scripts\\Reloaded.Mod.Loader.Bootstrapper.dll", exePath);

    HMODULE bootstrapper = LoadLibraryA(bootstrapperPath);
    if (bootstrapper == nullptr)
    {
        char line[128] = {};
        snprintf(line, sizeof(line), "bootstrap-loadlibrary-failed error=%lu", GetLastError());
        WriteBootstrapMarker(line);
        return;
    }

    WriteBootstrapMarker("bootstrap-loadlibrary-ok");

    using InitializeAsiFn = void (*)();
    auto initializeAsi = reinterpret_cast<InitializeAsiFn>(GetProcAddress(bootstrapper, "InitializeASI"));
    if (initializeAsi == nullptr)
    {
        char line[128] = {};
        snprintf(line, sizeof(line), "bootstrap-getproc-failed error=%lu", GetLastError());
        WriteBootstrapMarker(line);
        return;
    }

    WriteBootstrapMarker("bootstrap-getproc-ok");

    __try
    {
        initializeAsi();
        WriteBootstrapMarker("bootstrap-initialize-returned");
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        char line[128] = {};
        snprintf(line, sizeof(line), "bootstrap-initialize-exception code=0x%08lx", GetExceptionCode());
        WriteBootstrapMarker(line);
    }
}

static DWORD WINAPI BootstrapThread(LPVOID)
{
    WriteBootstrapMarker("worker-start");

    for (int attempt = 0; attempt < 100; attempt++)
    {
        if (GetModuleHandleA("USER32.dll") != nullptr && GetModuleHandleA("PolHook.dll") != nullptr)
            break;

        Sleep(100);
    }

    WriteBootstrapMarker("worker-calling-reloaded");
    CallReloadedBootstrapper();
    WriteBootstrapMarker("worker-end");
    return 0;
}

static void StartBootstrapThread(const char* source)
{
    if (InterlockedExchange(&gBootstrapStarted, 1) != 0)
    {
        WriteBootstrapMarker("thread-already-started");
        return;
    }

    char line[128] = {};
    snprintf(line, sizeof(line), "thread-start-request source=%s", source);
    WriteBootstrapMarker(line);

    HANDLE thread = CreateThread(nullptr, 0, BootstrapThread, nullptr, 0, nullptr);
    if (thread == nullptr)
    {
        char failure[128] = {};
        snprintf(failure, sizeof(failure), "thread-create-failed error=%lu", GetLastError());
        WriteBootstrapMarker(failure);
        return;
    }

    CloseHandle(thread);
}

extern "C" __declspec(dllexport) void InitializeASI()
{
    WriteBootstrapMarker("InitializeASI");
    StartBootstrapThread("InitializeASI");
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls(module);
        WriteBootstrapMarker("DllMain");
    }

    return TRUE;
}
