#pragma once
#include "types.hpp"
#include "predicates.hpp"
#include <algorithm>
#include <array>
#include <cstdint>
#include <stdexcept>

namespace triage {
namespace small_detail {

inline bool contains(const Point& a, const Point& b, const Point& c,
                     const Point& p) {
    return orient_original(a, b, p) >= 0 && orient_original(b, c, p) >= 0 &&
           orient_original(c, a, p) >= 0;
}

inline Result quadrilateral(const std::vector<Point>& p) {
    Result out;
    out.triangles.reserve(2);
    if (orient_original(p[0], p[1], p[2]) > 0 &&
        orient_original(p[0], p[2], p[3]) > 0) {
        out.triangles.push_back({0, 1, 2});
        out.triangles.push_back({0, 2, 3});
    } else if (orient_original(p[1], p[2], p[3]) > 0 &&
               orient_original(p[1], p[3], p[0]) > 0) {
        out.triangles.push_back({1, 2, 3});
        out.triangles.push_back({1, 3, 0});
    } else {
        throw std::invalid_argument("invalid quadrilateral");
    }
    return out;
}

inline Result triangle(const std::vector<Point>& p) {
    if (orient_original(p[0], p[1], p[2]) <= 0)
        throw std::invalid_argument("nonpositive triangle");
    Result out;
    out.triangles.push_back({0, 1, 2});
    return out;
}

inline bool blocked(const std::vector<Point>& p, Index a, Index b, Index c,
                    std::uint64_t reflex) {
    const Point& pa = p[a];
    const Point& pb = p[b];
    const Point& pc = p[c];
    const double x0 = std::min({pa[0], pb[0], pc[0]});
    const double x1 = std::max({pa[0], pb[0], pc[0]});
    const double y0 = std::min({pa[1], pb[1], pc[1]});
    const double y1 = std::max({pa[1], pb[1], pc[1]});
    reflex &= ~(std::uint64_t{1} << a);
    reflex &= ~(std::uint64_t{1} << c);
    while (reflex != 0) {
        const auto id = static_cast<unsigned>(__builtin_ctzll(reflex));
        reflex &= reflex - 1;
        const Point& q = p[id];
        if (q[0] >= x0 && q[0] <= x1 && q[1] >= y0 && q[1] <= y1 && contains(pa, pb, pc, q))
            return true;
    }
    return false;
}

inline void refresh(const std::vector<Point>& p, unsigned id,
                    const std::array<std::uint8_t, 64>& prev,
                    const std::array<std::uint8_t, 64>& next,
                    std::uint64_t& reflex) {
    const auto bit = std::uint64_t{1} << id;
    if ((reflex & bit) != 0 && orient_original(p[prev[id]], p[id], p[next[id]]) > 0)
        reflex &= ~bit;
}

} // namespace small_detail

// A compact live-reflex mask is cheaper than allocating a tree or ear queue.
inline Result triangulate_reflex(const std::vector<Point>& p) {
    if (p.size() < 3 || p.size() > 64) throw std::invalid_argument("reflex polygon size must be 3..64");
    const unsigned n = static_cast<unsigned>(p.size());
    if (n == 3) return small_detail::triangle(p);
    if (n == 4) return small_detail::quadrilateral(p);
    std::array<std::uint8_t, 64> prev, next;
    std::uint64_t reflex = 0;
    for (unsigned i = 0; i < n; ++i) {
        prev[i] = static_cast<std::uint8_t>(i == 0 ? n - 1 : i - 1);
        next[i] = static_cast<std::uint8_t>(i + 1 == n ? 0 : i + 1);
        if (orient_original(p[prev[i]], p[i], p[next[i]]) <= 0)
            reflex |= std::uint64_t{1} << i;
    }
    Result out;
    out.triangles.reserve(n - 2);
    if (reflex == 0) {
        for (Index i = 1; i + 1 < n; ++i) out.triangles.push_back({0, i, i + 1});
        return out;
    }
    unsigned current = 0, remaining = n, misses = 0;
    while (remaining > 3) {
        const Index a = prev[current], c = next[current];
        if ((reflex & (std::uint64_t{1} << current)) == 0 &&
            !small_detail::blocked(p, a, current, c, reflex)) {
            out.triangles.push_back({a, current, c});
            next[a] = static_cast<std::uint8_t>(c);
            prev[c] = static_cast<std::uint8_t>(a);
            small_detail::refresh(p, a, prev, next, reflex);
            small_detail::refresh(p, c, prev, next, reflex);
            --remaining;
            misses = 0;
        } else if (++misses >= remaining) {
            throw std::invalid_argument("no ear found");
        }
        current = c;
    }
    const Index b = next[current], c = next[b];
    if (orient_original(p[current], p[b], p[c]) <= 0)
        throw std::invalid_argument("nonpositive final triangle");
    out.triangles.push_back({current, b, c});
    return out;
}

inline Result triangulate_small(const std::vector<Point>& p) {
    return triangulate_reflex(p);
}
} // namespace triage
