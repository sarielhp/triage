using Test, Random, Triage
include("support.jl")

@testset "Triage native Julia" begin
    for d in generated(MersenneTwister(15152026))
        @test certify(d,triangulate(d.points,d.offsets))
        @test certify(d,chain_monotone(d.points,d.offsets))
    end
    p = Point[(0,0),(4,0),(5,4),(1,5),(1.5,1),(2,2),(3,1)]
    @test length(triangulate(p,[1,5,8])) == 7
    @test_throws ArgumentError triangulate(p,[0,4,7])
    @test_throws ArgumentError triangulate(p,[1,3,8])
    @test_throws ArgumentError triangulate(Point[])
    # Exact cancellation and range boundaries in predicate filters.
    @test Triage.turn((0.0,0.0),(1.0,1.0),(2.0,2.0)) == 0
    @test Triage.turn((0.0,0.0),(1.0,1.0),(2.0,nextfloat(2.0))) == 1
    for n in (8,128,2048)
        p = Point[(-1,0)]
        append!(p,[(i+0.125,-3+0.1sin(i)) for i in 0:(n-1)])
        push!(p,(n+1,0))
        append!(p,[(i+0.375,3+0.1cos(i)) for i in (n-1):-1:0])
        @test certify(Domain(p,[1,length(p)+1]),chain_monotone(p))
    end
end
