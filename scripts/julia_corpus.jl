using QuickEnv # silent
using Statistics: median
include("../julia/src/Triage.jl")
using .Triage
include("../julia/test/support.jl")

function dump_corpus(corpus, path, triangulator = triangulate)
    open(path, "w") do io
        write(io, UInt64(0x484f4c4544554d31), UInt64(length(corpus)))
        for d in corpus
            ts = triangulator(d.points, d.offsets)
            write(io, UInt64(length(d.points)), UInt64(0), UInt64(length(ts)))
            for t in ts, i in t
                write(io, UInt32(i-1))
            end
        end
    end
end

function validate_corpus(corpus, output)
    open(output) do io
        read(io, UInt64) == 0x484f4c4544554d31 || error("bad output magic")
        read(io, UInt64) == length(corpus) || error("polygon count mismatch")
        for (i, d) in enumerate(corpus)
            read(io, UInt64) == length(d.points) || error("vertex count mismatch")
            read(io, UInt64) == 0 || error("Steiner vertices")
            n = Int(read(io, UInt64))
            0 <= n <= 3length(d.points) || error("bad triangle count")
            ts = [ntuple(_ -> Int(read(io, UInt32))+1, 3) for _ in 1:n]
            certify(d, ts)
            i % 10000 == 0 && println("validated ", i)
        end
        eof(io) || error("trailing output")
    end
    println("PASS exact coverage: ", length(corpus), " domains")
end

function measure(corpus, reps, triangulator::F = triangulate) where {F}
    checksum = 0
    start = time_ns()
    for _ in 1:reps, d in corpus
        ts = triangulator(d.points, d.offsets)
        checksum += 3length(ts)+first(ts)[1]+last(ts)[3]-2
    end
    return (time_ns()-start)*1e-9/reps, checksum
end

function benchmark(corpus, path)
    # Compile on small input, then warm the corpus in this same Julia process.
    triangulate(Point[(0, 0), (2, 0), (1, 1)])
    measure(corpus, 1)
    pilot, _ = measure(corpus, 1)
    reps = clamp(ceil(Int, 0.02/pilot), 1, 100000)
    samples = Float64[]
    checksum = 0
    open(path, "w") do io
        println(io, "method,sample,repetitions,seconds_per_corpus,checksum")
        for round in 1:12
            elapsed, total = measure(corpus, reps)
            checksum += total
            push!(samples, elapsed)
            println(io, join(("julia", round, reps, elapsed, total), ','))
        end
    end
    println(
        "Julia polygons=",
        length(corpus),
        " median_ms=",
        1000median(samples),
        " checksum=",
        checksum,
    )
end

function benchmark_strategies(corpus, path)
    methods = (triangulate, triangulate_bounded)
    names = ("julia", "triage-bounded-julia")
    pilots = Float64[]
    for method in methods
        method(Point[(0, 0), (2, 0), (1, 1)])
        measure(corpus, 1, method)
        elapsed, _ = measure(corpus, 1, method)
        push!(pilots, elapsed)
    end
    reps = clamp(ceil(Int, 0.02/minimum(pilots)), 1, 100000)
    samples = (Float64[], Float64[])
    open(path, "w") do io
        println(io, "method,sample,repetitions,seconds_per_corpus,checksum")
        for round in 1:12, j in 0:1
            mode = mod(round+j, 2)+1
            elapsed, checksum = measure(corpus, reps, methods[mode])
            push!(samples[mode], elapsed)
            println(io, join((names[mode], round, reps, elapsed, checksum), ','))
        end
    end
    for mode in 1:2
        println(
            names[mode],
            " polygons=",
            length(corpus),
            " median_ms=",
            1000median(samples[mode]),
        )
    end
end

length(ARGS) == 3 || error(
    "usage: julia_corpus.jl dump|dump-bounded|validate|bench|bench-strategies INPUT OUTPUT",
)
corpus = read_corpus(ARGS[2])
if ARGS[1] == "dump"
    dump_corpus(corpus, ARGS[3])
elseif ARGS[1] == "dump-bounded"
    dump_corpus(corpus, ARGS[3], triangulate_bounded)
elseif ARGS[1] == "validate"
    validate_corpus(corpus, ARGS[3])
elseif ARGS[1] == "bench"
    benchmark(corpus, ARGS[3])
elseif ARGS[1] == "bench-strategies"
    benchmark_strategies(corpus, ARGS[3])
else
    error("unknown operation")
end
