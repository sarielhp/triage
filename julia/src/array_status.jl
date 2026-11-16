# Adapted from BasicCompGeometry 0.6.1 SweepTriangulation.jl.
# Copyright (c) 2026 Sariel Har-Peled, MIT (see LICENSE).
# Array-backed AVL, iterative balancing, and deletion by handle.
mutable struct ArrayStatus
    left::Vector{Int}
    right::Vector{Int}
    parent::Vector{Int}
    height::Vector{Int}
    key::Vector{Int}    # interval ID currently stored in tree node slot
    slot::Vector{Int}   # tree slot holding an interval (0 if inactive)
    root::Int
    alloc::Int
    x::Float64
end

function ArrayStatus(n::Int)
    return ArrayStatus(
        zeros(Int, n),
        zeros(Int, n),
        zeros(Int, n),
        zeros(Int, n),
        zeros(Int, n),
        zeros(Int, n),
        0,
        0,
        0.0,
    )
end

@inline array_height(t::ArrayStatus, u::Int) = u == 0 ? 0 : t.height[u]

@inline function array_update_height!(t::ArrayStatus, u::Int)
    t.height[u] = 1 + max(array_height(t, t.left[u]), array_height(t, t.right[u]))
    return nothing
end

@inline function array_replace_child!(t::ArrayStatus, p::Int, old_c::Int, new_c::Int)
    if p == 0
        t.root = new_c
    elseif t.left[p] == old_c
        t.left[p] = new_c
    else
        t.right[p] = new_c
    end
    new_c != 0 && (t.parent[new_c] = p)
    return nothing
end

function array_rotate_left!(t::ArrayStatus, x::Int)::Int
    y = t.right[x]
    p = t.parent[x]
    b = t.left[y]

    t.right[x] = b
    b != 0 && (t.parent[b] = x)

    t.left[y] = x
    t.parent[x] = y

    array_replace_child!(t, p, x, y)
    array_update_height!(t, x)
    array_update_height!(t, y)
    return y
end

function array_rotate_right!(t::ArrayStatus, y::Int)::Int
    x = t.left[y]
    p = t.parent[y]
    b = t.right[x]

    t.left[y] = b
    b != 0 && (t.parent[b] = y)

    t.right[x] = y
    t.parent[y] = x

    array_replace_child!(t, p, y, x)
    array_update_height!(t, y)
    array_update_height!(t, x)
    return x
end

function array_rebalance_up!(t::ArrayStatus, start_node::Int)
    u = start_node
    while u != 0
        array_update_height!(t, u)
        bf = array_height(t, t.left[u]) - array_height(t, t.right[u])
        if bf > 1
            lc = t.left[u]
            if array_height(t, t.left[lc]) < array_height(t, t.right[lc])
                array_rotate_left!(t, lc)
            end
            u = array_rotate_right!(t, u)
        elseif bf < -1
            rc = t.right[u]
            if array_height(t, t.right[rc]) < array_height(t, t.left[rc])
                array_rotate_right!(t, rc)
            end
            u = array_rotate_left!(t, u)
        end
        u = t.parent[u]
    end
    return nothing
end


ArrayStatus() = ArrayStatus(0)
status_event!(s::Sweep{ArrayStatus}, v) = (s.status.x = s.p[v][1])
function status_prepare!(t::ArrayStatus, capacity)
    # Each extremum creates at most two interval records. Nodes are not reused;
    # this capacity covers the entire sweep, including already deleted records.
    for a in (t.left, t.right, t.parent, t.height, t.key, t.slot)
        resize!(a, capacity)
        fill!(a, 0)
    end
    t.root = t.alloc = 0
    return nothing
end
function status_insert!(s::Sweep{ArrayStatus}, id)
    t = s.status
    t.slot[id] == 0 || error("duplicate status boundary")
    idx = (t.alloc += 1)
    t.key[idx] = id
    t.slot[id] = idx
    t.height[idx] = 1
    cur, par, go_right = t.root, 0, false
    while cur != 0
        par = cur
        go_right = !status_less!(s, id, t.key[cur])
        cur = go_right ? t.right[cur] : t.left[cur]
    end
    t.parent[idx] = par
    if par == 0
        t.root = idx
    elseif go_right
        t.right[par] = idx
    else
        t.left[par] = idx
    end
    array_rebalance_up!(t, par)
    return nothing
end
function status_remove!(s::Sweep{ArrayStatus}, e)
    t = s.status
    z = t.slot[e]
    z != 0 || error("missing status boundary")
    t.slot[e] = 0

    if t.left[z] != 0 && t.right[z] != 0
        y = t.right[z]
        while t.left[y] != 0
            y = t.left[y]
        end
        ey = t.key[y]
        t.key[z] = ey
        t.slot[ey] = z
        z = y
    end

    child = t.left[z] != 0 ? t.left[z] : t.right[z]
    pz = t.parent[z]
    array_replace_child!(t, pz, z, child)
    t.left[z] = 0
    t.right[z] = 0
    t.parent[z] = 0
    t.height[z] = 0
    pz != 0 && array_rebalance_up!(t, pz)
    return nothing
end

function below!(s::Sweep{ArrayStatus}, v)
    t = s.status
    cur, best = t.root, 0
    while cur != 0
        id = t.key[cur]
        c = s.intervals[id][1]
        k = predecessor!(s, c, t.x)
        if turn(s, at(s, c, k), at(s, c, k+1), v) > 0
            best, cur = id, t.right[cur]
        else
            cur = t.left[cur]
        end
    end
    best != 0 || error("missing sweep interval")
    return best
end
