using QuickEnv # silent
include("prepare_holes.jl")

function prepare_single_geography(source, destination, records)
    parser = joinpath(@__DIR__, "selected_labels.rb")
    labels = split(
        chomp(read(`ruby $parser $(joinpath(records, "selected.csv"))`, String)),
        '\n',
    )
    cases = Tuple{String,H.Polygon}[]
    for label in labels
        p = H.read_points(joinpath(source, "rings", label*".raw.bin"))
        push!(cases, (label, [p]))
    end
    row = make_dataset(cases, "geographic-single", destination, records)
    open(joinpath(records, "corpora.csv"), "a") do io
        println(io, join(row, ','))
    end
end

length(ARGS) == 3 || error("usage: prepare_geography.jl SOURCE DESTINATION RECORDS")
prepare_single_geography(ARGS...)
