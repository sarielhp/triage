#pragma once
#include "types.hpp"
#include <algorithm>
#include <boost/multiprecision/cpp_int.hpp>
#include <cmath>
#include <limits>

namespace triage::detail { using Rational = boost::multiprecision::cpp_rational; }

namespace triage {
// Keep arbitrary-precision arithmetic outside the hot inlined filter.
[[gnu::noinline, gnu::cold]] inline int orient_original_exact(
    const Point& a, const Point& b, const Point& c) {
    if ((a[0] == b[0] && b[0] == c[0]) || (a[1] == b[1] && b[1] == c[1])) return 0;
    // Float64 inputs convert exactly. Recompute the entire determinant after
    // promotion; promoting already-rounded differences would not be a filter.
    if constexpr (std::numeric_limits<long double>::digits >
                  std::numeric_limits<double>::digits) {
        const long double dx = static_cast<long double>(a[0]) - c[0];
        const long double ex = static_cast<long double>(b[0]) - c[0];
        const long double dy = static_cast<long double>(a[1]) - c[1];
        const long double ey = static_cast<long double>(b[1]) - c[1];
        const long double left = dx * ey, right = ex * dy;
        const long double det = left - right;
        const long double bound = 8 * std::numeric_limits<long double>::epsilon() *
                                 (std::abs(left) + std::abs(right));
        if (std::abs(det) > bound) return det > 0 ? 1 : -1;
    }
    const detail::Rational ax(a[0]), ay(a[1]), bx(b[0]), by(b[1]), cx(c[0]), cy(c[1]);
    const detail::Rational exact = (ax-cx)*(by-cy)-(ay-cy)*(bx-cx);
    return exact > 0 ? 1 : exact < 0 ? -1 : 0;
}

inline int orient_original(const Point& a, const Point& b, const Point& c) {
    const double dx=a[0]-c[0], ex=b[0]-c[0];
    const double left=dx*(b[1]-c[1]), right=ex*(a[1]-c[1]);
    const double det=left-right;
    const double bound=8*std::numeric_limits<double>::epsilon()*(std::abs(left)+std::abs(right));
    if (std::abs(det)>bound) return det>0 ? 1 : -1;
    return orient_original_exact(a, b, c);
}
} // namespace triage
