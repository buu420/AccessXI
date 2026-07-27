#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace accessxi::pol_pml
{
    constexpr uintptr_t CpmlImageVtableRva = 0x003DB00Cu;
    constexpr uintptr_t CpmlSheetVtableRva = 0x003E177Cu;
    constexpr uintptr_t CpmlTextVtableRva = 0x003E40ECu;
    constexpr uintptr_t CpmlFormSelectEditorVtableRva = 0x003D907Cu;
    constexpr uintptr_t CButtonVtableRva = 0x0032DC2Cu;
    constexpr uintptr_t CPulldownVtableRva = 0x0032F0ECu;
    constexpr uintptr_t CComboBoxListVtableRva = 0x0032EA6Cu;
    constexpr uintptr_t CListVtableRva = 0x003306CCu;
    constexpr uintptr_t CDefaultListSelectionModelVtableRva = 0x0031DC7Cu;

    constexpr uintptr_t NativePulldownListOffset = 0x1DCu;
    constexpr uintptr_t NativePulldownComboBoxListOffset = 0x1E0u;
    constexpr uintptr_t NativeComboBoxListOwnedListOffset = 0x220u;
    constexpr uintptr_t NativeListSelectionModelOffset = 0x210u;
    constexpr uintptr_t NativeListSelectionFirstIndexOffset = 0x18u;
    constexpr uintptr_t NativeListSelectionLastIndexOffset = 0x1Cu;
    constexpr uintptr_t NativeListSelectionMaximumSlotOffset = 0x24u;
    constexpr uintptr_t NativeListSelectionMinimumSlotOffset = 0x28u;
    constexpr uintptr_t NativeListSelectionMaximumGetterRva = 0x00004740u;
    constexpr uintptr_t NativeListSelectionMinimumGetterRva = 0x0000474Du;

    using ReadMemory = bool(*)(void* context, uintptr_t address, void* output, size_t size) noexcept;

    struct MemoryView
    {
        ReadMemory read = nullptr;
        void* context = nullptr;
    };

    enum class SheetFocusEventDisposition : uint8_t
    {
        replace,
        capture_nested_child,
        preserve
    };

    struct SelectedImageInspection
    {
        bool matched = false;
        bool object_is_sheet = false;
        bool nested_is_direct_child = false;
        uint32_t child_count = 0;
        uint32_t image_child_count = 0;
        uint32_t text_child_count = 0;
        uint32_t other_child_count = 0;
        uintptr_t image = 0;
        uintptr_t image_vtable_rva = 0;
        uint32_t primary_capacity_130 = 0;
        uint32_t alternate_capacity_14c = 0;
        uintptr_t linked_label_object = 0;
        uintptr_t linked_label_vtable_rva = 0;
        std::u16string primary_alt;
        std::u16string alternate_alt;
    };

    struct NativePulldownSelectionSnapshot
    {
        bool matched = false;
        uint32_t selected_index = 0;
    };

    SheetFocusEventDisposition classify_sheet_focus_event(
        bool have_pending_sheet_row,
        uintptr_t pending_sheet_row,
        uintptr_t pending_nested_child,
        bool incoming_is_sheet_row,
        uintptr_t incoming_manager,
        uintptr_t incoming_child) noexcept;

    // Captures the exact CPmlImage label path proven by the current app.dll:
    // primary/alternate native strings plus the linked object consulted by the
    // image's virtual label getter. This is diagnostic-only and never invents
    // or speaks a label.
    SelectedImageInspection inspect_selected_image_path(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base,
        uintptr_t captured_nested_child = 0) noexcept;

    // Accepts a live CPmlImage caption only when both native getter states
    // agree. A leading '$' is PlayOnline's PML control marker, not visible
    // caption text, and is removed only at the start of an agreed caption.
    std::string choose_selected_image_getter_caption(
        const std::string& primary,
        const std::string& alternate);

    // Copies a null-terminated caption returned by CPmlImage's native virtual
    // getter. The established selected-label ceiling is 120 UTF-16 code units;
    // missing termination or any longer value stays silent.
    std::u16string read_bounded_native_image_getter_text(
        const MemoryView& memory,
        uintptr_t characters) noexcept;

    // Applies the caption-specific 120-character ceiling while rejecting PML,
    // URL, and local-resource strings that are not player-facing labels.
    bool selected_image_getter_caption_allowed(const std::string& caption) noexcept;

    // Reads the exact CPulldown -> CComboBoxList -> CList ->
    // CDefaultListSelectionModel ownership chain used by the native
    // PlayOnline registration form. The selected row is accepted only when
    // both native selection endpoints agree and the verified min/max getter
    // slots still match the recognized app.dll.
    NativePulldownSelectionSnapshot read_native_pulldown_selection(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base) noexcept;

    // Reads only the selection shapes proven by the 2026-07-22 live trace and
    // matching app.dll Ghidra project. Dynamic CPmlText captions are accepted
    // only from their bounded rendered-line lists. Image-only captions require
    // the native CPmlImage alt field plus the exact captured sheet-to-image
    // selection relationship. Malformed or ambiguous state stays silent.
    std::u16string read_selected_control_text(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base,
        uintptr_t captured_nested_child = 0) noexcept;
}
