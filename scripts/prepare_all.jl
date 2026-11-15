using QuickEnv # silent
include("prepare_holes.jl")

function all_tile_cases(source,holes)
    bytes2hex(sha256(read(source))) ==
        "4f58c4cb13f1bb74a71cca25a21379f62882c956274c8ce10352ba132e2be1c7" ||
        error("tile source hash mismatch")
    polygons = TileSource.decode_tiles(source)
    return [("tile-$i",p.rings) for (i,p) in enumerate(polygons) if (length(p.rings)>1) == holes]
end

function prepare_all(source,destination,records)
    isdir(destination) && error("use a fresh destination")
    mkpath(destination); mkpath(records)
    tiles = joinpath(source,"bench","tiles-fixture.bin")
    rows = [make_dataset(all_tile_cases(tiles,false),"tiles-single",destination,records)]
    push!(rows,make_dataset(all_tile_cases(tiles,true),"tiles-holes",destination,records))
    push!(rows,make_dataset(fixture_cases(joinpath(source,"test","fixtures"),records),"fixtures",destination,records))
    push!(rows,make_dataset(synthetic_domains(),"synthetic-holes",destination,records))
    open(joinpath(records,"corpora.csv"),"w") do io
        println(io,"dataset,polygons,vertices,sha256")
        foreach(row -> println(io,join(row,',')),rows)
    end
end

length(ARGS) == 3 || error("usage: prepare_all.jl EAR CUT SOURCE DESTINATION RECORDS")
prepare_all(ARGS...)
