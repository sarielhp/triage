# Filter on original Float64 inputs; recompute differences after exact conversion.
@noinline function exact_turn(a, b, c)
    ax, ay = Rational{BigInt}.(a)
    bx, by = Rational{BigInt}.(b)
    cx, cy = Rational{BigInt}.(c)
    return Int(sign((ax-cx)*(by-cy)-(ay-cy)*(bx-cx)))
end

@inline function turn(a, b, c)
    left = (a[1]-c[1])*(b[2]-c[2])
    right = (b[1]-c[1])*(a[2]-c[2])
    det = left-right
    abs(det) > 8eps(Float64)*(abs(left)+abs(right)) && return det > 0 ? 1 : -1
    return exact_turn(a, b, c)
end

@noinline function exact_height(a, c, p, q)
    ax, ay = Rational{BigInt}.(a)
    cx, cy = Rational{BigInt}.(c)
    px, py = Rational{BigInt}.(p)
    qx, qy = Rational{BigInt}.(q)
    return Int(sign((ax-cx)*(py-qy)-(ay-cy)*(px-qx)))
end

@inline function height(a, c, p, q)
    left = (a[1]-c[1])*(p[2]-q[2])
    right = (a[2]-c[2])*(p[1]-q[1])
    det = left-right
    abs(det) > 8eps(Float64)*(abs(left)+abs(right)) && return det > 0 ? 1 : -1
    return exact_height(a, c, p, q)
end

@inline function contains(a, b, c, q)
    min(a[1], b[1], c[1]) <= q[1] <= max(a[1], b[1], c[1]) || return false
    min(a[2], b[2], c[2]) <= q[2] <= max(a[2], b[2], c[2]) || return false
    return turn(a,b,q) >= 0 && turn(b,c,q) >= 0 && turn(c,a,q) >= 0
end
