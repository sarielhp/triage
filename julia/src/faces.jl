# A node's outgoing link represents an original monotone range or one diagonal.
struct Node
    id::Int
    prev::Int
    next::Int
    alias::Int
    ring::Int
    original::Bool
    seen::Bool
end
@inline function node(n; prev = n.prev, next = n.next, original = n.original, seen = n.seen)
    return Node(n.id, prev, next, n.alias, n.ring, original, seen)
end
mutable struct Faces
    p::Vector{Point}
    offsets::Vector{Int}
    marks::Vector{Int}
    heads::Vector{Int}
    nodes::Vector{Node}
    stack::Vector{Tuple{Int,Bool}}
    triangles::Vector{Triangle}
end
@inline next_original(f, v, r) = v+1 == f.offsets[r+1] ? f.offsets[r] : v+1
@inline prev_original(f, v, r) = v == f.offsets[r] ? f.offsets[r+1]-1 : v-1
@inline turn(f::Faces, a, b, c) = turn(f.p[a], f.p[b], f.p[c])

function sector(f, v, q)
    n = f.nodes[v]
    before = f.nodes[n.prev]
    a = before.original ? prev_original(f, n.id, before.ring) : before.id
    b = n.original ? next_original(f, n.id, n.ring) : f.nodes[n.next].id
    left, right = turn(f, a, n.id, q), turn(f, n.id, b, q)
    return turn(f, a, n.id, b) >= 0 ? left > 0 && right > 0 : left > 0 || right > 0
end

function occurrence(f, key, q)
    v = f.heads[key]
    while v != 0
        sector(f, v, q) && return v
        v = f.nodes[v].alias
    end
    error("missing diagonal endpoint sector")
end

function diagonal!(f::Faces, a, b)
    ak, bk = searchsortedfirst(f.marks, a), searchsortedfirst(f.marks, b)
    av, bv = occurrence(f, ak, b), occurrence(f, bk, a)
    an, bn = f.nodes[av], f.nodes[bv]
    following, previous = an.next, bn.prev
    bc, ac = length(f.nodes)+1, length(f.nodes)+2
    push!(f.nodes, Node(b, previous, ac, f.heads[bk], bn.ring, false, false))
    push!(f.nodes, Node(a, bc, following, f.heads[ak], an.ring, an.original, false))
    f.heads[ak], f.heads[bk] = ac, bc
    f.nodes[av] = node(f.nodes[av]; next = bv, original = false)
    f.nodes[bv] = node(f.nodes[bv]; prev = av)
    f.nodes[previous] = node(f.nodes[previous]; next = bc)
    f.nodes[following] = node(f.nodes[following]; prev = ac)
    return nothing
end

function forward(f, c)
    v, id = c
    n = f.nodes[v]
    target = f.nodes[n.next].id
    id = n.original ? next_original(f, id, n.ring) : target
    return (id == target ? n.next : v, id)
end

function backward(f, c)
    v, id = c
    previous = f.nodes[v].prev
    n = f.nodes[previous]
    id = n.original ? prev_original(f, id, n.ring) : n.id
    return (id == n.id ? previous : v, id)
end

function emit!(f, a, b, c)
    sign = turn(f, a, b, c)
    sign != 0 || error("zero-area monotone triangle")
    push!(f.triangles, sign > 0 ? (a, b, c) : (a, c, b))
    return nothing
end

function take_event(f, lower, upper, last)
    high = lower[2] == last || (upper[2] != last && f.p[upper[2]][1] < f.p[lower[2]][1])
    id = high ? upper[2] : lower[2]
    if high
        upper = backward(f, upper)
    else
        lower = forward(f, lower)
    end
    return (id, high), lower, upper
end

function flush_stack!(f, v)
    while length(f.stack) >= 2
        q = pop!(f.stack)
        emit!(f, v, q[1], last(f.stack)[1])
    end
    return nothing
end

function same_side!(f, v)
    q = pop!(f.stack)
    while !isempty(f.stack)
        a = last(f.stack)
        t = turn(f, a[1], q[1], v[1])
        (v[2] ? t < 0 : t > 0) || break
        emit!(f, a[1], q[1], v[1])
        q = pop!(f.stack)
    end
    push!(f.stack, q, v)
    return nothing
end

function triangulate_face!(f, left, right)
    first, last_id = f.nodes[left].id, f.nodes[right].id
    lower, upper = forward(f, (left, first)), backward(f, (left, first))
    empty!(f.stack)
    push!(f.stack, (first, false))
    previous, lower, upper = take_event(f, lower, upper, last_id)
    push!(f.stack, previous)
    while lower[2] != last_id || upper[2] != last_id
        v, lower, upper = take_event(f, lower, upper, last_id)
        f.p[previous[1]][1] < f.p[v[1]][1] || error("nonmonotone face")
        if v[2] != last(f.stack)[2]
            flush_stack!(f, v[1])
            empty!(f.stack)
            push!(f.stack, previous, v)
        else
            same_side!(f, v)
        end
        previous = v
    end
    flush_stack!(f, last_id)
    return nothing
end

function build_faces(p, o, marks, diagonals)
    f = Faces(p, o, marks, collect(eachindex(marks)), Node[], Tuple{Int,Bool}[], Triangle[])
    sizehint!(f.nodes, length(marks)+2length(diagonals))
    sizehint!(f.stack, 64)
    sizehint!(f.triangles, length(p)+2(length(o)-2)-2)
    start = 1
    for r in 1:(length(o)-1)
        finish = searchsortedfirst(marks, o[r+1])-1
        finish-start+1 >= 2 || error("missing ring marks")
        for i in start:finish
            prev, next = i == start ? finish : i-1, i == finish ? start : i+1
            push!(f.nodes, Node(marks[i], prev, next, 0, r, true, false))
        end
        start = finish+1
    end
    for (a, b) in diagonals
        diagonal!(f, a, b)
    end
    return f
end

function visit_face!(f, start)
    left, right, v = start, start, start
    while true
        n = f.nodes[v]
        !n.seen || error("invalid face tape")
        f.nodes[v] = node(n; seen = true)
        f.p[n.id][1] < f.p[f.nodes[left].id][1] && (left = v)
        f.p[n.id][1] > f.p[f.nodes[right].id][1] && (right = v)
        v = n.next
        v == start && break
    end
    triangulate_face!(f, left, right)
    return nothing
end

function triangulate_faces(p, o, marks, diagonals)
    f = build_faces(p, o, marks, diagonals)
    for start in eachindex(f.nodes)
        f.nodes[start].seen || visit_face!(f, start)
    end
    length(f.triangles) == length(p)+2(length(o)-2)-2 || error("wrong triangle count")
    return f.triangles
end
