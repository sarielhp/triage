using .Triage

struct Domain
    points::Vector{Point}
    offsets::Vector{Int}
end

function read_corpus(path)
    open(path) do io
        count = Int(read(io,UInt64))
        0 <= count <= 1_000_000 || error("invalid corpus count")
        result = Domain[]
        for _ in 1:count
            rings = Int(read(io,UInt64))
            1 <= rings <= 1_000_000 || error("invalid ring count")
            points,offsets = Point[],[1]
            for _ in 1:rings
                n = Int(read(io,UInt64))
                3 <= n < 2^31 || error("invalid ring size")
                append!(points,[(read(io,Float64),read(io,Float64)) for _ in 1:n])
                push!(offsets,length(points)+1)
            end
            push!(result,Domain(points,offsets))
        end
        eof(io) || error("trailing corpus bytes")
        return result
    end
end

function exact_orientation(p,t)
    a,b,c = (Rational{BigInt}.(p[i]) for i in t)
    return (b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1])
end

function add_edge!(edges,a,b,sign)
    key = (min(a,b),max(a,b))
    edges[key] = get(edges,key,0)+(a < b ? sign : -sign)
    return nothing
end

# Positive exact triangles and equality of oriented boundary chains certify
# coverage (winding number), unlike comparison of total floating-point areas.
function certify(d,ts)
    n = length(d.points)
    length(ts) == n+2(length(d.offsets)-2)-2 || error("wrong triangle count")
    edges = Dict{Tuple{Int,Int},Int}()
    for t in ts
        all(i -> 1 <= i <= n,t) || error("nonoriginal index")
        exact_orientation(d.points,t) > 0 || error("nonpositive exact triangle")
        add_edge!(edges,t[1],t[2],1)
        add_edge!(edges,t[2],t[3],1)
        add_edge!(edges,t[3],t[1],1)
    end
    for r in 1:(length(d.offsets)-1), i in d.offsets[r]:(d.offsets[r+1]-1)
        next = i+1 == d.offsets[r+1] ? d.offsets[r] : i+1
        add_edge!(edges,i,next,-1)
    end
    all(iszero,values(edges)) || error("oriented boundary mismatch")
    return true
end

function radial(n,x,y,radius,clockwise,rng)
    return Point[(x+r*cos(a),y+r*sin(a)) for i in 1:n for
        (r,a) in ((radius*(0.6+0.4rand(rng)),(clockwise ? -1 : 1)*2pi*(i+0.137)/n),)]
end

function generated(rng)
    result = Domain[]
    for holes in 0:20, repeat in 1:20
        p = radial(4+repeat%17,15,15,80,false,rng)
        o = [1,length(p)+1]
        for h in 0:(holes-1)
            append!(p,radial(3+(repeat+h)%6,10(h%5),10(h÷5),2,true,rng))
            push!(o,length(p)+1)
        end
        push!(result,Domain(p,o))
    end
    for n in (3,4,10,32,64,65,128,1024,4096)
        p = radial(n,0,0,20,false,rng)
        push!(result,Domain(p,[1,n+1]))
    end
    return result
end
