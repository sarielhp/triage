#pragma once
// MIT License. Copyright (c) 2026 Sariel Har-Peled.
#include "chain_monotone.hpp"
#include "lazy_holes.hpp"

namespace triage {
// Trusted simple polygonal domain: CCW exterior, CW disjoint interior holes.
// Offsets delimit half-open rings in the flat coordinate array; no closing copy.
// See README for the geometric and numerical preconditions. No Steiner points.
inline Result triangulate(const std::vector<Point>& points,
                          const std::vector<Index>& offsets) {
    if (points.size()<3 || points.size()>=std::numeric_limits<Index>::max() ||
        offsets.size()<2 || offsets.front()!=0 || offsets.back()!=points.size())
        throw std::invalid_argument("invalid polygon shape");
    for (std::size_t r=1;r<offsets.size();++r)
        if (offsets[r]>points.size() || offsets[r]<offsets[r-1] || offsets[r]-offsets[r-1]<3)
            throw std::invalid_argument("invalid ring offsets");
    if (offsets.size()==2 && points.size()<=64) return triangulate_small(points);
    Result result;
    if (offsets.size()>2 && points.size()<=32 &&
        try_triangulate_lazy_holes(points,offsets,result)) return result;
    return triangulate_chain_monotone<ChainSearch::Walk>(points,offsets);
}
inline Result triangulate(const std::vector<Point>& points) {
    if (points.size()>=std::numeric_limits<Index>::max())
        throw std::invalid_argument("too many vertices");
    return triangulate(points,{0,static_cast<Index>(points.size())});
}
} // namespace triage
