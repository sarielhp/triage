# Deterministic AVL status. Records are inline (left, right, height, interval).
# Lower chains do not cross, so their order remains valid as x advances.
mutable struct BalancedStatus
    nodes::Vector{NTuple{4,Int}}
    root::Int
    x::Float64
end
BalancedStatus() = BalancedStatus(NTuple{4,Int}[], 0, 0.0)
status_event!(s::Sweep{BalancedStatus}, v) = (s.status.x = s.p[v][1])

function status_less!(s, i, j)
    i == j && return false
    c, d = s.intervals[i][1], s.intervals[j][1]
    k, l = predecessor!(s, c, s.status.x), predecessor!(s, d, s.status.x)
    a, b = at(s, c, k), at(s, d, l)
    return s.p[a][1] < s.p[b][1] ? turn(s, a, at(s, c, k+1), b) > 0 :
           turn(s, b, at(s, d, l+1), a) < 0
end

@inline avl_height(t, i) = i == 0 ? 0 : t.nodes[i][3]
function avl_update!(t, i, left, right, key = t.nodes[i][4])
    t.nodes[i] = (left, right, 1+max(avl_height(t, left), avl_height(t, right)), key)
    return i
end

function avl_left!(t, i)
    left, right, _, key = t.nodes[i]
    a, b, _, other = t.nodes[right]
    avl_update!(t, i, left, a, key)
    avl_update!(t, right, i, b, other)
    return right
end

function avl_right!(t, i)
    left, right, _, key = t.nodes[i]
    a, b, _, other = t.nodes[left]
    avl_update!(t, i, b, right, key)
    avl_update!(t, left, a, i, other)
    return left
end

function avl_balance!(t, i)
    left, right, _, key = t.nodes[i]
    delta = avl_height(t, left)-avl_height(t, right)
    if delta > 1
        a, b = t.nodes[left]
        avl_height(t, a) < avl_height(t, b) && (left = avl_left!(t, left))
        avl_update!(t, i, left, right, key)
        return avl_right!(t, i)
    elseif delta < -1
        a, b = t.nodes[right]
        avl_height(t, a) > avl_height(t, b) && (right = avl_right!(t, right))
        avl_update!(t, i, left, right, key)
        return avl_left!(t, i)
    end
    return avl_update!(t, i, left, right, key)
end

function avl_insert!(s, i, fresh)
    i == 0 && return fresh
    t = s.status
    left, right, _, key = t.nodes[i]
    if status_less!(s, t.nodes[fresh][4], key)
        left = avl_insert!(s, left, fresh)
    else
        right = avl_insert!(s, right, fresh)
    end
    avl_update!(t, i, left, right)
    return avl_balance!(t, i)
end

function avl_erase!(s, i, target)
    i != 0 || error("missing status boundary")
    t = s.status
    left, right, _, key = t.nodes[i]
    if key == target
        left == 0 && return right
        right == 0 && return left
        successor = right
        while t.nodes[successor][1] != 0
            successor = t.nodes[successor][1]
        end
        key = t.nodes[successor][4]
        right = avl_erase!(s, right, key)
    elseif status_less!(s, target, key)
        left = avl_erase!(s, left, target)
    else
        right = avl_erase!(s, right, target)
    end
    avl_update!(t, i, left, right, key)
    return avl_balance!(t, i)
end

function status_insert!(s::Sweep{BalancedStatus}, id)
    t = s.status
    push!(t.nodes, (0, 0, 1, id))
    t.root = avl_insert!(s, t.root, length(t.nodes))
    return nothing
end

function status_remove!(s::Sweep{BalancedStatus}, id)
    s.status.root = avl_erase!(s, s.status.root, id)
    return nothing
end

function below!(s::Sweep{BalancedStatus}, v)
    i, best = s.status.root, 0
    while i != 0
        left, right, _, id = s.status.nodes[i]
        c = s.intervals[id][1]
        k = predecessor!(s, c, s.status.x)
        if turn(s, at(s, c, k), at(s, c, k+1), v) > 0
            best, i = id, right
        else
            i = left
        end
    end
    best != 0 || error("missing sweep interval")
    return best
end

# Each pair of nodes represents twin halfedges. A boundary halfedge uses its
# actual adjacent original vertex as tangent, not the chord across its range.
function sorted_edge!(f, tangent, a, b, ta, tb, ring, boundary)
    u, v = length(f.nodes)+1, length(f.nodes)+2
    push!(f.nodes, Node(a, 0, 0, v, ring, boundary, false))
    push!(f.nodes, Node(b, 0, 0, u, ring, false, boundary))
    push!(tangent, ta, tb)
    return nothing
end

@inline function upper_direction(p, a, b)
    return p[b][2] > p[a][2] || (p[b][2] == p[a][2] && p[b][1] > p[a][1])
end

function angle_less(f, tangent, a, b)
    v, w = f.nodes[a].id, f.nodes[b].id
    v != w && return v < w
    ah, bh = upper_direction(f.p, v, tangent[a]), upper_direction(f.p, v, tangent[b])
    ah != bh && return ah > bh
    side = turn(f, v, tangent[a], tangent[b])
    return side != 0 ? side > 0 : a < b
end

function link_sorted_edges!(f, order)
    first = 1
    while first <= length(order)
        last = first+1
        while last <= length(order) && f.nodes[order[last]].id == f.nodes[order[first]].id
            last += 1
        end
        for j in first:(last-1)
            incoming = f.nodes[order[j]].alias
            outgoing = order[j == first ? last-1 : j-1]
            f.nodes[incoming] = node(f.nodes[incoming]; next = outgoing)
            f.nodes[outgoing] = node(f.nodes[outgoing]; prev = incoming)
        end
        first = last
    end
    return nothing
end

function build_sorted_faces(p, o, marks, diagonals)
    f = Faces(p, o, marks, Int[], Node[], Tuple{Int,Bool}[], Triangle[])
    capacity = 2(length(marks)+length(diagonals))
    sizehint!(f.nodes, capacity)
    sizehint!(f.stack, 64)
    sizehint!(f.triangles, length(p)+2(length(o)-2)-2)
    tangent = Int[]
    sizehint!(tangent, capacity)
    start = 1
    for r in 1:(length(o)-1)
        finish = searchsortedfirst(marks, o[r+1])-1
        finish-start+1 >= 2 || error("missing ring marks")
        for i in start:finish
            a, b = marks[i], marks[i == finish ? start : i+1]
            sorted_edge!(
                f,
                tangent,
                a,
                b,
                next_original(f, a, r),
                prev_original(f, b, r),
                r,
                true,
            )
        end
        start = finish+1
    end
    for (a, b) in diagonals
        sorted_edge!(f, tangent, a, b, b, a, 1, false)
    end
    order = collect(eachindex(f.nodes))
    # Specify MergeSort explicitly: deterministic O(k log k), even on bad input.
    sort!(order; lt = (a, b) -> angle_less(f, tangent, a, b), alg = MergeSort)
    link_sorted_edges!(f, order)
    return f
end

function chain_monotone_bounded(p::Vector{Point}, o::Vector{Int})
    s = prepare_sweep(p, o, BalancedStatus())
    sweep!(s)
    marks = [e.v for e in s.events]
    for (a, b) in s.diagonals
        push!(marks, a, b)
    end
    sort!(marks; alg = MergeSort)
    unique!(marks)
    f = build_sorted_faces(p, o, marks, s.diagonals)
    for start in eachindex(f.nodes)
        f.nodes[start].seen || visit_face!(f, start)
    end
    length(f.triangles) == length(p)+2(length(o)-2)-2 || error("wrong triangle count")
    return f.triangles
end
