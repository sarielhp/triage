using Test, Random, Triage
include("support.jl")

function check_avl(t, i, ids)
    i == 0 && return 0
    left, right, height, key = t.nodes[i]
    lh = check_avl(t, left, ids)
    push!(ids, key)
    rh = check_avl(t, right, ids)
    @test abs(lh-rh) <= 1
    @test height == 1+max(lh, rh)
    return height
end

function check_avl(t::Triage.ArrayStatus, i, ids, parent = 0)
    i == 0 && return 0
    @test t.parent[i] == parent
    @test t.slot[t.key[i]] == i
    lh = check_avl(t, t.left[i], ids, i)
    push!(ids, t.key[i])
    rh = check_avl(t, t.right[i], ids, i)
    @test abs(lh-rh) <= 1
    @test t.height[i] == 1+max(lh, rh)
    return t.height[i]
end

@testset "AVL insert/delete invariants" for status in (
    Triage.BalancedStatus(),
    Triage.ArrayStatus(514),
)

    n = 257
    p = Point[]
    for j in 1:n
        append!(p, Point[(-1-j/(2n), j), (1+j/(2n), j)])
    end
    chains = [Triage.Chain(2j-1, 1, 2j-1, 2j+1, true) for j in 1:n]
    s = Triage.Sweep(
        p,
        Int[],
        chains,
        zeros(Int, n),
        Triage.SweepEvent[],
        [(j, j, 0, 0, 0, 0) for j in 1:n],
        Int[],
        Int[],
        Tuple{Int,Int}[],
        status,
    )
    live = Set{Int}()
    rng = MersenneTwister(56173)
    for inserting in (true, false, true, false), key in randperm(rng, n)
        if inserting
            Triage.status_insert!(s, key)
            push!(live, key)
        else
            Triage.status_remove!(s, key)
            delete!(live, key)
        end
        ids = Int[]
        check_avl(s.status, s.status.root, ids)
        @test ids == sort!(collect(live))
    end
end

@testset "Triage native Julia" begin
    for d in generated(MersenneTwister(15152026))
        @test certify(d, triangulate(d.points, d.offsets))
        @test certify(d, chain_monotone(d.points, d.offsets))
        @test certify(d, triangulate_bounded(d.points, d.offsets))
        @test certify(d, Triage.chain_monotone_bounded(d.points, d.offsets))
        scan = Triage.prepare_sweep(d.points, d.offsets)
        tree = Triage.prepare_sweep(d.points, d.offsets, Triage.BalancedStatus())
        Triage.sweep!(scan)
        Triage.sweep!(tree)
        @test scan.diagonals == tree.diagonals
        array = Triage.prepare_sweep(d.points, d.offsets, Triage.ArrayStatus())
        Triage.sweep!(array)
        @test array.diagonals == tree.diagonals
        @test Triage.chain_monotone_bounded(d.points, d.offsets, Triage.ArrayStatus()) ==
              Triage.chain_monotone_bounded(d.points, d.offsets)
    end
    p = Point[(0, 0), (4, 0), (5, 4), (1, 5), (1.5, 1), (2, 2), (3, 1)]
    @test length(triangulate(p, [1, 5, 8])) == 7
    @test_throws ArgumentError triangulate(p, [0, 4, 7])
    @test_throws ArgumentError triangulate(p, [1, 3, 8])
    @test_throws ArgumentError triangulate(Point[])
    # Exact cancellation and range boundaries in predicate filters.
    @test Triage.turn((0.0, 0.0), (1.0, 1.0), (2.0, 2.0)) == 0
    @test Triage.turn((0.0, 0.0), (1.0, 1.0), (2.0, nextfloat(2.0))) == 1
    for n in (8, 128, 2048)
        p = Point[(-1, 0)]
        append!(p, [(i+0.125, -3+0.1sin(i)) for i in 0:(n-1)])
        push!(p, (n+1, 0))
        append!(p, [(i+0.375, 3+0.1cos(i)) for i in (n-1):-1:0])
        @test certify(Domain(p, [1, length(p)+1]), chain_monotone(p))
        @test certify(Domain(p, [1, length(p)+1]), triangulate_bounded(p))
    end
end
