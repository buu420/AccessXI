#include "collision_native/collision_api.h"

#include <cstdint>
#include <iostream>

namespace {

int failures = 0;

void check(const bool condition, const char* expression, const int line)
{
    if (condition)
    {
        return;
    }

    std::cerr << "FAIL line " << line << ": " << expression << '\n';
    ++failures;
}

} // namespace

#define CHECK(expression) check(static_cast<bool>(expression), #expression, __LINE__)

int main()
{
    CHECK(AXI_GetAbiVersion() == std::uint32_t{ 1 });

    void* context = AXI_CreateContext();
    CHECK(context != nullptr);
    AXI_DestroyContext(context);

    if (failures != 0)
    {
        std::cerr << failures << " collision context assertion(s) failed.\n";
        return 1;
    }

    std::cout << "collision context ABI tests passed\n";
    return 0;
}
