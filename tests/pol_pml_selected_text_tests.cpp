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
    constexpr uintptr_t RenderedLine = 0x50000000;
    constexpr uintptr_t RenderedLineHead = 0x50001000;
    constexpr uintptr_t RenderedLineNode = 0x50002000;
    constexpr uintptr_t RenderedFragmentHead = 0x50003000;
    constexpr uintptr_t RenderedFragmentNode = 0x50004000;
    constexpr uintptr_t RenderedFragment = 0x50005000;
    constexpr uintptr_t RenderedCharacters = 0x50006000;
    constexpr uintptr_t ImageAltHeap = 0x50007000;
    constexpr uintptr_t ImageAlternateAltHeap = 0x50008000;
    constexpr uintptr_t LinkedLabelObject = 0x50009000;
    constexpr uintptr_t Pulldown = 0x5000A000;
    constexpr uintptr_t ComboBoxList = 0x5000B000;
    constexpr uintptr_t List = 0x5000C000;
    constexpr uintptr_t SelectionModel = 0x5000D000;
    constexpr uintptr_t RenderedTextFragmentVtableRva = 0x003E4A1C;

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

    void write_single_rendered_text_line(
        FakeMemory& memory,
        uintptr_t text_object,
        const std::u16string& text)
    {
        memory.write<uintptr_t>(text_object + 0x1D0, RenderedLineHead);
        memory.write<uint32_t>(text_object + 0x1D4, 1);
        memory.write<uintptr_t>(RenderedLineHead, RenderedLineNode);
        memory.write<uintptr_t>(RenderedLineHead + 4, RenderedLineNode);
        memory.write<uintptr_t>(RenderedLineNode, RenderedLineHead);
        memory.write<uintptr_t>(RenderedLineNode + 4, RenderedLineHead);
        memory.write<uintptr_t>(RenderedLineNode + 8, RenderedLine);

        memory.write<uintptr_t>(RenderedLine + 0x24, RenderedFragmentHead);
        memory.write<uint32_t>(RenderedLine + 0x28, 1);
        memory.write<uintptr_t>(RenderedFragmentHead, RenderedFragmentNode);
        memory.write<uintptr_t>(RenderedFragmentHead + 4, RenderedFragmentNode);
        memory.write<uintptr_t>(RenderedFragmentNode, RenderedFragmentHead);
        memory.write<uintptr_t>(RenderedFragmentNode + 4, RenderedFragmentHead);
        memory.write<uintptr_t>(RenderedFragmentNode + 8, RenderedFragment);

        memory.write<uintptr_t>(RenderedFragment, AppBase + RenderedTextFragmentVtableRva);
        memory.write<uintptr_t>(RenderedFragment + 0x28, RenderedCharacters);
        memory.write<uint32_t>(RenderedFragment + 0x2C, static_cast<uint32_t>(text.size()));
        memory.write_utf16(RenderedCharacters, text, false);
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

    void write_native_wide_string(
        FakeMemory& memory,
        uintptr_t field,
        uintptr_t heap,
        const std::u16string& text)
    {
        const uint32_t capacity = text.size() < 8 ? 7u : static_cast<uint32_t>(text.size());
        if (capacity < 8)
            memory.write_utf16(field, text);
        else
        {
            memory.write<uintptr_t>(field, heap);
            memory.write_utf16(heap, text);
        }
        memory.write<uint32_t>(field + 0x10, static_cast<uint32_t>(text.size()));
        memory.write<uint32_t>(field + 0x14, capacity);
    }

    void test_selected_sheet_reads_unique_literal_text_sibling()
    {
        auto memory = valid_sheet(u"Options");
        require(read_selected_control_text(memory.view(), Sheet, AppBase) == u"Options",
            "selected CPmlSheet did not resolve its CPmlText sibling");
    }

    void test_selected_sheet_reads_live_rendered_dynamic_text()
    {
        auto memory = valid_sheet(u"unresolved source token");
        memory.write<uint16_t>(Stream, 0x10);
        write_single_rendered_text_line(memory, Text, u"Games");

        require(read_selected_control_text(memory.view(), Sheet, AppBase) == u"Games",
            "selected CPmlSheet did not resolve its live rendered dynamic caption");
    }

    void test_rendered_dynamic_text_rejects_unproven_or_inconsistent_state()
    {
        auto memory = valid_sheet(u"unresolved source token");
        memory.write<uint16_t>(Stream, 0x10);
        write_single_rendered_text_line(memory, Text, u"Games");
        memory.write<uintptr_t>(RenderedFragment, AppBase + CpmlImageVtableRva);
        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "a non-text rendered fragment must stay silent");

        memory = valid_sheet(u"unresolved source token");
        memory.write<uint16_t>(Stream, 0x10);
        write_single_rendered_text_line(memory, Text, u"Games");
        memory.write<uintptr_t>(RenderedLineNode, RenderedLineNode);
        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "an inconsistent native rendered-line list must stay silent");

        memory = valid_sheet(u"unresolved source token");
        memory.write<uint16_t>(Stream, 0x10);
        write_single_rendered_text_line(memory, Text, u"Games");
        memory.write<uint16_t>(RenderedCharacters + 2, 0);
        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "rendered text containing an embedded null must stay silent");
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

    void test_selected_image_reads_only_ghidra_proven_native_alt_field()
    {
        FakeMemory memory;
        memory.write<uintptr_t>(Image, AppBase + CpmlImageVtableRva);
        write_native_wide_string(memory, Image + 0x11C, ImageAltHeap, u"Games");

        require(read_selected_control_text(memory.view(), Image, AppBase) == u"Games",
            "selected CPmlImage did not resolve its native alt property");

        memory.write<uint16_t>(Image + 0x11C + 2, 0);
        require(read_selected_control_text(memory.view(), Image, AppBase).empty(),
            "CPmlImage alt text containing an embedded null must stay silent");
    }

    void test_image_only_sheet_requires_exact_captured_nested_image()
    {
        FakeMemory memory;
        memory.write<uintptr_t>(Sheet, AppBase + CpmlSheetVtableRva);
        memory.write<uintptr_t>(Sheet + 0x18C, Children);
        memory.write<uintptr_t>(Sheet + 0x190, Children + sizeof(uintptr_t));
        memory.write<uintptr_t>(Children, Image);
        memory.write<uintptr_t>(Image, AppBase + CpmlImageVtableRva);
        write_native_wide_string(memory, Image + 0x11C, ImageAltHeap, u"Information");

        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "an image-only sheet without nested selection proof must stay silent");
        require(read_selected_control_text(memory.view(), Sheet, AppBase, Image) == u"Information",
            "captured image-only sheet did not resolve its selected image alt property");
        require(read_selected_control_text(memory.view(), Sheet, AppBase, Text).empty(),
            "an unrelated nested object must not label an image-only sheet");
    }

    void test_selected_image_inspection_exposes_only_the_proven_label_path()
    {
        FakeMemory memory;
        memory.write<uintptr_t>(Sheet, AppBase + CpmlSheetVtableRva);
        memory.write<uintptr_t>(Sheet + 0x18C, Children);
        memory.write<uintptr_t>(Sheet + 0x190, Children + 2 * sizeof(uintptr_t));
        memory.write<uintptr_t>(Children, Image);
        memory.write<uintptr_t>(Children + sizeof(uintptr_t), Text);
        memory.write<uintptr_t>(Image, AppBase + CpmlImageVtableRva);
        memory.write<uintptr_t>(Text, AppBase + CpmlTextVtableRva);
        memory.write<uintptr_t>(Image + 0x154, LinkedLabelObject);
        memory.write<uintptr_t>(LinkedLabelObject, AppBase + CpmlSheetVtableRva);
        write_native_wide_string(memory, Image + 0x11C, ImageAltHeap, u"Primary caption");
        write_native_wide_string(memory, Image + 0x138, ImageAlternateAltHeap, u"Alternate caption");

        const auto inspection = inspect_selected_image_path(
            memory.view(),
            Sheet,
            AppBase,
            Image);
        require(inspection.matched,
            "the exact captured sheet-to-image selection was not inspected");
        require(inspection.object_is_sheet && inspection.nested_is_direct_child,
            "sheet and direct-child relationship were not preserved in the inspection");
        require(inspection.child_count == 2 && inspection.image_child_count == 1 &&
                inspection.text_child_count == 1 && inspection.other_child_count == 0,
            "the inspection did not report the exact direct-child shape");
        require(inspection.image == Image && inspection.image_vtable_rva == CpmlImageVtableRva,
            "the inspection did not identify the selected CPmlImage");
        require(inspection.primary_capacity_130 == std::u16string(u"Primary caption").size() &&
                inspection.alternate_capacity_14c == std::u16string(u"Alternate caption").size(),
            "the inspection did not retain the Ghidra-proven image string capacities");
        require(inspection.linked_label_object == LinkedLabelObject &&
                inspection.linked_label_vtable_rva == CpmlSheetVtableRva,
            "the inspection did not expose the inherited native label object");
        require(inspection.primary_alt == u"Primary caption" &&
                inspection.alternate_alt == u"Alternate caption",
            "the inspection did not report both native image caption fields");

        const auto unrelated = inspect_selected_image_path(
            memory.view(),
            Sheet,
            AppBase,
            LinkedLabelObject);
        require(!unrelated.matched,
            "an unrelated nested object must not be reported as the selected image");
    }

    void test_native_image_getter_caption_requires_agreement_and_removes_pml_marker()
    {
        require(choose_selected_image_getter_caption(
                    "$View the ten latest articles.",
                    "$View the ten latest articles.") ==
                "View the ten latest articles.",
            "an agreeing native image caption did not remove its leading PML control marker");
        require(choose_selected_image_getter_caption(
                    "Visit the official forums!",
                    "Visit the official forums!") ==
                "Visit the official forums!",
            "an agreeing native image caption without a control marker was changed");
        require(choose_selected_image_getter_caption(
                    "Read the latest topics!",
                    "Visit the official site!").empty(),
            "conflicting native image getter states must stay silent");
        require(choose_selected_image_getter_caption("", "").empty(),
            "empty native image getter states must stay silent");
        require(choose_selected_image_getter_caption("$", "$").empty(),
            "a bare PML control marker must stay silent");
    }

    void test_native_image_getter_text_reads_long_caption_with_existing_bound()
    {
        FakeMemory memory;
        const std::u16string banner_caption(85, u'B');
        require(banner_caption.size() == 85,
            "the regression fixture must match the live banner's native length");
        memory.write_utf16(ImageAltHeap, banner_caption);

        require(read_bounded_native_image_getter_text(memory.view(), ImageAltHeap) == banner_caption,
            "the native image getter reader truncated a valid 85-character banner caption");

        const std::u16string oversized_caption(121, u'X');
        memory.write_utf16(ImageAlternateAltHeap, oversized_caption);
        require(read_bounded_native_image_getter_text(memory.view(), ImageAlternateAltHeap).empty(),
            "a native image caption beyond the existing 120-character safety bound must stay silent");
    }

    void test_native_image_getter_caption_filter_allows_the_captured_banner_safely()
    {
        const std::string banner_caption =
            "The Adventuring Primer for all adventurers returning to Vana'diel is now available!";
        require(banner_caption.size() == 83,
            "the caption fixture must match the native banner text captured from PlayOnline");
        require(selected_image_getter_caption_allowed(banner_caption),
            "the exact 83-character native banner caption was rejected");
        require(!selected_image_getter_caption_allowed(std::string(121, 'X')),
            "a native image caption beyond 120 characters must stay silent");
        require(!selected_image_getter_caption_allowed("https://example.invalid/banner"),
            "a native image getter URL must never be spoken as a caption");
        require(!selected_image_getter_caption_allowed("main/index.pml"),
            "a native image getter resource path must never be spoken as a caption");
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

    void test_form_select_editor_reads_only_its_exact_native_value()
    {
        FakeMemory memory;
        write_text_child(memory, Text, Model, Stream, u"Save");
        memory.write<uintptr_t>(Text, AppBase + CpmlFormSelectEditorVtableRva);

        require(read_selected_control_text(memory.view(), Text, AppBase) == u"Save",
            "the exact CPmlFormSelectEditor did not expose its visible selected value");

        memory.write<uintptr_t>(Text, AppBase + CpmlFormSelectEditorVtableRva + 4);
        require(read_selected_control_text(memory.view(), Text, AppBase).empty(),
            "an unverified CPmlText-derived object was treated as a form select editor");

        memory.write<uintptr_t>(Text, AppBase + CpmlFormSelectEditorVtableRva);
        memory.write<uint16_t>(Stream, 0x10);
        require(read_selected_control_text(memory.view(), Text, AppBase).empty(),
            "an unresolved dynamic select value was guessed from its token stream");
    }

    void test_native_pulldown_reads_only_its_exact_selected_index()
    {
        FakeMemory memory;
        memory.write<uintptr_t>(
            Pulldown,
            AppBase + CPulldownVtableRva);
        memory.write<uintptr_t>(
            Pulldown + NativePulldownListOffset,
            List);
        memory.write<uintptr_t>(
            Pulldown + NativePulldownComboBoxListOffset,
            ComboBoxList);
        memory.write<uintptr_t>(
            ComboBoxList,
            AppBase + CComboBoxListVtableRva);
        memory.write<uintptr_t>(
            ComboBoxList + NativeComboBoxListOwnedListOffset,
            List);
        memory.write<uintptr_t>(
            List,
            AppBase + CListVtableRva);
        memory.write<uintptr_t>(
            List + NativeListSelectionModelOffset,
            SelectionModel);

        const uintptr_t selection_vtable =
            AppBase + CDefaultListSelectionModelVtableRva;
        memory.write<uintptr_t>(SelectionModel, selection_vtable);
        memory.write<uintptr_t>(
            selection_vtable + NativeListSelectionMaximumSlotOffset,
            AppBase + NativeListSelectionMaximumGetterRva);
        memory.write<uintptr_t>(
            selection_vtable + NativeListSelectionMinimumSlotOffset,
            AppBase + NativeListSelectionMinimumGetterRva);
        memory.write<int32_t>(
            SelectionModel + NativeListSelectionFirstIndexOffset,
            1);
        memory.write<int32_t>(
            SelectionModel + NativeListSelectionLastIndexOffset,
            1);

        auto snapshot = read_native_pulldown_selection(
            memory.view(),
            Pulldown,
            AppBase);
        require(snapshot.matched && snapshot.selected_index == 1,
            "the exact CPulldown did not expose its native selected index");

        memory.write<uintptr_t>(
            ComboBoxList + NativeComboBoxListOwnedListOffset,
            List + 0x1000);
        require(!read_native_pulldown_selection(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "a CPulldown with a mismatched owned CList was accepted");

        memory.write<uintptr_t>(
            ComboBoxList + NativeComboBoxListOwnedListOffset,
            List);
        memory.write<int32_t>(
            SelectionModel + NativeListSelectionLastIndexOffset,
            0);
        require(!read_native_pulldown_selection(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "an ambiguous multi-index pulldown selection was accepted");

        memory.write<int32_t>(
            SelectionModel + NativeListSelectionLastIndexOffset,
            1);
        memory.write<uintptr_t>(
            selection_vtable + NativeListSelectionMinimumSlotOffset,
            AppBase + NativeListSelectionMinimumGetterRva + 1);
        require(!read_native_pulldown_selection(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "a pulldown with an unverified native index getter was accepted");
    }

    void test_native_pulldown_reads_live_highlight_before_commit()
    {
        FakeMemory memory;
        memory.write<uintptr_t>(
            Pulldown,
            AppBase + CPulldownVtableRva);
        memory.write<uintptr_t>(
            Pulldown + NativePulldownListOffset,
            List);
        memory.write<uintptr_t>(
            Pulldown + NativePulldownComboBoxListOffset,
            ComboBoxList);
        memory.write<uintptr_t>(
            ComboBoxList,
            AppBase + CComboBoxListVtableRva);
        memory.write<uintptr_t>(
            ComboBoxList + NativeComboBoxListOwnedListOffset,
            List);
        memory.write<uintptr_t>(
            List,
            AppBase + CListVtableRva);
        memory.write<uintptr_t>(
            List + NativeListDataModelOffset,
            Model);
        memory.write<uintptr_t>(
            List + NativeListSelectionModelOffset,
            SelectionModel);
        const uintptr_t selection_vtable =
            AppBase + CDefaultListSelectionModelVtableRva;
        memory.write<uintptr_t>(SelectionModel, selection_vtable);
        memory.write<uintptr_t>(
            selection_vtable + NativeListSelectionMaximumSlotOffset,
            AppBase + NativeListSelectionMaximumGetterRva);
        memory.write<uintptr_t>(
            selection_vtable + NativeListSelectionMinimumSlotOffset,
            AppBase + NativeListSelectionMinimumGetterRva);
        memory.write<int32_t>(
            SelectionModel + NativeListSelectionFirstIndexOffset,
            1);
        memory.write<int32_t>(
            SelectionModel + NativeListSelectionLastIndexOffset,
            1);

        // The dropdown is open on "Not set" while the selection model still
        // contains the previously committed "Save" value.
        memory.write<int16_t>(
            List + NativeListHighlightIndexOffset,
            0);

        const auto committed = read_native_pulldown_selection(
            memory.view(),
            Pulldown,
            AppBase);
        require(committed.matched && committed.selected_index == 1,
            "the test fixture did not preserve the old committed row");

        auto snapshot = read_native_pulldown_highlight(
            memory.view(),
            Pulldown,
            AppBase);
        require(snapshot.matched && snapshot.active &&
                snapshot.highlighted_index == 0,
            "the exact CPulldown did not expose its live highlighted row");

        memory.write<int16_t>(
            List + NativeListHighlightIndexOffset,
            -1);
        snapshot = read_native_pulldown_highlight(
            memory.view(),
            Pulldown,
            AppBase);
        require(snapshot.matched && !snapshot.active,
            "the exact closed pulldown was not distinguished from an invalid layout");

        memory.write<int16_t>(
            List + NativeListHighlightIndexOffset,
            2);
        require(!read_native_pulldown_highlight(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "an unproven third Set Password row was accepted");

        memory.write<int16_t>(
            List + NativeListHighlightIndexOffset,
            1);
        memory.write<uintptr_t>(
            ComboBoxList + NativeComboBoxListOwnedListOffset,
            List + 0x1000);
        require(!read_native_pulldown_highlight(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "a live row from a CList not owned by the CPulldown was accepted");

        memory.write<uintptr_t>(
            ComboBoxList + NativeComboBoxListOwnedListOffset,
            List);
        memory.write<uintptr_t>(
            List + NativeListDataModelOffset,
            0);
        require(!read_native_pulldown_highlight(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "a live row without the CList data model was accepted");

        memory.write<uintptr_t>(
            List + NativeListDataModelOffset,
            Model);
        memory.write<uintptr_t>(
            List,
            AppBase + CListVtableRva + 4);
        require(!read_native_pulldown_highlight(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "an object without the exact CList vtable was accepted");

        memory.write<uintptr_t>(
            List,
            AppBase + CListVtableRva);
        memory.write<uintptr_t>(
            ComboBoxList,
            AppBase + CComboBoxListVtableRva + 4);
        require(!read_native_pulldown_highlight(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "an object without the exact CComboBoxList vtable was accepted");
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
    test_selected_sheet_reads_live_rendered_dynamic_text();
    test_rendered_dynamic_text_rejects_unproven_or_inconsistent_state();
    test_duplicate_text_siblings_are_safe_but_conflicts_are_silent();
    test_sheet_requires_image_selection_shape_and_literal_only_stream();
    test_selected_image_reads_only_ghidra_proven_native_alt_field();
    test_image_only_sheet_requires_exact_captured_nested_image();
    test_selected_image_inspection_exposes_only_the_proven_label_path();
    test_native_image_getter_caption_requires_agreement_and_removes_pml_marker();
    test_native_image_getter_text_reads_long_caption_with_existing_bound();
    test_native_image_getter_caption_filter_allows_the_captured_banner_safely();
    test_sheet_rejects_unbounded_or_unterminated_native_data();
    test_sheet_rejects_wrapped_object_fields();
    test_cbutton_reads_ghidra_proven_label_buffer();
    test_form_select_editor_reads_only_its_exact_native_value();
    test_native_pulldown_reads_only_its_exact_selected_index();
    test_native_pulldown_reads_live_highlight_before_commit();
    test_sheet_focus_coalescing_preserves_only_captured_nested_chain();
    std::cout << "ok: selected PlayOnline controls require bounded native text and unambiguous hierarchy\n";
    return 0;
}
