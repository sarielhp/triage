using QuickEnv # silent

# Dyadic shear preserves orientations and makes all original x values distinct.
# The comb has no holes; the second family has many simultaneously active holes.
const XY = NTuple{2,Float64}

function comb(teeth)
    p = XY[(-2, -1), (3, -1)]
    for j in 0:(teeth-1)
        append!(p, XY[(3, 2j), (0, 2j), (0, 2j+1), (3, 2j+1)])
    end
    append!(p, XY[(3, 2teeth), (-2, 2teeth)])
    return [p]
end

function stacked_holes(holes)
    rings = [XY[(-10, -2), (10, -2), (10, 3holes+2), (-10, 3holes+2)]]
    for j in 0:(holes-1)
        push!(rings, XY[(0, 3j), (0, 3j+1), (2, 3j+1), (2, 3j)])
    end
    return rings
end

function write_domain(path, rings, denominator)
    open(path, "w") do io
        write(io, UInt64(1), UInt64(length(rings)))
        for ring in rings
            write(io, UInt64(length(ring)))
            for (x, y) in ring
                write(io, x+y/denominator, y)
            end
        end
    end
end

length(ARGS) == 1 || error("usage: prepare_adversarial.jl OUTPUT_DIRECTORY")
mkpath(ARGS[1])
for size in (64, 256, 1024, 4096, 16384)
    write_domain(joinpath(ARGS[1], "comb-$size.bin"), comb(size), 16size)
    write_domain(joinpath(ARGS[1], "stacked-holes-$size.bin"), stacked_holes(size), 16size)
end
println("Wrote 10 adversarial domains (260 to 65,540 vertices each).")
