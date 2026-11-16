module Triage

export Point, Triangle, triangulate, triangulate_bounded, chain_monotone

const Point = NTuple{2,Float64}
const Triangle = NTuple{3,Int}
include("predicates.jl")
include("small.jl")
include("chains.jl")
include("faces.jl")
include("bounded.jl")
include("array_status.jl")

"""
    triangulate(points::Vector{Point}, offsets=[1,length(points)+1])

Triangulate a simple CCW exterior with disjoint strictly interior CW holes.
Offsets are one-based half-open ring boundaries. Return one-based original
vertex indices, with positive triangle orientation; no new vertices are added.
The chain path requires globally distinct x coordinates. Coordinates must be
finite, bounded by 1e12, with no underflow in determinant products. The fast
API checks array shape, not domain validity; see the package README.
"""
function triangulate(points::Vector{Point}, offsets::Vector{Int} = [1, length(points)+1])
    return triangulate_dispatch(points, offsets, Val(false))
end

"""
    triangulate_bounded(points::Vector{Point}, offsets=[1,length(points)+1])

Optional O(n + m log m) strategy, where m counts x-monotone boundary chains.
Uses a deterministic AVL status and sorted endpoint directions. Same input
assumptions and small-input kernels as `triangulate`; the default is unchanged.
"""
function triangulate_bounded(
    points::Vector{Point},
    offsets::Vector{Int} = [1, length(points)+1],
)
    return triangulate_dispatch(points, offsets, Val(true))
end

function triangulate_dispatch(
    points,
    offsets,
    ::Val{Bounded},
    ::Val{UseArray} = Val(false),
) where {Bounded,UseArray}
    check_shape(points, offsets)
    if length(offsets) == 2 && length(points) <= 64
        return small_polygon(points)
    end
    if length(offsets) > 2 && length(points) <= 32
        result = lazy_holes(points, offsets)
        isnothing(result) || return result
    end
    if Bounded
        status = UseArray ? ArrayStatus() : BalancedStatus()
        return chain_monotone_bounded(points, offsets, status)
    end
    return chain_monotone(points, offsets)
end

function check_shape(points, offsets)
    length(points) >= 3 && length(offsets) >= 2 ||
        throw(ArgumentError("invalid polygon shape"))
    first(offsets) == 1 && last(offsets) == length(points)+1 ||
        throw(ArgumentError("invalid ring offsets"))
    all(i -> 3 <= offsets[i]-offsets[i-1] <= length(points), 2:length(offsets)) ||
        throw(ArgumentError("invalid ring size"))
    return nothing
end

end # module
