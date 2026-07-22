#include "pol_native/diagnostics.h"
#include "pol_native/native_host.h"
#include "pol_native/startup_latch.h"

#include <Windows.h>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace
{
    using accessxi::pol_native::Diagnostics;
    using accessxi::pol_native::FileFingerprint;
    using accessxi::pol_native::NativeHost;
    using accessxi::pol_native::NativeHostConfiguration;
    using accessxi::pol_native::NativeHostResult;
    using accessxi::pol_native::StartupLatch;
    using accessxi::pol_native::dependency_directory_from_asi_path;
    using accessxi::pol_native::fingerprint_file;
    using namespace std::chrono_literals;

    struct Artifacts
    {
        std::filesystem::path prism;
        std::filesystem::path hook;
        std::filesystem::path hook_no_sink;
        std::filesystem::path hook_no_init;
        std::filesystem::path installed_app;
    };

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

    void write_fixture(const std::filesystem::path& path, std::string_view bytes)
    {
        std::filesystem::create_directories(path.parent_path());
        std::ofstream output(path, std::ios::binary | std::ios::trunc);
        output.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    }

    std::filesystem::path make_case_directory(const std::filesystem::path& root, const wchar_t* name)
    {
        const auto path = root / name;
        std::filesystem::remove_all(path);
        std::filesystem::create_directories(path / L"AccessXI.PolNative");
        std::filesystem::create_directories(path / L"logs");
        write_fixture(path / L"AccessXI.PolNative.asi", "ASI fixture");
        return path;
    }

    NativeHostConfiguration make_configuration(
        const std::filesystem::path& directory,
        const std::filesystem::path& app_path)
    {
        FileFingerprint fingerprint{};
        require(fingerprint_file(app_path, fingerprint), "app fixture fingerprint failed");
        NativeHostConfiguration configuration{};
        configuration.asi_path_override = directory / L"AccessXI.PolNative.asi";
        configuration.app_path_override = app_path;
        configuration.expected_app_size = fingerprint.size;
        configuration.expected_app_fnv64 = fingerprint.fnv64;
        configuration.show_failure_dialog = false;
        configuration.app_wait_timeout = 100ms;
        configuration.speech_ready_timeout = 2s;
        configuration.speech_initialization_timeout = 1s;
        configuration.window_wait_timeout = 10ms;
        return configuration;
    }

    void stage_dependencies(
        const Artifacts& artifacts,
        const std::filesystem::path& directory,
        const std::filesystem::path& hook)
    {
        const auto dependencies = directory / L"AccessXI.PolNative";
        std::filesystem::copy_file(artifacts.prism, dependencies / L"prism.dll", std::filesystem::copy_options::overwrite_existing);
        std::filesystem::copy_file(hook, dependencies / L"accessxi_pol_native.dll", std::filesystem::copy_options::overwrite_existing);
    }

    void prepare_fake_environment(const std::filesystem::path& directory)
    {
        set_environment(L"ACCESSXI_FAKE_PRISM_LOG", (directory / L"fake-prism.log").wstring());
        set_environment(L"ACCESSXI_FAKE_PRISM_SUCCESS_BACKEND", L"NVDA");
        set_environment(L"ACCESSXI_FAKE_PRISM_CONTEXT_FAIL", L"");
        set_environment(L"ACCESSXI_FAKE_PRISM_FAIL_FIRST_OUTPUT", L"");
        set_environment(L"ACCESSXI_FAKE_HOOK_LOG", (directory / L"fake-hook.log").wstring());
        set_environment(L"ACCESSXI_FAKE_HOOK_INIT_RESULT", L"1");
        set_environment(L"ACCESSXI_FAKE_HOOK_EMIT_TEXT", L"");
        set_environment(L"ACCESSXI_FAKE_HOOK_STRESS_COUNT", L"");
    }

    void test_path_and_fingerprint(const Artifacts& artifacts, const std::filesystem::path& root)
    {
        const auto asi = root / L"path" / L"AccessXI.PolNative.asi";
        require(
            dependency_directory_from_asi_path(asi) == root / L"path" / L"AccessXI.PolNative",
            "dependency directory must derive from ASI path");

        const auto vector_path = root / L"fnv-vector.bin";
        write_fixture(vector_path, "hello");
        FileFingerprint vector{};
        require(fingerprint_file(vector_path, vector), "known-vector fingerprint failed");
        require(vector.size == 5, "known-vector size mismatch");
        require(vector.fnv64 == 0xA430D84680AABD0Bull, "known FNV-1a vector mismatch");

        FileFingerprint installed{};
        require(fingerprint_file(artifacts.installed_app, installed), "installed app.dll fingerprint failed");
        require(installed.size == 4335104ull, "installed app.dll size is not the reviewed build");
        require(installed.fnv64 == 0x07E88E8067FEF6CCull, "installed app.dll FNV is not the reviewed build");
    }

    void test_success_order_and_callback_copy(const Artifacts& artifacts, const std::filesystem::path& root)
    {
        const auto directory = make_case_directory(root, L"success");
        const auto app = directory / L"app-fixture.dll";
        write_fixture(app, "recognized app fixture");
        stage_dependencies(artifacts, directory, artifacts.hook);
        prepare_fake_environment(directory);
        set_environment(L"ACCESSXI_FAKE_HOOK_EMIT_TEXT", L"copied native label");

        Diagnostics diagnostics(directory / L"logs");
        NativeHost host(make_configuration(directory, app), diagnostics);
        require(host.run() == NativeHostResult::ready, "valid host startup should succeed");
        require(wait_for_text(directory / L"fake-prism.log", "text=copied native label", 2s), "sink callback did not preserve copied text");
        host.stop_for_tests();

        const std::string hook_log = read_text(directory / L"fake-hook.log");
        require(hook_log.find("sink-register") < hook_log.find("initialize-v2"), "sink must register before hook initialization");

        const std::string startup = read_text(directory / L"logs" / L"pol-native-startup.log");
        const size_t worker = startup.find("ACCESSXI_POL_NATIVE worker-start");
        const size_t fingerprint = startup.find("ACCESSXI_POL_NATIVE app-fingerprint-ok");
        const size_t prism = startup.find("ACCESSXI_POL_NATIVE prism-ready");
        const size_t sink = startup.find("ACCESSXI_POL_NATIVE speech-sink-registered");
        const size_t initialize = startup.find("ACCESSXI_POL_NATIVE hook-initialize-ok");
        const size_t ready = startup.find("ACCESSXI_POL_NATIVE ready");
        require(worker < fingerprint && fingerprint < prism && prism < sink && sink < initialize && initialize < ready, "startup markers are out of order");
    }

    void test_fingerprint_fails_before_dependencies(const Artifacts& artifacts, const std::filesystem::path& root)
    {
        const auto directory = make_case_directory(root, L"fingerprint-failure");
        const auto app = directory / L"app-fixture.dll";
        write_fixture(app, "wrong app fixture");
        stage_dependencies(artifacts, directory, artifacts.hook);
        prepare_fake_environment(directory);

        auto configuration = make_configuration(directory, app);
        ++configuration.expected_app_fnv64;
        Diagnostics diagnostics(directory / L"logs");
        NativeHost host(configuration, diagnostics);
        require(host.run() == NativeHostResult::unsupported_app, "wrong fingerprint must fail closed");
        host.stop_for_tests();
        require(!std::filesystem::exists(directory / L"fake-prism.log"), "Prism loaded before fingerprint rejection");
        require(!std::filesystem::exists(directory / L"fake-hook.log"), "hook DLL loaded before fingerprint rejection");
    }

    void test_missing_dependencies_and_exports(const Artifacts& artifacts, const std::filesystem::path& root)
    {
        const auto missing_prism = make_case_directory(root, L"missing-prism");
        const auto app = missing_prism / L"app-fixture.dll";
        write_fixture(app, "recognized app fixture");
        std::filesystem::copy_file(artifacts.hook, missing_prism / L"AccessXI.PolNative" / L"accessxi_pol_native.dll");
        prepare_fake_environment(missing_prism);
        Diagnostics missing_prism_diagnostics(missing_prism / L"logs");
        NativeHost missing_prism_host(make_configuration(missing_prism, app), missing_prism_diagnostics);
        require(missing_prism_host.run() == NativeHostResult::speech_unavailable, "missing Prism must fail closed");
        require(missing_prism_host.fatal_notification_count() == 1, "fatal notification must be scheduled once");
        require(missing_prism_host.run() == NativeHostResult::speech_unavailable, "repeated failure result changed");
        require(missing_prism_host.fatal_notification_count() == 1, "fatal notification repeated");
        missing_prism_host.stop_for_tests();

        const auto missing_hook = make_case_directory(root, L"missing-hook");
        const auto missing_hook_app = missing_hook / L"app-fixture.dll";
        write_fixture(missing_hook_app, "recognized app fixture");
        std::filesystem::copy_file(artifacts.prism, missing_hook / L"AccessXI.PolNative" / L"prism.dll");
        prepare_fake_environment(missing_hook);
        Diagnostics missing_hook_diagnostics(missing_hook / L"logs");
        NativeHost missing_hook_host(make_configuration(missing_hook, missing_hook_app), missing_hook_diagnostics);
        require(missing_hook_host.run() == NativeHostResult::hook_unavailable, "missing hook DLL must fail closed");
        missing_hook_host.stop_for_tests();

        for (const auto& entry : std::vector<std::pair<const wchar_t*, std::filesystem::path>>{
                 {L"missing-sink", artifacts.hook_no_sink},
                 {L"missing-init", artifacts.hook_no_init}})
        {
            const auto directory = make_case_directory(root, entry.first);
            const auto case_app = directory / L"app-fixture.dll";
            write_fixture(case_app, "recognized app fixture");
            stage_dependencies(artifacts, directory, entry.second);
            prepare_fake_environment(directory);
            Diagnostics diagnostics(directory / L"logs");
            NativeHost host(make_configuration(directory, case_app), diagnostics);
            require(host.run() == NativeHostResult::hook_abi_mismatch, "missing hook export must fail closed");
            host.stop_for_tests();
        }
    }

    void test_rejected_initializer_and_bounded_stress(const Artifacts& artifacts, const std::filesystem::path& root)
    {
        const auto rejected = make_case_directory(root, L"init-rejected");
        const auto rejected_app = rejected / L"app-fixture.dll";
        write_fixture(rejected_app, "recognized app fixture");
        stage_dependencies(artifacts, rejected, artifacts.hook);
        prepare_fake_environment(rejected);
        set_environment(L"ACCESSXI_FAKE_HOOK_INIT_RESULT", L"-2");
        Diagnostics rejected_diagnostics(rejected / L"logs");
        NativeHost rejected_host(make_configuration(rejected, rejected_app), rejected_diagnostics);
        require(rejected_host.run() == NativeHostResult::hook_initialize_failed, "rejected V2 result must fail startup");
        rejected_host.stop_for_tests();

        const auto stress = make_case_directory(root, L"stress");
        const auto stress_app = stress / L"app-fixture.dll";
        write_fixture(stress_app, "recognized app fixture");
        stage_dependencies(artifacts, stress, artifacts.hook);
        prepare_fake_environment(stress);
        set_environment(L"ACCESSXI_FAKE_HOOK_STRESS_COUNT", L"1000");
        Diagnostics stress_diagnostics(stress / L"logs");
        NativeHost stress_host(make_configuration(stress, stress_app), stress_diagnostics);
        require(stress_host.run() == NativeHostResult::ready, "stress host startup failed");
        require(wait_for_text(stress / L"fake-prism.log", "text=stress-999", 5s), "newest stress focus was not retained");
        require(stress_host.speech_stats().dropped > 0, "stress burst did not exercise bounded dropping");
        stress_host.stop_for_tests();
    }

    void test_startup_latch()
    {
        StartupLatch latch;
        std::atomic<int> winners{0};
        std::vector<std::thread> threads;
        for (int index = 0; index < 32; ++index)
        {
            threads.emplace_back([&] {
                if (latch.try_start())
                    winners.fetch_add(1, std::memory_order_relaxed);
            });
        }
        for (auto& thread : threads)
            thread.join();
        require(winners.load(std::memory_order_relaxed) == 1, "startup latch must allow exactly one worker");
        require(!latch.try_start(), "startup latch reopened after first worker");
    }
}

int wmain(int argument_count, wchar_t** arguments)
{
    require(argument_count == 6, "five artifact paths are required");
    Artifacts artifacts{
        std::filesystem::absolute(arguments[1]),
        std::filesystem::absolute(arguments[2]),
        std::filesystem::absolute(arguments[3]),
        std::filesystem::absolute(arguments[4]),
        std::filesystem::absolute(arguments[5])};
    require(std::filesystem::exists(artifacts.prism), "fake Prism artifact missing");
    require(std::filesystem::exists(artifacts.hook), "fake hook artifact missing");
    require(std::filesystem::exists(artifacts.hook_no_sink), "fake no-sink artifact missing");
    require(std::filesystem::exists(artifacts.hook_no_init), "fake no-init artifact missing");
    require(std::filesystem::exists(artifacts.installed_app), "installed app.dll missing");

    const auto root = std::filesystem::temp_directory_path() /
        (L"accessxi-pol-native-host-tests-" + std::to_wstring(GetCurrentProcessId()));
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root);

    test_path_and_fingerprint(artifacts, root);
    test_success_order_and_callback_copy(artifacts, root);
    test_fingerprint_fails_before_dependencies(artifacts, root);
    test_missing_dependencies_and_exports(artifacts, root);
    test_rejected_initializer_and_bounded_stress(artifacts, root);
    test_startup_latch();

    std::filesystem::remove_all(root);
    std::cout << "ok: native host paths, fingerprint, ABI ordering, failures, callback, bounds, and latch\n";
    return 0;
}
