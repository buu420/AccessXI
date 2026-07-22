#include "pol_native/diagnostics.h"
#include "pol_native/speech_worker.h"

#include <Windows.h>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>

namespace
{
    using accessxi::pol_native::Diagnostics;
    using accessxi::pol_native::SpeechWorker;
    using namespace std::chrono_literals;

    void require(bool condition, const char* message)
    {
        if (!condition)
        {
            std::cerr << "FAIL: " << message << '\n';
            std::exit(1);
        }
    }

    std::string read_text(const std::filesystem::path& path)
    {
        std::ifstream input(path, std::ios::binary);
        return std::string(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
    }

    bool wait_for_text(const std::filesystem::path& path, const std::string& needle, std::chrono::milliseconds timeout)
    {
        const auto deadline = std::chrono::steady_clock::now() + timeout;
        while (std::chrono::steady_clock::now() < deadline)
        {
            if (std::filesystem::exists(path) && read_text(path).find(needle) != std::string::npos)
                return true;
            std::this_thread::sleep_for(10ms);
        }
        return false;
    }

    void set_environment(const wchar_t* name, const std::wstring& value)
    {
        require(SetEnvironmentVariableW(name, value.empty() ? nullptr : value.c_str()) != FALSE, "environment update failed");
    }

    std::filesystem::path make_case_directory(const std::filesystem::path& root, const wchar_t* name)
    {
        const auto path = root / name;
        std::filesystem::remove_all(path);
        std::filesystem::create_directories(path / L"deps");
        std::filesystem::create_directories(path / L"logs");
        return path;
    }

    void stage_fake_prism(const std::filesystem::path& fake_prism, const std::filesystem::path& case_directory)
    {
        std::filesystem::copy_file(
            fake_prism,
            case_directory / L"deps" / L"prism.dll",
            std::filesystem::copy_options::overwrite_existing);
    }

    HWND create_visible_test_window()
    {
        HWND window = CreateWindowExW(
            0,
            L"STATIC",
            L"AccessXI Prism Worker Test",
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            320,
            200,
            nullptr,
            nullptr,
            GetModuleHandleW(nullptr),
            nullptr);
        require(window != nullptr, "test window creation failed");
        ShowWindow(window, SW_SHOWNOACTIVATE);
        UpdateWindow(window);
        return window;
    }

    void prepare_fake(const std::filesystem::path& log, const wchar_t* backend, bool context_fail, bool first_output_fail)
    {
        set_environment(L"ACCESSXI_FAKE_PRISM_LOG", log.wstring());
        set_environment(L"ACCESSXI_FAKE_PRISM_SUCCESS_BACKEND", backend);
        set_environment(L"ACCESSXI_FAKE_PRISM_CONTEXT_FAIL", context_fail ? L"1" : L"");
        set_environment(L"ACCESSXI_FAKE_PRISM_FAIL_FIRST_OUTPUT", first_output_fail ? L"1" : L"");
    }

    void test_nvda_and_worker_thread(
        const std::filesystem::path& root,
        const std::filesystem::path& fake_prism)
    {
        const auto directory = make_case_directory(root, L"nvda");
        stage_fake_prism(fake_prism, directory);
        const auto fake_log = directory / L"fake.log";
        prepare_fake(fake_log, L"NVDA", false, false);

        Diagnostics diagnostics(directory / L"logs");
        SpeechWorker worker(directory / L"deps", diagnostics, 128, 1s, 20ms);
        require(worker.start(), "NVDA worker should start");
        require(worker.wait_until_ready(2s), "NVDA worker should become ready");
        require(worker.enqueue("native label", true), "NVDA label should enqueue");
        require(wait_for_text(fake_log, "text=native label", 2s), "fake Prism did not receive label");
        worker.stop_for_tests();

        const std::string log = read_text(fake_log);
        require(log.find("create name=NVDA") < log.find("backend-initialize name=NVDA result=ok"), "NVDA create/init order mismatch");
        require(log.find("create name=JAWS") == std::string::npos, "JAWS must not be tried after NVDA succeeds");
        require(log.find("interrupt=1") != std::string::npos, "interrupt flag was not preserved");
        const std::string main_thread = "tid=" + std::to_string(GetCurrentThreadId());
        const size_t output = log.find("output count=1");
        require(output != std::string::npos, "output marker missing");
        require(log.substr(output, log.find('\n', output) - output).find(main_thread) == std::string::npos, "Prism output ran on producer thread");

        const std::string speech_log = read_text(directory / L"logs" / L"pol-native-speech.log");
        require(speech_log.find("native label") == std::string::npos, "production speech diagnostics must not include label text");
    }

    void test_explicit_fallback_order(
        const std::filesystem::path& root,
        const std::filesystem::path& fake_prism)
    {
        const auto directory = make_case_directory(root, L"uia");
        stage_fake_prism(fake_prism, directory);
        const auto fake_log = directory / L"fake.log";
        prepare_fake(fake_log, L"UIA", false, false);
        HWND window = create_visible_test_window();

        Diagnostics diagnostics(directory / L"logs");
        SpeechWorker worker(directory / L"deps", diagnostics, 128, 2s, 1s);
        require(worker.start(), "UIA worker should start");
        require(worker.wait_until_ready(3s), "UIA worker should become ready");
        worker.stop_for_tests();
        DestroyWindow(window);

        const std::string log = read_text(fake_log);
        const size_t nvda = log.find("create name=NVDA");
        const size_t jaws = log.find("create name=JAWS");
        const size_t uia = log.find("create name=UIA");
        require(nvda != std::string::npos && jaws != std::string::npos && uia != std::string::npos, "explicit backend attempts missing");
        require(nvda < jaws && jaws < uia, "backend fallback order must be NVDA, JAWS, UIA");
        require(log.find("create-best") == std::string::npos, "best fallback must not run after UIA succeeds");
    }

    void test_best_fallback(
        const std::filesystem::path& root,
        const std::filesystem::path& fake_prism)
    {
        const auto directory = make_case_directory(root, L"best");
        stage_fake_prism(fake_prism, directory);
        const auto fake_log = directory / L"fake.log";
        prepare_fake(fake_log, L"BEST", false, false);

        Diagnostics diagnostics(directory / L"logs");
        SpeechWorker worker(directory / L"deps", diagnostics, 128, 1s, 10ms);
        require(worker.start(), "best-fallback worker should start");
        require(worker.wait_until_ready(2s), "best fallback should become ready");
        worker.stop_for_tests();

        const std::string log = read_text(fake_log);
        require(log.find("create name=NVDA") < log.find("create name=JAWS"), "NVDA/JAWS order mismatch");
        require(log.find("create-best") != std::string::npos, "best fallback was not attempted");
        require(log.find("backend-initialize name=BEST result=ok") != std::string::npos, "best fallback did not initialize");
    }

    void test_output_failure_retries_once(
        const std::filesystem::path& root,
        const std::filesystem::path& fake_prism)
    {
        const auto directory = make_case_directory(root, L"retry");
        stage_fake_prism(fake_prism, directory);
        const auto fake_log = directory / L"fake.log";
        prepare_fake(fake_log, L"NVDA", false, true);

        Diagnostics diagnostics(directory / L"logs");
        SpeechWorker worker(directory / L"deps", diagnostics, 128, 1s, 20ms);
        require(worker.start(), "retry worker should start");
        require(worker.wait_until_ready(2s), "retry worker should become ready");
        require(worker.enqueue("retry label", false), "retry label should enqueue");
        require(wait_for_text(fake_log, "output count=2", 2s), "failed output was not retried once");
        worker.stop_for_tests();

        const std::string log = read_text(fake_log);
        require(log.find("output count=1 interrupt=0 result=fail") != std::string::npos, "first output did not fail as configured");
        require(log.find("output count=2 interrupt=0 result=ok") != std::string::npos, "second output did not succeed");
        require(log.find("output count=3") == std::string::npos, "output was retried more than once");
    }

    void test_bounded_initialization_failure(
        const std::filesystem::path& root,
        const std::filesystem::path& fake_prism)
    {
        const auto directory = make_case_directory(root, L"failure");
        stage_fake_prism(fake_prism, directory);
        const auto fake_log = directory / L"fake.log";
        prepare_fake(fake_log, L"NONE", true, false);

        Diagnostics diagnostics(directory / L"logs");
        SpeechWorker worker(directory / L"deps", diagnostics, 128, 150ms, 10ms);
        const auto started = std::chrono::steady_clock::now();
        require(worker.start(), "failure worker should schedule");
        require(!worker.wait_until_ready(1s), "context failure must not report ready");
        worker.stop_for_tests();
        require(std::chrono::steady_clock::now() - started < 2s, "initialization failure exceeded bound");
        require(read_text(directory / L"logs" / L"pol-native-startup.log").find("prism-initialize-timeout") != std::string::npos, "bounded failure marker missing");
    }
}

int wmain(int argument_count, wchar_t** arguments)
{
    require(argument_count == 2, "fake Prism path argument is required");
    const std::filesystem::path fake_prism = std::filesystem::absolute(arguments[1]);
    require(std::filesystem::exists(fake_prism), "fake Prism DLL is missing");

    const auto root = std::filesystem::temp_directory_path() /
        (L"accessxi-pol-native-worker-tests-" + std::to_wstring(GetCurrentProcessId()));
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root);

    test_nvda_and_worker_thread(root, fake_prism);
    test_explicit_fallback_order(root, fake_prism);
    test_best_fallback(root, fake_prism);
    test_output_failure_retries_once(root, fake_prism);
    test_bounded_initialization_failure(root, fake_prism);

    std::filesystem::remove_all(root);
    std::cout << "ok: native Prism loading, backend policy, worker ownership, retry, and diagnostics\n";
    return 0;
}
