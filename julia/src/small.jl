function quadrilateral(p)
        turn(p[1],p[2],p[3]) > 0 && turn(p[1],p[3],p[4]) > 0 &&
            return Triangle[(1,2,3),(1,3,4)]
        turn(p[2],p[3],p[4]) > 0 && turn(p[2],p[4],p[1]) > 0 &&
            return Triangle[(2,3,4),(2,4,1)]
        error("invalid quadrilateral")
end

@inline bit(i) = UInt64(1) << (i-1)

function small_polygon(p)
    n = length(p)
    if n == 3
        turn(p[1],p[2],p[3]) > 0 || error("nonpositive triangle")
        return Triangle[(1,2,3)]
    end
    n == 4 && return quadrilateral(p)
    prev = [i == 1 ? n : i-1 for i in 1:n]
    next = [i == n ? 1 : i+1 for i in 1:n]
    reflex = UInt64(0)
    for i in 1:n
        turn(p[prev[i]],p[i],p[next[i]]) <= 0 && (reflex |= bit(i))
    end
    reflex == 0 && return Triangle[(1,i,i+1) for i in 2:(n-1)]
    out = Triangle[]
    sizehint!(out,n-2)
    current, remaining, misses = 1,n,0
    while remaining > 3
        a, c = prev[current], next[current]
        if reflex & bit(current) == 0 && !blocked(p,a,current,c,reflex)
            push!(out,(a,current,c))
            next[a], prev[c] = c,a
            reflex = refresh(p,a,prev,next,reflex)
            reflex = refresh(p,c,prev,next,reflex)
            remaining -= 1
            misses = 0
        else
            misses += 1
            misses < remaining || error("no ear found")
        end
        current = c
    end
    b,c = next[current],next[next[current]]
    turn(p[current],p[b],p[c]) > 0 || error("nonpositive final triangle")
    push!(out,(current,b,c))
    return out
end

function blocked(p,a,b,c,reflex)
    bits = reflex & ~bit(a) & ~bit(c)
    while bits != 0
        i = trailing_zeros(bits)+1
        bits &= bits-1
        contains(p[a],p[b],p[c],p[i]) && return true
    end
    return false
end

@inline function refresh(p,i,prev,next,reflex)
    reflex & bit(i) != 0 && turn(p[prev[i]],p[i],p[next[i]]) > 0 && return reflex & ~bit(i)
    return reflex
end

# At most 32 original vertices in the dispatch path. Duplicate occurrences
# fit a UInt64 mask; pending holes use original indices, connected reflexes use slots.
mutable struct Cutter
    ids::Vector{Int}
    prev::Vector{Int}
    next::Vector{Int}
    reflex::UInt64
    pending::UInt64
    remaining::Int
    unjoined::Int
end

function cutter(p,o)
    n = length(p)
    c = Cutter(collect(1:n),zeros(Int,n),zeros(Int,n),0,0,o[2]-1,length(o)-2)
    sizehint!(c.ids,64); sizehint!(c.prev,64); sizehint!(c.next,64)
    for r in 1:(length(o)-1), i in o[r]:(o[r+1]-1)
        c.prev[i] = i == o[r] ? o[r+1]-1 : i-1
        c.next[i] = i+1 == o[r+1] ? o[r] : i+1
        r > 1 && (c.pending |= bit(i))
    end
    for i in 1:c.remaining
        refresh!(c,p,i)
    end
    return c
end

function refresh!(c,p,i)
    a,b,d = c.ids[c.prev[i]], c.ids[i], c.ids[c.next[i]]
    if turn(p[a],p[b],p[d]) <= 0
        c.reflex |= bit(i)
    else
        c.reflex &= ~bit(i)
    end
    return nothing
end

function connected_blocked(c,p,a,b,d)
    bits = c.reflex
    while bits != 0
        id = c.ids[trailing_zeros(bits)+1]
        bits &= bits-1
        id in (a,b,d) && continue
        contains(p[a],p[b],p[d],p[id]) && return true
    end
    return false
end

function blocking_hole(c,p,a,b,d)
    best, bits = 0,c.pending
    while bits != 0
        i = trailing_zeros(bits)+1
        bits &= bits-1
        if contains(p[a],p[b],p[d],p[i]) && (best == 0 || height(p[a],p[d],p[i],p[best]) > 0)
            best = i
        end
    end
    return best
end

function join_hole!(c,p,o,b,h)
    r = searchsortedlast(o,h)
    first, last = o[r],o[r+1]-1
    following, previous = c.next[b],c.prev[h]
    hc,bc = length(c.ids)+1,length(c.ids)+2
    push!(c.ids,c.ids[h],c.ids[b])
    push!(c.prev,previous,hc)
    push!(c.next,bc,following)
    c.next[b],c.prev[h],c.next[previous],c.prev[following] = h,b,hc,bc
    for i in first:last
        c.pending &= ~bit(i)
        refresh!(c,p,i)
    end
    refresh!(c,p,b); refresh!(c,p,hc); refresh!(c,p,bc)
    c.remaining += last-first+3
    c.unjoined -= 1
    return nothing
end

function cut_ear!(c,p,a,b,d,out)
    push!(out,(c.ids[a],c.ids[b],c.ids[d]))
    c.next[a], c.prev[d] = d,a
    c.reflex & bit(a) != 0 && refresh!(c,p,a)
    c.reflex & bit(d) != 0 && refresh!(c,p,d)
    c.remaining -= 1
    return nothing
end

function lazy_holes(p,o)
    c = cutter(p,o)
    out = Triangle[]
    sizehint!(out,length(p)+2c.unjoined-2)
    current, misses = 1,0
    while c.remaining > 3 || c.unjoined > 0
        a,d = c.prev[current],c.next[current]
        ia,ib,ic = c.ids[a],c.ids[current],c.ids[d]
        if c.reflex & bit(current) == 0 && !connected_blocked(c,p,ia,ib,ic)
            h = c.unjoined > 0 ? blocking_hole(c,p,ia,ib,ic) : 0
            if h != 0
                join_hole!(c,p,o,current,h)
                misses = 0
                continue
            end
            c.remaining > 3 || return nothing
            cut_ear!(c,p,a,current,d,out)
            misses, current = 0,d
            continue
        end
        misses += 1
        misses < c.remaining || return nothing
        current = d
    end
    b,d = c.next[current],c.next[c.next[current]]
    a,b,d = c.ids[current],c.ids[b],c.ids[d]
    turn(p[a],p[b],p[d]) > 0 || return nothing
    push!(out,(a,b,d))
    return out
end
