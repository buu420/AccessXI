#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace accessxi::pol_pml
{
    constexpr uintptr_t CpmlImageVtableRva = 0x003DB00Cu;
    constexpr uintptr_t CpmlSheetVtableRva = 0x003E177Cu;
    constexpr uintptr_t CpmlTextVtableRva = 0x003E40ECu;
    constexpr uintptr_t CButtonVtableRva = 0x0032DC2Cu;

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

    SheetFocusEventDisposition classify_sheet_focus_event(
        bool have_pending_sheet_row,
        uintptr_t pending_sheet_row,
        uintptr_t pending_nested_child,
        bool incoming_is_sheet_row,
        uintptr_t incoming_manager,
        uintptr_t incoming_child) noexcept;

    // Reads only the two selection shapes proven by the 2026-07-22 live trace
    // and the matching app.dll Ghidra project. Any malformed, dynamic, or
    // ambiguous native structure deliberately resolves to an empty string.
    std::u16string read_selected_control_text(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base) noexcept;
}
