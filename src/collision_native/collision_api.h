#pragma once

#include <cstdint>

#if !defined(_WIN32)
#error AccessXI collision navigation currently supports Windows only.
#endif

#if defined(ACCESSXI_COLLISION_NATIVE_EXPORTS)
#define AXI_COLLISION_API __declspec(dllexport)
#else
#define AXI_COLLISION_API __declspec(dllimport)
#endif

#define AXI_COLLISION_CALL __cdecl

extern "C"
{

AXI_COLLISION_API std::uint32_t AXI_COLLISION_CALL AXI_GetAbiVersion() noexcept;
AXI_COLLISION_API void* AXI_COLLISION_CALL AXI_CreateContext() noexcept;
AXI_COLLISION_API void AXI_COLLISION_CALL AXI_DestroyContext(void* context) noexcept;

}
