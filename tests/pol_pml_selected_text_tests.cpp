#include "pol_pml/native_selected_text.h"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
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

        void write_utf16(uintptr_t address, const std::u16string& value, bool terminate = true)
        {
            for (size_t index = 0; index < value.size(); ++index)
                write<uint16_t>(address + index * 2, static_cast<uint16_t>(value[index]));
            if (terminate)
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

    constexpr uintptr_t AppBase = 0x04000000;
    constexpr uintptr_t Sheet = 0x10000000;
    constexpr uintptr_t Image = 0x10001000;
    constexpr uintptr_t Text = 0x10002000;
    constexpr uintptr_t Text2 = 0x10003000;
    constexpr uintptr_t Children = 0x20000000;
    constexpr uintptr_t Model = 0x30000000;
    constexpr uintptr_t Stream = 0x40000000;

    void write_literal_stream(FakeMemory& memory, uintptr_t stream, const std::u16string& text)
    {
        const uint16_t record_size = static_cast<uint16_t>(4 + (text.size() + 1) * 2);
        memory.write<uint16_t>(stream, 0);
        memory.write<uint16_t>(stream + 2, record_size);
        memory.write_utf16(stream + 4, text);
        memory.write<uint16_t>(stream + record_size, 0x29);
        memory.write<uint16_t>(stream + record_size + 2, 4);
    }

    void write_text_child(FakeMemory& memory, uintptr_t object, uintptr_t model, uintptr_t stream, const std::u16string& text)
    {
        memory.write<uintptr_t>(object, AppBase + CpmlTextVtableRva);
        memory.write<uintptr_t>(object + 0x244, model);
        memory.write<uintptr_t>(model + 4, stream);
        write_literal_stream(memory, stream, text);
    }

    FakeMemory valid_sheet(const std::u16string& text)
    {
        FakeMemory memory;
        memory.write<uintptr_t>(Sheet, AppBase + CpmlSheetVtableRva);
        memory.write<uintptr_t>(Sheet + 0x18C, Children);
        memory.write<uintptr_t>(Sheet + 0x190, Children + 2 * sizeof(uintptr_t));
        memory.write<uintptr_t>(Children, Image);
        memory.write<uintptr_t>(Children + sizeof(uintptr_t), Text);
        memory.write<uintptr_t>(Image, AppBase + CpmlImageVtableRva);
        write_text_child(memory, Text, Model, Stream, text);
        return memory;
    }

    void test_selected_sheet_reads_unique_literal_text_sibling()
    {
        auto memory = valid_sheet(u"Options");
        require(read_selected_control_text(memory.view(), Sheet, AppBase) == u"Options",
            "selected CPmlSheet did not resolve its CPmlText sibling");
    }

    void test_duplicate_text_siblings_are_safe_but_conflicts_are_silent()
    {
        auto memory = valid_sheet(u"Friend List");
        memory.write<uintptr_t>(Sheet + 0x190, Children + 3 * sizeof(uintptr_t));
        memory.write<uintptr_t>(Children + 2 * sizeof(uintptr_t), Text2);
        write_text_child(memory, Text2, Model + 0x1000, Stream + 0x1000, u"Friend List");
        require(read_selected_control_text(memory.view(), Sheet, AppBase) == u"Friend List",
            "duplicate rendering text should collapse to one visible label");

        write_literal_stream(memory, Stream + 0x1000, u"Quick Manuals");
        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "conflicting CPmlText siblings must stay silent");
    }

    void test_sheet_requires_image_selection_shape_and_literal_only_stream()
    {
        auto memory = valid_sheet(u"Mail");
        memory.write<uintptr_t>(Image, AppBase + CpmlTextVtableRva);
        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "sheet without its captured CPmlImage selection child must stay silent");

        memory = valid_sheet(u"Mail");
        memory.write<uint16_t>(Stream, 1);
        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "dynamic or formatting token streams must not be partially spoken");
    }

    void test_sheet_rejects_unbounded_or_unterminated_native_data()
    {
        auto memory = valid_sheet(u"Chat");
        memory.write<uintptr_t>(Sheet + 0x190, Children + 65 * sizeof(uintptr_t));
        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "oversized child vectors must be rejected");

        memory = valid_sheet(u"Chat");
        const uint16_t record_size = 4 + 4 * 2;
        memory.write<uint16_t>(Stream, 0);
        memory.write<uint16_t>(Stream + 2, record_size);
        memory.write_utf16(Stream + 4, u"Chat", false);
        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "unterminated literal token must be rejected");
    }

    void test_sheet_rejects_wrapped_object_fields()
    {
        FakeMemory memory;
        const uintptr_t wrapped_sheet = std::numeric_limits<uintptr_t>::max() - 0x100u;
        memory.write<uintptr_t>(wrapped_sheet, AppBase + CpmlSheetVtableRva);
        memory.write<uintptr_t>(wrapped_sheet + 0x18C, Children);
        memory.write<uintptr_t>(wrapped_sheet + 0x190, Children + 2 * sizeof(uintptr_t));
        memory.write<uintptr_t>(Children, Image);
        memory.write<uintptr_t>(Children + sizeof(uintptr_t), Text);
        memory.write<uintptr_t>(Image, AppBase + CpmlImageVtableRva);
        write_text_child(memory, Text, Model, Stream, u"Wrapped");

        require(read_selected_control_text(memory.view(), wrapped_sheet, AppBase).empty(),
            "overflowed native object fields must not wrap into unrelated memory");
    }

    void test_cbutton_reads_ghidra_proven_label_buffer()
    {
        FakeMemory memory;
        constexpr uintptr_t button = 0x50000000;
        constexpr uintptr_t buffer = 0x60000000;
        const std::u16string label = u"Friend Search";
        memory.write<uintptr_t>(button, AppBase + CButtonVtableRva);
        memory.write<uintptr_t>(button + 0x184, buffer);
        memory.write<uintptr_t>(button + 0x188, buffer + (label.size() + 1) * 2);
        memory.write<int16_t>(button + 0x21A, static_cast<int16_t>(label.size()));
        memory.write_utf16(buffer, label);

        require(read_selected_control_text(memory.view(), button, AppBase) == label,
            "CButton visible label buffer was not decoded");

        memory.write<uintptr_t>(button + 0x188, buffer + 2);
        require(read_selected_control_text(memory.view(), button, AppBase).empty(),
            "CButton length beyond its native buffer must be rejected");
    }

    void test_sheet_focus_coalescing_preserves_only_captured_nested_chain()
    {
        constexpr uintptr_t row = 0x70000000;
        constexpr uintptr_t image = 0x70001000;
        constexpr uintptr_t unrelated = 0x70002000;

        require(classify_sheet_focus_event(false, row, 0, false, row, image) ==
                SheetFocusEventDisposition::replace,
            "an event without a pending selected row must replace the snapshot");
        require(classify_sheet_focus_event(true, row, 0, true, row, image) ==
                SheetFocusEventDisposition::replace,
            "a newly selected sheet row must replace the older row");
        require(classify_sheet_focus_event(true, row, 0, false, row, image) ==
                SheetFocusEventDisposition::capture_nested_child,
            "the captured row-to-image event must preserve the selected row");
        require(classify_sheet_focus_event(true, row, image, false, image, image) ==
                SheetFocusEventDisposition::preserve,
            "the captured image self-focus event must preserve the selected row");
        require(classify_sheet_focus_event(true, row, image, false, image, unrelated) ==
                SheetFocusEventDisposition::replace,
            "a different descendant event must not be inferred as selected-row proof");
        require(classify_sheet_focus_event(true, row, image, false, unrelated, unrelated) ==
                SheetFocusEventDisposition::replace,
            "an unrelated control must replace the selected-row snapshot");
    }
}

int main()
{
    test_selected_sheet_reads_unique_literal_text_sibling();
    test_duplicate_text_siblings_are_safe_but_conflicts_are_silent();
    test_sheet_requires_image_selection_shape_and_literal_only_stream();
    test_sheet_rejects_unbounded_or_unterminated_native_data();
    test_sheet_rejects_wrapped_object_fields();
    test_cbutton_reads_ghidra_proven_label_buffer();
    test_sheet_focus_coalescing_preserves_only_captured_nested_chain();
    std::cout << "ok: selected PlayOnline controls require bounded native text and unambiguous hierarchy\n";
    return 0;
}
