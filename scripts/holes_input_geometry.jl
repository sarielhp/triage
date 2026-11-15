using QuickEnv # silent

module HoleInputs
include("geographic/geometry.jl")

const Point = Tuple{Float64,Float64}
const Ring = Vector{Point}
const Polygon = Vector{Ring}

function point_inside(p, ring)
    winding = 0
    for i in eachindex(ring)
        a, b = ring[i], ring[mod1(i + 1, length(ring))]
        if a[2] <= p[2] < b[2]
            determinant(a, b, p) > 0 && (winding += 1)
        elseif b[2] <= p[2] < a[2]
            determinant(a, b, p) < 0 && (winding -= 1)
        end
    end
    return winding != 0
end

bounds(ring) =
    (minimum(first, ring), maximum(first, ring), minimum(last, ring), maximum(last, ring))
contains(box, p) = box[1] <= p[1] <= box[2] && box[3] <= p[2] <= box[4]
separate(a, b) = a[2] < b[1] || b[2] < a[1] || a[4] < b[3] || b[4] < a[3]

function domain_edges(rings)
    edges = Tuple{Point,Point,Int}[]
    for (id, ring) in enumerate(rings), i in eachindex(ring)
        push!(edges, (ring[i], ring[mod1(i + 1, length(ring))], id))
    end
    boxes = [
        (min(a[1], b[1]), max(a[1], b[1]), min(a[2], b[2]), max(a[2], b[2])) for
        (a, b, _) in edges
    ]
    return edges, boxes
end

function cross_candidates(edges, boxes, edge, node, ids)
    a, b, ring = edges[edge]
    for k in node.first:node.last
        other = ids[k]
        other > edge || continue
        c, d, other_ring = edges[other]
        ring == other_ring && continue
        separate(boxes[edge], boxes[other]) && continue
        intersects(a, b, c, d) && error("rings $ring and $other_ring touch or intersect")
    end
    return nothing
end

function check_crossings(rings)
    edges, boxes = domain_edges(rings)
    ids, nodes = collect(eachindex(edges)), BoundsNode[]
    build_bounds!(nodes, ids, boxes, 1, length(edges))
    stack = Int[]
    for edge in eachindex(edges)
        empty!(stack)
        push!(stack, 1)
        while !isempty(stack)
            node = nodes[pop!(stack)]
            disjoint(boxes[edge], node) && continue
            if node.left == 0
                cross_candidates(edges, boxes, edge, node, ids)
            else
                push!(stack, node.left, node.right)
            end
        end
    end
    return nothing
end

function check_containment(rings)
    boxes = bounds.(rings)
    for i in 2:length(rings)
        point_inside(first(rings[i]), rings[1]) || error("hole $i lies outside exterior")
        for j in 2:(i-1)
            separate(boxes[i], boxes[j]) && continue
            contains(boxes[j], first(rings[i])) &&
                point_inside(first(rings[i]), rings[j]) &&
                error("nested holes $i and $j")
            contains(boxes[i], first(rings[j])) &&
                point_inside(first(rings[j]), rings[i]) &&
                error("nested holes $j and $i")
        end
    end
    return nothing
end

function check_domain(rings; distinct_x = true)
    isempty(rings) && error("missing exterior ring")
    for (i, ring) in enumerate(rings)
        check_simple(i == 1 ? ring : reverse(ring))
    end
    check_crossings(rings)
    check_containment(rings)
    if distinct_x
        xs = sort([p[1] for ring in rings for p in ring])
        all(i -> xs[i] - xs[i-1] >= 1e-100, 2:length(xs)) ||
            error("original x coordinates are not globally distinct")
    end
    return true
end

function normalize_rings(raw)
    rings = [clean(Point[(Float64(p[1]), Float64(p[2])) for p in ring]) for ring in raw]
    foreach(reverse!, @view rings[2:end])
    return rings
end

function prepare_domain(raw)
    normalized = normalize_rings(raw)
    check_domain(normalized; distinct_x = false)
    projected = [[(x + sqrt(2)/10*y, y) for (x, y) in ring] for ring in normalized]
    prepared = normalize_rings(projected)
    check_domain(prepared)
    return prepared
end

function write_polygon(io, rings)
    write(io, UInt64(length(rings)))
    for ring in rings
        write(io, UInt64(length(ring)))
        write(io, reinterpret(UInt8, ring))
    end
    return nothing
end

function polygon_hash(rings)
    io = IOBuffer()
    write_polygon(io, rings)
    return bytes2hex(sha256(take!(io)))
end

function save_corpus(path, polygons)
    open(path, "w") do io
        write(io, UInt64(length(polygons)))
        foreach(p -> write_polygon(io, p), polygons)
    end
    return bytes2hex(sha256(read(path)))
end

end # module HoleInputs
