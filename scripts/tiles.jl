using QuickEnv # silent
using Serialization: serialize, deserialize


struct TilePolygon
    rings::Vector{Vector{Tuple{Int,Int}}}
    zoom::Int
end

# Adapted from the pinned upstream JS/C++ MVT decoders (ISC; fixtures/LICENSE).
# Mirrors the pinned upstream JS and C++ MVT fixture decoders. Coordinates
# remain exact integers; positive signed area starts a new polygon.
function read_varint(io)
    value, shift = 0, 0
    while true
        byte = read(io, UInt8)
        value |= Int(byte & 0x7f) << shift
        byte & 0x80 == 0 && return value
        shift += 7
        shift <= 28 || error("invalid UInt32 varint")
    end
end

zigzag(n) = (n >> 1) ⊻ -(n & 1)

function decode_rings(geometry)
    rings = Vector{Tuple{Int,Int}}[]
    ring = Tuple{Int,Int}[]
    x, y, i = 0, 0, 1
    while i <= length(geometry)
        command, count = geometry[i] & 7, geometry[i] >> 3
        i += 1
        if command == 7
            isempty(ring) || push!(rings, ring)
            ring = Tuple{Int,Int}[]
            continue
        end
        command in (1, 2) || error("unknown MVT command $command")
        for _ in 1:count
            x += zigzag(geometry[i]);
            y += zigzag(geometry[i+1]);
            i += 2
            if command == 1
                isempty(ring) || push!(rings, ring)
                ring = Tuple{Int,Int}[]
            end
            push!(ring, (x, y))
        end
    end
    isempty(ring) || push!(rings, ring)
    rings
end

function group_rings!(polygons, rings, zoom)
    current = Vector{Tuple{Int,Int}}[]
    for ring in rings
        length(ring) >= 3 || continue
        area = sum(a[1]*b[2]-a[2]*b[1] for (a,b) in zip(ring,circshift(ring,-1)))
        area == 0 && continue
        if area > 0
            isempty(current) || push!(polygons, TilePolygon(current, zoom))
            current = [ring]
            continue
        end
        isempty(current) || push!(current, ring)
    end
    isempty(current) || push!(polygons, TilePolygon(current, zoom))
end

function decode_tiles(path)
    polygons = TilePolygon[]
    open(path) do io
        while !eof(io)
            zoom, features = read_varint(io), read_varint(io)
            for _ in 1:features
                count = read_varint(io)
                geometry = [read_varint(io) for _ in 1:count]
                group_rings!(polygons, decode_rings(geometry), zoom)
            end
        end
    end
    length(polygons) == 119680 || error("decoder mismatch: $(length(polygons)) polygons")
    polygons
end

