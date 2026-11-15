#pragma once
#include <array>
#include <cstdint>
#include <vector>

namespace triage {
using Index = std::uint32_t;
using Point = std::array<double, 2>;
using Triangle = std::array<Index, 3>;
// All IDs refer to the caller's original vertices (zero-based).
struct Result {
    std::vector<Triangle> triangles;
};
} // namespace triage
