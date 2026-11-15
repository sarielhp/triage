using QuickEnv # silent
include("prepare_holes.jl")

function read_raw_geography(path, labels)
    return open(path) do io
        count = Int(read(io, UInt64))
        count == length(labels) || error("metadata count mismatch")
        cases = Tuple{String,H.Polygon}[]
        for label in labels
            rings = H.Polygon()
            for _ in 1:Int(read(io, UInt64))
                n = Int(read(io, UInt64))
                push!(rings, [(read(io, Float64), read(io, Float64)) for _ in 1:n])
            end
            push!(cases, (label, rings))
        end
        eof(io) || error("trailing source coordinates")
        cases
    end
end

function prepare_geographic_holes(raw, destination, records)
    metadata = readlines(joinpath(records, "geographic-hole-sources.csv"))[2:end]
    labels = [first(split(line, ',')) for line in metadata]
    cases = read_raw_geography(raw, labels)
    row = make_dataset(cases, "geographic-holes", destination, records)
    open(joinpath(records, "corpora.csv"), "a") do io
        println(io, join(row, ','))
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 3 ||
        error("usage: prepare_hole_geography.jl RAW.bin DESTINATION RECORDS")
    prepare_geographic_holes(ARGS...)
end
