using QuickEnv # silent
using SHA: sha256


function exact_det(a, b, c)
    ax, ay = Rational{BigInt}.(a)
    bx, by = Rational{BigInt}.(b)
    cx, cy = Rational{BigInt}.(c)
    (ax - cx) * (by - cy) - (ay - cy) * (bx - cx)
end

@inline function determinant(a, b, c)
    left = (a[1] - c[1]) * (b[2] - c[2])
    right = (a[2] - c[2]) * (b[1] - c[1])
    value = left - right
    abs(value) > 3.3306690738754716e-16 * (abs(left) + abs(right)) && return value
    Float64(exact_det(a, b, c))
end

on_segment(a, b, p) =
    min(a[1], b[1]) <= p[1] <= max(a[1], b[1]) && min(a[2], b[2]) <= p[2] <= max(a[2], b[2])

function intersects(a, b, c, d)
    o1, o2 = sign(determinant(a, b, c)), sign(determinant(a, b, d))
    o3, o4 = sign(determinant(c, d, a)), sign(determinant(c, d, b))
    o1 * o2 < 0 && o3 * o4 < 0 && return true
    (o1 == 0 && on_segment(a, b, c)) ||
        (o2 == 0 && on_segment(a, b, d)) ||
        (o3 == 0 && on_segment(c, d, a)) ||
        (o4 == 0 && on_segment(c, d, b))
end

function exact_area(p)
    if all(v -> all(isinteger, v), p)
        # |coordinate| < 1e9, n < 2e6: total magnitude < 4e24 < 2^127.
        return sum(
            Int128(a[1]) * Int128(b[2]) - Int128(a[2]) * Int128(b[1]) for
            (a, b) in zip(p, Iterators.flatten((@view(p[2:end]), (p[1],))))
        )
    end
    sum(exact_det((0.0, 0.0), p[i], p[mod1(i + 1, length(p))]) for i in eachindex(p))
end

function clean(p)
    q = Tuple{Float64,Float64}[]
    for v in p
        (isempty(q) || last(q) != v) && push!(q, v)
    end
    length(q) > 1 && first(q) == last(q) && pop!(q)
    while length(q) >= 3
        keep = [
            !(
                determinant(q[mod1(i - 1, length(q))], q[i], q[mod1(i + 1, length(q))]) == 0 &&
                on_segment(q[mod1(i - 1, length(q))], q[mod1(i + 1, length(q))], q[i])
            ) for i in eachindex(q)
        ]
        all(keep) && break
        q = q[keep]
    end
    exact_area(q) < 0 && reverse!(q)
    q
end

struct BoundsNode
    x0::Float64
    x1::Float64
    y0::Float64
    y1::Float64
    first::Int
    last::Int
    left::Int
    right::Int
end

function build_bounds!(nodes, ids, boxes, first, last)
    x0 = minimum(boxes[ids[k]][1] for k in first:last)
    x1 = maximum(boxes[ids[k]][2] for k in first:last)
    y0 = minimum(boxes[ids[k]][3] for k in first:last)
    y1 = maximum(boxes[ids[k]][4] for k in first:last)
    id = length(nodes) + 1
    push!(nodes, BoundsNode(x0, x1, y0, y1, first, last, 0, 0))
    last - first < 16 && return id
    axis = x1 - x0 > y1 - y0 ? 1 : 3
    sort!(@view(ids[first:last]); by = i -> boxes[i][axis] + boxes[i][axis+1])
    middle = (first + last) ÷ 2
    left = build_bounds!(nodes, ids, boxes, first, middle)
    right = build_bounds!(nodes, ids, boxes, middle + 1, last)
    nodes[id] = BoundsNode(x0, x1, y0, y1, first, last, left, right)
    id
end

disjoint(a, b) = a[2] < b.x0 || a[1] > b.x1 || a[4] < b.y0 || a[3] > b.y1

function check_candidates(p, edge, node, ids)
    n = length(p)
    for k in node.first:node.last
        other = ids[k]
        (other <= edge || other == edge + 1 || (edge == 1 && other == n)) && continue
        intersects(p[edge], p[mod1(edge + 1, n)], p[other], p[mod1(other + 1, n)]) &&
            error("self-intersection at edges $edge and $other")
    end
end

function check_simple(p)
    n = length(p)
    n >= 3 || error("fewer than three vertices")
    length(Set(p)) == n || error("nonconsecutive duplicate vertex")
    any(i -> determinant(p[mod1(i - 1, n)], p[i], p[mod1(i + 1, n)]) == 0, 1:n) &&
        error("collinear reversal/backtracking remains after cleaning")
    exact_area(p) > 0 || error("nonpositive exact area")
    boxes = [
        begin
            a, b = p[i], p[mod1(i + 1, n)]
            (min(a[1], b[1]), max(a[1], b[1]), min(a[2], b[2]), max(a[2], b[2]))
        end for i in eachindex(p)
    ]
    nodes, ids = BoundsNode[], collect(1:n)
    build_bounds!(nodes, ids, boxes, 1, n)
    stack = Int[]
    for edge in 1:n
        empty!(stack)
        push!(stack, 1)
        while !isempty(stack)
            node = nodes[pop!(stack)]
            disjoint(boxes[edge], node) && continue
            if node.left == 0
                check_candidates(p, edge, node, ids)
                continue
            end
            push!(stack, node.left, node.right)
        end
    end
    true
end


function read_points(path)
    open(path) do io
        n = Int(read(io,UInt64))
        coordinates = read!(io,Vector{Float64}(undef,2n))
        eof(io) || error("trailing input bytes")
        return [(coordinates[2i-1],coordinates[2i]) for i in 1:n]
    end
end
