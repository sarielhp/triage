# Immutable isbits records live inline in vectors; updates replace a record.
struct Chain
    first::Int
    length::Int
    begin_id::Int
    end_id::Int
    forward::Bool
end
struct SweepEvent
    v::Int
    out::Int
    incoming::Int
    kind::Int
end
mutable struct Sweep
    p::Vector{Point}
    offsets::Vector{Int}
    chains::Vector{Chain}
    fingers::Vector{Int}
    events::Vector{SweepEvent}
    intervals::Vector{NTuple{6,Int}} # low, high, helper, next, slot, pending
    active::Vector{Int}
    owner::Vector{Int}
    diagonals::Vector{Tuple{Int,Int}}
end

@inline function vertex(c::Chain,k)
    v = c.first+(c.forward ? k : -k)
    v < c.begin_id && return v+c.end_id-c.begin_id
    v >= c.end_id && return v-c.end_id+c.begin_id
    return v
end
@inline at(s,c,k) = vertex(s.chains[c],k)
@inline turn(s::Sweep,a,b,c) = turn(s.p[a],s.p[b],s.p[c])

function predecessor!(s,c,x)
    k = s.fingers[c]
    while k+1 < s.chains[c].length && s.p[at(s,c,k+1)][1] < x
        k += 1
    end
    s.fingers[c] = k
    return k
end

function ring_events!(s,first,last)
    start = length(s.events)+1
    for v in first:last
        a,b = v == first ? last : v-1, v == last ? first : v+1
        s.p[v][1] != s.p[b][1] || throw(ArgumentError("distinct x required"))
        pa,pb = s.p[a][1] > s.p[v][1],s.p[b][1] > s.p[v][1]
        if pa == pb
            kind = (pa ? 1 : 3)+(turn(s,a,v,b) <= 0)
            push!(s.events,SweepEvent(v,0,0,kind))
        end
    end
    link_chains!(s,start,first,last)
    return nothing
end

function link_chains!(s,start,first,last)
    finish, base = length(s.events),length(s.chains)
    finish-start+1 >= 2 || error("missing extrema")
    for j in start:finish
        e = s.events[j]
        a,b = e.v,s.events[j == finish ? start : j+1].v
        len = b > a ? b-a : b+last-first+1-a
        forward = s.p[a][1] < s.p[b][1]
        push!(s.chains,Chain(forward ? a : b,len,first,last+1,forward))
        s.events[j] = SweepEvent(a,base+j-start+1,base+(j == start ? finish-start+1 : j-start),e.kind)
    end
    return nothing
end

function prepare_sweep(p,o)
    check_shape(p,o)
    all(q -> all(isfinite,q) && max(abs(q[1]),abs(q[2])) < 1e12,p) ||
        throw(ArgumentError("finite bounded coordinates required"))
    s = Sweep(p,o,Chain[],Int[],SweepEvent[],NTuple{6,Int}[],Int[],Int[],Tuple{Int,Int}[])
    for r in 1:(length(o)-1)
        ring_events!(s,o[r],o[r+1]-1)
    end
    resize!(s.fingers,length(s.chains)); fill!(s.fingers,0)
    resize!(s.owner,length(s.chains)); fill!(s.owner,0)
    sizehint!(s.intervals,length(s.events)); sizehint!(s.diagonals,length(s.events)÷2)
    sort!(s.events; by = e -> p[e.v][1])
    all(i -> p[s.events[i-1].v][1] != p[s.events[i].v][1],2:length(s.events)) ||
        throw(ArgumentError("distinct extremum x required"))
    return s
end

function diagonal!(s,a,b)
    a != b || error("zero diagonal")
    push!(s.diagonals,(a,b))
    return nothing
end

function fresh!(s,low,high,helper,pending)
    next = 0
    if pending
        a = at(s,low,predecessor!(s,low,s.p[helper][1])+1)
        b = at(s,high,predecessor!(s,high,s.p[helper][1])+1)
        next = s.p[a][1] < s.p[b][1] ? a : b
    end
    id = length(s.intervals)+1
    push!(s.intervals,(low,high,helper,next,length(s.active)+1,Int(pending)))
    push!(s.active,id)
    s.owner[low] = s.owner[high] = id
    return id
end

function remove!(s,id)
    slot = s.intervals[id][5]
    last = pop!(s.active)
    if slot <= length(s.active)
        s.active[slot] = last
        s.intervals[last] = Base.setindex(s.intervals[last],slot,5)
    end
    return nothing
end

function sync!(s,id,v)
    low,high,helper,next,slot,pending = s.intervals[id]
    x = s.p[v][1]
    if pending == 1 && s.p[next][1] < x
        diagonal!(s,helper,next)
        helper,pending = next,0
    end
    a,b = at(s,low,predecessor!(s,low,x)),at(s,high,predecessor!(s,high,x))
    latest = s.p[a][1] > s.p[b][1] ? a : b
    if s.p[latest][1] > s.p[helper][1]
        pending == 0 || error("missed pending merge")
        helper = latest
    end
    s.intervals[id] = (low,high,helper,next,slot,pending)
    return nothing
end

function finish!(s,id,v)
    sync!(s,id,v)
    s.intervals[id][6] == 1 && diagonal!(s,v,s.intervals[id][3])
    return nothing
end

function below!(s,v)
    best,ba,bb = 0,0,0
    for id in s.active
        c = s.intervals[id][1]
        k = predecessor!(s,c,s.p[v][1])
        a,b = at(s,c,k),at(s,c,k+1)
        turn(s,a,b,v) > 0 || continue
        higher = best == 0 || (s.p[ba][1] < s.p[a][1] ? turn(s,ba,bb,a) > 0 : turn(s,a,b,ba) < 0)
        higher && ((best,ba,bb) = (id,a,b))
    end
    best != 0 || error("missing sweep interval")
    return best
end

function split_event!(s,e,positive,negative)
    id = below!(s,e.v)
    sync!(s,id,e.v)
    old = s.intervals[id]
    diagonal!(s,e.v,old[3]); remove!(s,id)
    fresh!(s,old[1],negative,e.v,false)
    fresh!(s,positive,old[2],e.v,false)
    return nothing
end

function merge_event!(s,e,positive,negative)
    upper,lower = s.owner[positive],s.owner[negative]
    upper != lower || error("merge interval mismatch")
    finish!(s,lower,e.v); finish!(s,upper,e.v)
    low,high = s.intervals[lower][1],s.intervals[upper][2]
    remove!(s,lower); remove!(s,upper)
    fresh!(s,low,high,e.v,true)
    return nothing
end

function sweep!(s)
    for e in s.events
        positive = s.chains[e.out].forward ? e.out : e.incoming
        negative = s.chains[e.out].forward ? e.incoming : e.out
        if e.kind == 1
            fresh!(s,positive,negative,e.v,false)
        elseif e.kind == 2
            split_event!(s,e,positive,negative)
        elseif e.kind == 3
            id = s.owner[positive]
            id == s.owner[negative] || error("end interval mismatch")
            finish!(s,id,e.v); remove!(s,id)
        else
            merge_event!(s,e,positive,negative)
        end
    end
    isempty(s.active) || error("unfinished sweep")
    return nothing
end

function chain_monotone(p::Vector{Point},o::Vector{Int} = [1,length(p)+1])
    s = prepare_sweep(p,o)
    sweep!(s)
    marks = [e.v for e in s.events]
    for (a,b) in s.diagonals
        push!(marks,a,b)
    end
    sort!(marks); unique!(marks)
    return triangulate_faces(p,o,marks,s.diagonals)
end
