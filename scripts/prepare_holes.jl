using QuickEnv # silent
using SHA: sha256
include("holes_input_geometry.jl")
include("hole_synthetic_inputs.jl")

module TileSource
include("tiles.jl")
end

const H = HoleInputs

function read_fixture(path)
    parser = joinpath(@__DIR__, "read_hole_fixture.rb")
    io = IOBuffer(read(`ruby $parser $path`))
    rings = H.Polygon()
    for _ in 1:Int(read(io, UInt64))
        n = Int(read(io, UInt64))
        push!(rings, [(read(io, Float64), read(io, Float64)) for _ in 1:n])
    end
    eof(io) || error("trailing fixture data")
    return rings
end

function add_case!(polygons, ledger, label, raw)
    vertices = sum(length, raw)
    try
        rings = H.prepare_domain(raw)
        push!(polygons, rings)
        row = (
            length(polygons),
            label,
            length(raw),
            vertices,
            sum(length, rings),
            length(rings)-1,
            "accepted",
            H.polygon_hash(rings),
        )
        println(ledger, join(row, ','))
    catch exception
        exception isa InterruptException && rethrow(exception)
        reason = replace(sprint(showerror, exception), ',' => ';', '\n' => ' ')
        println(
            ledger,
            join(
                (0, label, length(raw), vertices, 0, max(0, length(raw)-1), reason, ""),
                ',',
            ),
        )
    end
    return nothing
end

function make_dataset(cases, name, destination, records)
    polygons = H.Polygon[]
    open(joinpath(records, "$name-eligibility.csv"), "w") do ledger
        println(
            ledger,
            "output_index,label,raw_rings,raw_vertices,prepared_vertices,holes,status,prepared_sha256",
        )
        for (i, (label, raw)) in enumerate(cases)
            add_case!(polygons, ledger, label, raw)
            i % 1000 == 0 && (println(name, ": checked ", i); flush(stdout))
        end
    end
    path = joinpath(destination, "$name.bin")
    hash = H.save_corpus(path, polygons)
    println(
        name,
        ": accepted ",
        length(polygons),
        " polygons; vertices=",
        sum(p -> sum(length, p), polygons),
        "; SHA256=",
        hash,
    )
    flush(stdout)
    return (name, length(polygons), sum(p -> sum(length, p), polygons), hash)
end

function tile_cases(source)
    bytes2hex(sha256(read(source))) ==
    "4f58c4cb13f1bb74a71cca25a21379f62882c956274c8ce10352ba132e2be1c7" ||
        error("changed pinned tile source")
    polygons = TileSource.decode_tiles(source)
    return [("tile-$i", p.rings) for (i, p) in enumerate(polygons) if length(p.rings) > 1]
end

function fixture_cases(directory, records)
    cases = Tuple{String,H.Polygon}[]
    open(joinpath(records, "fixture-sources.csv"), "w") do io
        println(io, "filename,sha256,rings,vertices")
        for file in sort(readdir(directory; join = true))
            endswith(file, ".json") || continue
            rings = read_fixture(file)
            println(
                io,
                join(
                    (
                        basename(file),
                        bytes2hex(sha256(read(file))),
                        length(rings),
                        sum(length, rings),
                    ),
                    ',',
                ),
            )
            push!(cases, (basename(file), rings))
        end
    end
    return cases
end

function main(source_root, destination, records)
    isdir(destination) && error("use a fresh binary destination")
    mkpath(destination)
    mkpath(records)
    rows = [
        make_dataset(
            tile_cases(joinpath(source_root, "bench/tiles-fixture.bin")),
            "tiles-holes",
            destination,
            records,
        ),
    ]
    push!(
        rows,
        make_dataset(
            fixture_cases(joinpath(source_root, "test/fixtures"), records),
            "fixtures-holes",
            destination,
            records,
        ),
    )
    push!(rows, make_dataset(synthetic_domains(), "synthetic-holes", destination, records))
    open(joinpath(records, "corpora.csv"), "w") do io
        println(io, "dataset,polygons,vertices,sha256")
        foreach(row -> println(io, join(row, ',')), rows)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 3 ||
        error("usage: prepare_holes.jl EAR CUT SOURCE ROOT BINARY DESTINATION RECORDS")
    main(ARGS...)
end
