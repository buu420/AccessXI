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

    // Layout fixture: app.dll SHA256 97F99A0A..., reviewed 2026-11-10 in Ghidra.
    // Literal addresses and fields deliberately do not derive from production constants.
    // The RVA beside each value is the function that proves it.
    constexpr uintptr_t ImageVtable = 0x00495224u;              // 229718
    constexpr uintptr_t SheetVtable = 0x0049BD94u;              // 23806b
    constexpr uintptr_t TextVtable = 0x0049EDC4u;               // 245937
    constexpr uintptr_t TextElementVtable = 0x0049EA7Cu;        // 2459ab
    constexpr uintptr_t FormSelectEditorVtable = 0x004940B0u;   // 21d245
    constexpr uintptr_t ButtonVtable = 0x003CCB14u;             // 7fcc9 at slot 0x190
    constexpr uintptr_t PulldownVtable = 0x003CDB74u;           // 80486
    constexpr uintptr_t ComboBoxListVtable = 0x003CD578u;       // 80465
    constexpr uintptr_t ListVtable = 0x003CF5ACu;               // 8eb97
    constexpr uintptr_t SelectionModelVtable = 0x004AB6E8u;     // 2884b9
    constexpr uintptr_t SelectionMaximumGetter = 0x00289D39u;   // 289d39
    constexpr uintptr_t SelectionMinimumGetter = 0x00289D44u;   // 289d44

    constexpr uintptr_t ChildrenBegin = 0x170u;                 // 82c4c, 83024
    constexpr uintptr_t ChildrenEnd = 0x174u;
    constexpr uintptr_t TextLiteralModel = 0x214u;              // 2207cb
    constexpr uintptr_t ModelTokenStream = 0x04u;               // 249992
    constexpr uintptr_t TextRenderedLines = 0x1ACu;             // 24934e
    constexpr uintptr_t LineFragments = 0x20u;                  // 246176, 249426
    constexpr uintptr_t ListHead = 0x00u;                       // 24ba50
    constexpr uintptr_t ListSize = 0x04u;
    constexpr uintptr_t FragmentCharacters = 0x28u;             // 2459ab, 246d65
    constexpr uintptr_t FragmentLength = 0x2Cu;
    constexpr uintptr_t PrimaryCaption = 0x10Cu;                // 289cbc
    constexpr uintptr_t AlternateCaption = 0x124u;
    constexpr uintptr_t LinkedLabel = 0x13Cu;
    constexpr uintptr_t StringLength = 0x10u;
    constexpr uintptr_t StringCapacity = 0x14u;
    constexpr uintptr_t LabelBegin = 0x168u;                    // 8d574
    constexpr uintptr_t LabelEnd = 0x16Cu;
    constexpr uintptr_t LabelLength = 0x1FAu;
    constexpr uintptr_t PulldownList = 0x1BCu;                  // 81d76, 816fc
    constexpr uintptr_t PulldownComboBoxList = 0x1C0u;
    constexpr uintptr_t ComboBoxListOwnedList = 0x200u;         // 8ed9c, 8fc23
    constexpr uintptr_t ListDataModel = 0x1E0u;                 // 907af
    constexpr uintptr_t ListSelectionModel = 0x1E8u;            // 9124e
    constexpr uintptr_t ListHighlightIndex = 0x1F2u;            // 8eb97, 907af, 901e2
    constexpr uintptr_t SelectionFirstIndex = 0x14u;            // 2884b9, 289d39
    constexpr uintptr_t SelectionLastIndex = 0x18u;
    constexpr uintptr_t SelectionMaximumSlot = 0x24u;           // 289d39 referenced from vtable + 0x24
    constexpr uintptr_t SelectionMinimumSlot = 0x28u;           // 289d44 referenced from vtable + 0x28

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
        memory.write<uintptr_t>(object, AppBase + TextVtable);
        memory.write<uintptr_t>(object + TextLiteralModel, model);
        memory.write<uintptr_t>(model + ModelTokenStream, stream);
        write_literal_stream(memory, stream, text);
    }

    // A one-element std::list: head node and value node, each { next, previous, value }.
    void write_single_node_list(
        FakeMemory& memory,
        uintptr_t list,
        uintptr_t head,
        uintptr_t node,
        uintptr_t value)
    {
        memory.write<uintptr_t>(list + ListHead, head);
        memory.write<uint32_t>(list + ListSize, 1);
        memory.write<uintptr_t>(head, node);
        memory.write<uintptr_t>(head + 4, node);
        memory.write<uintptr_t>(node, head);
        memory.write<uintptr_t>(node + 4, head);
        memory.write<uintptr_t>(node + 8, value);
    }

    void write_single_rendered_text_line(
        FakeMemory& memory,
        uintptr_t text_object,
        const std::u16string& text)
    {
        write_single_node_list(
            memory,
            text_object + TextRenderedLines,
            RenderedLineHead,
            RenderedLineNode,
            RenderedLine);
        write_single_node_list(
            memory,
            RenderedLine + LineFragments,
            RenderedFragmentHead,
            RenderedFragmentNode,
            RenderedFragment);

        memory.write<uintptr_t>(RenderedFragment, AppBase + TextElementVtable);
        memory.write<uintptr_t>(RenderedFragment + FragmentCharacters, RenderedCharacters);
        memory.write<uint32_t>(RenderedFragment + FragmentLength, static_cast<uint32_t>(text.size()));
        memory.write_utf16(RenderedCharacters, text, false);
    }

    FakeMemory valid_sheet(const std::u16string& text)
    {
        FakeMemory memory;
        memory.write<uintptr_t>(Sheet, AppBase + SheetVtable);
        memory.write<uintptr_t>(Sheet + ChildrenBegin, Children);
        memory.write<uintptr_t>(Sheet + ChildrenEnd, Children + 2 * sizeof(uintptr_t));
        memory.write<uintptr_t>(Children, Image);
        memory.write<uintptr_t>(Children + sizeof(uintptr_t), Text);
        memory.write<uintptr_t>(Image, AppBase + ImageVtable);
        write_text_child(memory, Text, Model, Stream, text);
        return memory;
    }

    // MSVC std::wstring: 8-unit inline buffer or heap pointer, then size and
    // capacity. A heap capacity grows to size | 7, so it can differ from size.
    void write_native_wide_string(
        FakeMemory& memory,
        uintptr_t field,
        uintptr_t heap,
        const std::u16string& text)
    {
        const uint32_t capacity =
            text.size() < 8 ? 7u : static_cast<uint32_t>(text.size() | 7u);
        if (capacity < 8)
            memory.write_utf16(field, text);
        else
        {
            memory.write<uintptr_t>(field, heap);
            memory.write_utf16(heap, text);
        }
        memory.write<uint32_t>(field + StringLength, static_cast<uint32_t>(text.size()));
        memory.write<uint32_t>(field + StringCapacity, capacity);
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
        memory.write<uintptr_t>(RenderedFragment, AppBase + ImageVtable);
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
        memory.write<uint32_t>(Text + TextRenderedLines + ListSize, 2);
        require(read_selected_control_text(memory.view(), Sheet, AppBase).empty(),
            "a rendered-line list whose size disagrees with its nodes must stay silent");

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
        memory.write<uintptr_t>(Sheet + ChildrenEnd, Children + 3 * sizeof(uintptr_t));
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
        memory.write<uintptr_t>(Image, AppBase + TextVtable);
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
        memory.write<uintptr_t>(Image, AppBase + ImageVtable);
        write_native_wide_string(memory, Image + PrimaryCaption, ImageAltHeap, u"Games");

        require(read_selected_control_text(memory.view(), Image, AppBase) == u"Games",
            "selected CPmlImage did not resolve its native alt property");

        memory.write<uint16_t>(Image + PrimaryCaption + 2, 0);
        require(read_selected_control_text(memory.view(), Image, AppBase).empty(),
            "CPmlImage alt text containing an embedded null must stay silent");

        memory = {};
        memory.write<uintptr_t>(Image, AppBase + ImageVtable);
        write_native_wide_string(memory, Image + PrimaryCaption, ImageAltHeap, u"Read the latest topics!");
        require(read_selected_control_text(memory.view(), Image, AppBase) == u"Read the latest topics!",
            "selected CPmlImage did not resolve its heap-allocated native alt property");
    }

    void test_image_only_sheet_requires_exact_captured_nested_image()
    {
        FakeMemory memory;
        memory.write<uintptr_t>(Sheet, AppBase + SheetVtable);
        memory.write<uintptr_t>(Sheet + ChildrenBegin, Children);
        memory.write<uintptr_t>(Sheet + ChildrenEnd, Children + sizeof(uintptr_t));
        memory.write<uintptr_t>(Children, Image);
        memory.write<uintptr_t>(Image, AppBase + ImageVtable);
        write_native_wide_string(memory, Image + PrimaryCaption, ImageAltHeap, u"Information");

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
        memory.write<uintptr_t>(Sheet, AppBase + SheetVtable);
        memory.write<uintptr_t>(Sheet + ChildrenBegin, Children);
        memory.write<uintptr_t>(Sheet + ChildrenEnd, Children + 2 * sizeof(uintptr_t));
        memory.write<uintptr_t>(Children, Image);
        memory.write<uintptr_t>(Children + sizeof(uintptr_t), Text);
        memory.write<uintptr_t>(Image, AppBase + ImageVtable);
        memory.write<uintptr_t>(Text, AppBase + TextVtable);
        memory.write<uintptr_t>(Image + LinkedLabel, LinkedLabelObject);
        memory.write<uintptr_t>(LinkedLabelObject, AppBase + SheetVtable);
        write_native_wide_string(memory, Image + PrimaryCaption, ImageAltHeap, u"Primary banner");
        write_native_wide_string(memory, Image + AlternateCaption, ImageAlternateAltHeap, u"Alternate caption");

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
        require(inspection.image == Image && inspection.image_vtable_rva == ImageVtable,
            "the inspection did not identify the selected CPmlImage");
        // Both strings are heap allocated with capacity size | 7, so these
        // fields distinguish the lengths the native getter tests from capacity.
        require(inspection.primary_capacity_130 == std::u16string(u"Primary banner").size() &&
                inspection.alternate_capacity_14c == std::u16string(u"Alternate caption").size(),
            "the inspection did not retain the caption lengths the native getter tests");
        require(inspection.linked_label_object == LinkedLabelObject &&
                inspection.linked_label_vtable_rva == SheetVtable,
            "the inspection did not expose the inherited native label object");
        require(inspection.primary_alt == u"Primary banner" &&
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
        memory.write<uintptr_t>(Sheet + ChildrenEnd, Children + 65 * sizeof(uintptr_t));
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
        memory.write<uintptr_t>(wrapped_sheet, AppBase + SheetVtable);
        memory.write<uintptr_t>(wrapped_sheet + ChildrenBegin, Children);
        memory.write<uintptr_t>(wrapped_sheet + ChildrenEnd, Children + 2 * sizeof(uintptr_t));
        memory.write<uintptr_t>(Children, Image);
        memory.write<uintptr_t>(Children + sizeof(uintptr_t), Text);
        memory.write<uintptr_t>(Image, AppBase + ImageVtable);
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
        memory.write<uintptr_t>(button, AppBase + ButtonVtable);
        memory.write<uintptr_t>(button + LabelBegin, buffer);
        memory.write<uintptr_t>(button + LabelEnd, buffer + (label.size() + 1) * 2);
        memory.write<int16_t>(button + LabelLength, static_cast<int16_t>(label.size()));
        memory.write_utf16(buffer, label);

        require(read_selected_control_text(memory.view(), button, AppBase) == label,
            "CButton visible label buffer was not decoded");

        memory.write<uintptr_t>(button + LabelEnd, buffer + 2);
        require(read_selected_control_text(memory.view(), button, AppBase).empty(),
            "CButton length beyond its native buffer must be rejected");
    }

    void test_form_select_editor_reads_only_its_exact_native_value()
    {
        FakeMemory memory;
        write_text_child(memory, Text, Model, Stream, u"Save");
        memory.write<uintptr_t>(Text, AppBase + FormSelectEditorVtable);

        require(read_selected_control_text(memory.view(), Text, AppBase) == u"Save",
            "the exact CPmlFormSelectEditor did not expose its visible selected value");

        memory.write<uintptr_t>(Text, AppBase + FormSelectEditorVtable + 4);
        require(read_selected_control_text(memory.view(), Text, AppBase).empty(),
            "an unverified CPmlText-derived object was treated as a form select editor");

        memory.write<uintptr_t>(Text, AppBase + FormSelectEditorVtable);
        memory.write<uint16_t>(Stream, 0x10);
        require(read_selected_control_text(memory.view(), Text, AppBase).empty(),
            "an unresolved dynamic select value was guessed from its token stream");
    }

    uintptr_t write_exact_pulldown_chain(FakeMemory& memory)
    {
        memory.write<uintptr_t>(
            Pulldown,
            AppBase + PulldownVtable);
        memory.write<uintptr_t>(
            Pulldown + PulldownList,
            List);
        memory.write<uintptr_t>(
            Pulldown + PulldownComboBoxList,
            ComboBoxList);
        memory.write<uintptr_t>(
            ComboBoxList,
            AppBase + ComboBoxListVtable);
        memory.write<uintptr_t>(
            ComboBoxList + ComboBoxListOwnedList,
            List);
        memory.write<uintptr_t>(
            List,
            AppBase + ListVtable);
        memory.write<uintptr_t>(
            List + ListSelectionModel,
            SelectionModel);

        const uintptr_t selection_vtable =
            AppBase + SelectionModelVtable;
        memory.write<uintptr_t>(SelectionModel, selection_vtable);
        memory.write<uintptr_t>(
            selection_vtable + SelectionMaximumSlot,
            AppBase + SelectionMaximumGetter);
        memory.write<uintptr_t>(
            selection_vtable + SelectionMinimumSlot,
            AppBase + SelectionMinimumGetter);
        memory.write<int32_t>(
            SelectionModel + SelectionFirstIndex,
            1);
        memory.write<int32_t>(
            SelectionModel + SelectionLastIndex,
            1);
        return selection_vtable;
    }

    void test_native_pulldown_reads_only_its_exact_selected_index()
    {
        FakeMemory memory;
        const uintptr_t selection_vtable = write_exact_pulldown_chain(memory);

        auto snapshot = read_native_pulldown_selection(
            memory.view(),
            Pulldown,
            AppBase);
        require(snapshot.matched && snapshot.selected_index == 1,
            "the exact CPulldown did not expose its native selected index");

        memory.write<uintptr_t>(
            ComboBoxList + ComboBoxListOwnedList,
            List + 0x1000);
        require(!read_native_pulldown_selection(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "a CPulldown with a mismatched owned CList was accepted");

        memory.write<uintptr_t>(
            ComboBoxList + ComboBoxListOwnedList,
            List);
        memory.write<int32_t>(
            SelectionModel + SelectionLastIndex,
            0);
        require(!read_native_pulldown_selection(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "an ambiguous multi-index pulldown selection was accepted");

        memory.write<int32_t>(
            SelectionModel + SelectionLastIndex,
            1);
        memory.write<uintptr_t>(
            selection_vtable + SelectionMinimumSlot,
            AppBase + SelectionMinimumGetter + 1);
        require(!read_native_pulldown_selection(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "a pulldown with an unverified native index getter was accepted");

        memory.write<uintptr_t>(
            selection_vtable + SelectionMinimumSlot,
            AppBase + SelectionMinimumGetter);
        memory.write<uintptr_t>(
            SelectionModel,
            AppBase + SelectionModelVtable + 4);
        require(!read_native_pulldown_selection(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "an object without the exact CDefaultListSelectionModel vtable was accepted");
    }

    void test_native_pulldown_reads_live_highlight_before_commit()
    {
        FakeMemory memory;
        write_exact_pulldown_chain(memory);
        memory.write<uintptr_t>(
            List + ListDataModel,
            Model);

        // The dropdown is open on "Not set" while the selection model still
        // contains the previously committed "Save" value.
        memory.write<int16_t>(
            List + ListHighlightIndex,
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
            List + ListHighlightIndex,
            -1);
        snapshot = read_native_pulldown_highlight(
            memory.view(),
            Pulldown,
            AppBase);
        require(snapshot.matched && !snapshot.active,
            "the exact closed pulldown was not distinguished from an invalid layout");

        memory.write<int16_t>(
            List + ListHighlightIndex,
            2);
        require(!read_native_pulldown_highlight(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "an unproven third Set Password row was accepted");

        memory.write<int16_t>(
            List + ListHighlightIndex,
            1);
        memory.write<uintptr_t>(
            ComboBoxList + ComboBoxListOwnedList,
            List + 0x1000);
        require(!read_native_pulldown_highlight(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "a live row from a CList not owned by the CPulldown was accepted");

        memory.write<uintptr_t>(
            ComboBoxList + ComboBoxListOwnedList,
            List);
        memory.write<uintptr_t>(
            List + ListDataModel,
            0);
        require(!read_native_pulldown_highlight(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "a live row without the CList data model was accepted");

        memory.write<uintptr_t>(
            List + ListDataModel,
            Model);
        memory.write<uintptr_t>(
            List,
            AppBase + ListVtable + 4);
        require(!read_native_pulldown_highlight(
                    memory.view(),
                    Pulldown,
                    AppBase).matched,
            "an object without the exact CList vtable was accepted");

        memory.write<uintptr_t>(
            List,
            AppBase + ListVtable);
        memory.write<uintptr_t>(
            ComboBoxList,
            AppBase + ComboBoxListVtable + 4);
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

    void test_exported_layout_matches_the_reviewed_build()
    {
        // The reader's callers consume these constants directly, so they must
        // describe the same build as the fixtures above.
        require(CpmlImageVtableRva == ImageVtable &&
                CpmlSheetVtableRva == SheetVtable &&
                CpmlTextVtableRva == TextVtable &&
                CpmlFormSelectEditorVtableRva == FormSelectEditorVtable &&
                CButtonVtableRva == ButtonVtable &&
                CPulldownVtableRva == PulldownVtable &&
                CComboBoxListVtableRva == ComboBoxListVtable &&
                CListVtableRva == ListVtable &&
                CDefaultListSelectionModelVtableRva == SelectionModelVtable,
            "an exported selected-control identity does not match the reviewed app.dll");
        require(NativePulldownListOffset == PulldownList &&
                NativePulldownComboBoxListOffset == PulldownComboBoxList &&
                NativeComboBoxListOwnedListOffset == ComboBoxListOwnedList &&
                NativeListDataModelOffset == ListDataModel &&
                NativeListSelectionModelOffset == ListSelectionModel &&
                NativeListHighlightIndexOffset == ListHighlightIndex,
            "an exported pulldown ownership offset does not match the reviewed app.dll");
        require(NativeListSelectionFirstIndexOffset == SelectionFirstIndex &&
                NativeListSelectionLastIndexOffset == SelectionLastIndex &&
                NativeListSelectionMaximumSlotOffset == SelectionMaximumSlot &&
                NativeListSelectionMinimumSlotOffset == SelectionMinimumSlot &&
                NativeListSelectionMaximumGetterRva == SelectionMaximumGetter &&
                NativeListSelectionMinimumGetterRva == SelectionMinimumGetter,
            "an exported list selection layout does not match the reviewed app.dll");
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
    test_exported_layout_matches_the_reviewed_build();
    std::cout << "ok: selected PlayOnline controls require bounded native text and unambiguous hierarchy\n";
    return 0;
}
