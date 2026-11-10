#pragma once

#include "pol_pml/native_selected_text.h"

#include <cstddef>
#include <cstdint>
#include <string>

namespace accessxi::pol_pml
{
    // Layout of app.dll SHA256 97F99A0A... (November 2026), reviewed in Ghidra.
    // The documents now use the MSVC std::wstring without an allocator slot:
    // inline buffer or heap pointer at +0, size at +0x10, capacity at +0x14.
    inline constexpr uintptr_t CTextFieldVtableRva = 0x003D3054u;
    inline constexpr uintptr_t CPasswordFieldVtableRva = 0x003D3294u;
    inline constexpr uintptr_t CTextFieldModelVtableRva = 0x003D2A2Cu;
    inline constexpr uintptr_t CPasswordFieldModelVtableRva = 0x003D2ABCu;
    inline constexpr uintptr_t CpmlFormTextVtableRva = 0x00494460u;
    inline constexpr uintptr_t CpmlFormPasswordVtableRva = 0x00494504u;
    inline constexpr uintptr_t CScrollTextFieldVtableRva = 0x003D17B4u;
    inline constexpr uintptr_t CpmlFcScrollTextVtableRva = 0x004927E8u;
    inline constexpr uintptr_t CpmlFcScrollPasswordVtableRva = 0x00492A18u;
    inline constexpr uintptr_t NativeTextModelLengthGetterRva = 0x000A3354u;

    inline constexpr uintptr_t NativeFormFieldInnerControlOffset = 0x40u;
    inline constexpr uintptr_t NativeScrollTextFieldInnerControlOffset = 0x208u;
    inline constexpr uintptr_t NativeTextFieldActiveModelOffset = 0x19Cu;
    inline constexpr uintptr_t NativeTextFieldOwnedModelOffset = 0x1C8u;
    inline constexpr uintptr_t NativeTextModelStringOffset = 0x2Cu;
    inline constexpr uintptr_t NativeTextModelRawLengthOffset = 0x3Cu;
    inline constexpr uintptr_t NativeTextModelLengthSlotOffset = 0x30u;
    inline constexpr uintptr_t NativeWideStringInlineBufferOffset = 0x00u;
    inline constexpr uintptr_t NativeWideStringLengthOffset = 0x10u;
    inline constexpr uintptr_t NativeWideStringCapacityOffset = 0x14u;
    inline constexpr char16_t NativeTextModelSentinel = u'\x0003';
    inline constexpr uintptr_t NativePasswordMaskTemplateOffset = 0x1E2u;
    inline constexpr size_t NativePasswordMaskCapacity = 32u;

    enum class NativeTextFieldKind : uint8_t
    {
        none,
        text,
        password
    };

    struct NativeTextFieldSnapshot
    {
        bool matched = false;
        NativeTextFieldKind kind = NativeTextFieldKind::none;
        uintptr_t field = 0;
        std::u16string value;
        size_t character_count = 0;
    };

    // Reads only the exact CTextField/CPasswordField object graphs proven for
    // the recognized app.dll: the field itself, a CScrollTextField or PML
    // CPmlFCScrollText/CPmlFCScrollPassword that owns it, or a PML form that
    // owns that PML wrapper. Password character storage is never read:
    // password snapshots contain only the verified logical character count.
    NativeTextFieldSnapshot read_native_text_field(
        const MemoryView& memory,
        uintptr_t object,
        uintptr_t app_base) noexcept;
}
