#pragma once

#include "collision_native/collision_types.h"

#include <filesystem>

namespace accessxi::collision {

FileSnapshot read_stable_snapshot(const std::filesystem::path& path);

} // namespace accessxi::collision
