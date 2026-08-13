#include "pol_pml/native_update_progress.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <unordered_map>

namespace
{
    using namespace accessxi::pol_pml;

    void require(bool condition, const char* message)
    {
        if (!condition)
        {
            std::cerr << "FAIL: " << message << '\n';
            std::exit(1);
        }
    }

    struct FakeMemory
    {
        std::unordered_map<uintptr_t, uint8_t> bytes;

        template<typename T>
        void write(uintptr_t address, const T& value)
        {
            const auto* source = reinterpret_cast<const uint8_t*>(&value);
            for (size_t index = 0; index < sizeof(T); ++index)
                bytes[address + index] = source[index];
        }

        void write_utf16(uintptr_t address, const std::u16string& value)
        {
            for (size_t index = 0; index < value.size(); ++index)
                write<uint16_t>(address + index * 2, static_cast<uint16_t>(value[index]));
            write<uint16_t>(address + value.size() * 2, 0);
        }

        static bool read(void* context, uintptr_t address, void* output, size_t size) noexcept
        {
            auto* memory = static_cast<FakeMemory*>(context);
            auto* destination = static_cast<uint8_t*>(output);
            for (size_t index = 0; index < size; ++index)
            {
                const auto found = memory->bytes.find(address + index);
                if (found == memory->bytes.end())
                    return false;
                destination[index] = found->second;
            }
            return true;
        }

        MemoryView view()
        {
            return MemoryView{ &FakeMemory::read, this };
        }
    };

    constexpr uintptr_t AppBase = 0x04000000u;
    constexpr uintptr_t Owner = 0x10000000u;
    constexpr uintptr_t LabelBase = 0x11000000u;
    constexpr uintptr_t TextBase = 0x12000000u;

    constexpr std::array<uint32_t, UpdateProgressFieldCount> OwnerSlots{
        0x2ACu, 0x2B0u, 0x2B4u, 0x2B8u, 0x2BCu, 0x2C0u,
        0x2C4u, 0x2C8u, 0x2CCu, 0x2D0u
    };

    void write_visible_component(FakeMemory& memory, uintptr_t object)
    {
        memory.write<uint8_t>(object + 0x18, 0x0Cu);
    }

    void write_label(
        FakeMemory& memory,
        size_t index,
        const std::u16string& text)
    {
        const uintptr_t label = LabelBase + index * 0x1000u;
        const uintptr_t characters = TextBase + index * 0x1000u;
        memory.write<uintptr_t>(Owner + OwnerSlots[index], label);
        memory.write<uintptr_t>(label, AppBase + CLabelVtableRva);
        write_visible_component(memory, label);
        memory.write<uintptr_t>(label + 0x184, characters);
        memory.write<uintptr_t>(
            label + 0x188,
            characters + (text.size() + 1) * sizeof(char16_t));
        memory.write<int16_t>(label + 0x21A, static_cast<int16_t>(text.size()));
        memory.write_utf16(characters, text);
    }

    FakeMemory make_progress_memory()
    {
        FakeMemory memory;
        memory.write<uintptr_t>(Owner, AppBase + UpgradeProgressWindowVtableRva);
        write_visible_component(memory, Owner);
        for (size_t index = 0; index < OwnerSlots.size(); ++index)
            memory.write<uintptr_t>(Owner + OwnerSlots[index], 0);
        write_label(memory, static_cast<size_t>(UpdateProgressField::stage), u"Downloading");
        write_label(memory, static_cast<size_t>(UpdateProgressField::time_remaining), u"Time remaining 22:49");
        write_label(memory, static_cast<size_t>(UpdateProgressField::current_status), u"Current file ROM/0/1.DAT");
        write_label(memory, static_cast<size_t>(UpdateProgressField::overall_percent), u"Overall 1%");
        write_label(memory, static_cast<size_t>(UpdateProgressField::title), u"Updating FINAL FANTASY XI");
        write_label(memory, static_cast<size_t>(UpdateProgressField::files_remaining), u"194 files remaining");
        write_label(memory, static_cast<size_t>(UpdateProgressField::current_file), u"Current file ROM/0/1.DAT");
        write_label(memory, static_cast<size_t>(UpdateProgressField::current_file_percent), u"Current file 30%");
        return memory;
    }

    void replace_label_text(
        FakeMemory& memory,
        UpdateProgressField field,
        const std::u16string& text)
    {
        write_label(memory, static_cast<size_t>(field), text);
    }

    void test_inspector_reads_only_the_exact_visible_upgrade_window()
    {
        auto memory = make_progress_memory();
        const auto snapshot = inspect_update_progress(memory.view(), Owner, AppBase);
        require(snapshot.state == UpdateProgressInspectionState::present,
            "exact Upgrade_ProgressWnd was not recognized");
        require(snapshot.fields[static_cast<size_t>(UpdateProgressField::title)] ==
                u"Updating FINAL FANTASY XI",
            "native update title did not survive");
        require(snapshot.fields[static_cast<size_t>(UpdateProgressField::overall_percent)] ==
                u"Overall 1%",
            "native overall percentage did not survive");
        require(snapshot.fields[static_cast<size_t>(UpdateProgressField::time_remaining)] ==
                u"Time remaining 22:49",
            "native remaining time did not survive");

        memory.write<uintptr_t>(Owner, AppBase + UpgradeProgressWindowVtableRva + 4);
        require(inspect_update_progress(memory.view(), Owner, AppBase).state ==
                UpdateProgressInspectionState::absent,
            "another native window was accepted as update progress");

        memory.write<uintptr_t>(Owner, AppBase + UpgradeProgressWindowVtableRva);
        memory.write<uint8_t>(Owner + 0x18, 0);
        require(inspect_update_progress(memory.view(), Owner, AppBase).state ==
                UpdateProgressInspectionState::absent,
            "a hidden update window remained active");

        write_visible_component(memory, Owner);
        const size_t title = static_cast<size_t>(UpdateProgressField::title);
        memory.write<uintptr_t>(LabelBase + title * 0x1000u, AppBase + CLabelVtableRva + 4);
        require(inspect_update_progress(memory.view(), Owner, AppBase).state ==
                UpdateProgressInspectionState::unknown,
            "a changed native label layout was trusted");
    }

    void test_tracker_announces_entry_milestones_heartbeat_and_completion_without_file_spam()
    {
        auto memory = make_progress_memory();
        UpdateProgressTracker tracker;
        auto snapshot = inspect_update_progress(memory.view(), Owner, AppBase);

        require(tracker.observe(snapshot, 100).mode == UpdateProgressSpeechMode::none,
            "one unstable update read was spoken");
        const auto entered = tracker.observe(snapshot, 120);
        require(entered.mode == UpdateProgressSpeechMode::interrupt,
            "stable update entry was not announced");
        require(entered.text ==
                u"Version update. Updating FINAL FANTASY XI. Downloading. Overall 1%. 194 files remaining. Current file ROM/0/1.DAT. Current file 30%. Time remaining 22:49",
            "initial update summary did not use the native fields in reading order");

        replace_label_text(memory, UpdateProgressField::current_file, u"Current file ROM/0/2.DAT");
        replace_label_text(memory, UpdateProgressField::current_status, u"Current file ROM/0/2.DAT");
        replace_label_text(memory, UpdateProgressField::current_file_percent, u"Current file 1%");
        snapshot = inspect_update_progress(memory.view(), Owner, AppBase);
        tracker.observe(snapshot, 200);
        require(tracker.observe(snapshot, 220).mode == UpdateProgressSpeechMode::none,
            "every current-file change was spoken");

        replace_label_text(memory, UpdateProgressField::overall_percent, u"Overall 7%");
        snapshot = inspect_update_progress(memory.view(), Owner, AppBase);
        tracker.observe(snapshot, 1000);
        require(tracker.observe(snapshot, 1020).mode == UpdateProgressSpeechMode::none,
            "progress ignored the five-second speech floor");
        const auto milestone = tracker.observe(snapshot, 5200);
        require(milestone.mode == UpdateProgressSpeechMode::queued,
            "a five-percent progress milestone was not announced");
        require(milestone.text ==
                u"Version update. Overall 7%. 194 files remaining. Time remaining 22:49",
            "milestone speech included noisy current-file changes");

        replace_label_text(memory, UpdateProgressField::current_file, u"Current file ROM/0/3.DAT");
        snapshot = inspect_update_progress(memory.view(), Owner, AppBase);
        tracker.observe(snapshot, 6000);
        require(tracker.observe(snapshot, 6020).mode == UpdateProgressSpeechMode::none,
            "a file-only change bypassed rate limiting");
        const auto heartbeat = tracker.observe(snapshot, 65200);
        require(heartbeat.mode == UpdateProgressSpeechMode::queued,
            "a long-running unchanged milestone had no one-minute status");

        replace_label_text(memory, UpdateProgressField::overall_percent, u"Overall 100%");
        snapshot = inspect_update_progress(memory.view(), Owner, AppBase);
        tracker.observe(snapshot, 65300);
        const auto complete = tracker.observe(snapshot, 65320);
        require(complete.mode == UpdateProgressSpeechMode::interrupt,
            "100 percent completion did not bypass the routine speech floor");
        require(complete.text.find(u"Overall 100%") != std::u16string::npos,
            "completion speech omitted the native 100 percent value");
    }

    void test_tracker_announces_phase_changes_and_resets_after_window_closes()
    {
        auto memory = make_progress_memory();
        UpdateProgressTracker tracker;
        auto snapshot = inspect_update_progress(memory.view(), Owner, AppBase);
        tracker.observe(snapshot, 100);
        tracker.observe(snapshot, 120);

        replace_label_text(memory, UpdateProgressField::stage, u"Installing files");
        snapshot = inspect_update_progress(memory.view(), Owner, AppBase);
        tracker.observe(snapshot, 200);
        const auto phase = tracker.observe(snapshot, 220);
        require(phase.mode == UpdateProgressSpeechMode::interrupt,
            "a native update phase change was not announced immediately");
        require(phase.text.find(u"Installing files") != std::u16string::npos,
            "phase announcement omitted the new native stage");

        UpdateProgressSnapshot closed;
        closed.state = UpdateProgressInspectionState::absent;
        tracker.observe(closed, 300);
        tracker.observe(snapshot, 400);
        require(tracker.observe(snapshot, 420).mode == UpdateProgressSpeechMode::interrupt,
            "reopening the progress window did not announce a fresh entry");
    }
}

int main()
{
    test_inspector_reads_only_the_exact_visible_upgrade_window();
    test_tracker_announces_entry_milestones_heartbeat_and_completion_without_file_spam();
    test_tracker_announces_phase_changes_and_resets_after_window_closes();
    std::cout << "ok: native PlayOnline update progress inspection and speech policy\n";
    return 0;
}
