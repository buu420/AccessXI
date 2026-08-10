#include "collision_native/collision_api.h"

#include <new>

namespace {

struct CollisionContext final
{
    std::uint32_t magic = 0x41584943u;
};

} // namespace

static_assert(sizeof(void*) == 4, "AccessXI collision navigation must be built for Win32/x86.");

extern "C" std::uint32_t AXI_COLLISION_CALL AXI_GetAbiVersion() noexcept
{
    return 1u;
}

extern "C" void* AXI_COLLISION_CALL AXI_CreateContext() noexcept
{
    return new (std::nothrow) CollisionContext{};
}

extern "C" void AXI_COLLISION_CALL AXI_DestroyContext(void* context) noexcept
{
    delete static_cast<CollisionContext*>(context);
}
