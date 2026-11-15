using QuickEnv # silent
import BasicCompGeometry as BCG
using BasicCompGeometry.IpeDraw: figure, draw_polygon!, set_layer!
include("../src/Triage.jl")
using .Triage
include("../test/support.jl")
include("../../scripts/holes_input_geometry.jl")

# Regenerate with: ruby scripts/draw_wordmark.rb
# Stencil cuts make R and A simple holes rather than disconnected islands.
function glyphs()
    t = Point[
        (0, 7),
        (5, 7),
        (5, 5.5),
        (3.25, 5.5),
        (3.25, 0),
        (1.75, 0),
        (1.75, 5.5),
        (0, 5.5),
    ]
    r = Point[
        (0, 0),
        (1.5, 0),
        (1.5, 3),
        (2.5, 3),
        (4, 0),
        (5.5, 0),
        (3.75, 3.5),
        (4.75, 4.25),
        (4.75, 4.75),
        (3.25, 4.75),
        (3.25, 4.5),
        (2.75, 4),
        (1.5, 4),
        (1.5, 5.75),
        (3.25, 5.75),
        (3.25, 5.25),
        (4.75, 5.25),
        (4.75, 6.25),
        (4, 7),
        (0, 7),
    ]
    i = Point[
        (0, 0),
        (4, 0),
        (4, 1.5),
        (2.75, 1.5),
        (2.75, 5.5),
        (4, 5.5),
        (4, 7),
        (0, 7),
        (0, 5.5),
        (1.25, 5.5),
        (1.25, 1.5),
        (0, 1.5),
    ]
    a = Point[
        (0, 0),
        (1.5, 0),
        (2, 2),
        (2.5, 2),
        (2.5, 3.25),
        (2.25, 3.25),
        (2.875, 5.75),
        (3.5, 3.25),
        (3, 3.25),
        (3, 2),
        (3.75, 2),
        (4.25, 0),
        (5.75, 0),
        (4, 7),
        (1.75, 7),
    ]
    g = Point[
        (5, 6),
        (4, 7),
        (1, 7),
        (0, 6),
        (0, 1),
        (1, 0),
        (4, 0),
        (5, 1),
        (5, 3.75),
        (2.75, 3.75),
        (2.75, 2.5),
        (3.5, 2.5),
        (3.5, 1.5),
        (1.5, 1.5),
        (1.5, 5.5),
        (3.5, 5.5),
        (3.5, 4.75),
        (5, 4.75),
    ]
    e = Point[
        (0, 0),
        (5, 0),
        (5, 1.5),
        (1.5, 1.5),
        (1.5, 2.75),
        (4, 2.75),
        (4, 4.25),
        (1.5, 4.25),
        (1.5, 5.5),
        (5, 5.5),
        (5, 7),
        (0, 7),
    ]
    return [t, r, i, a, g, e]
end

area(r) = sum(a[1]*b[2]-a[2]*b[1] for (a, b) in zip(r, circshift(r, -1)))

function domain()
    rings = Vector{Point}[]
    x = 2.0
    for glyph in glyphs()
        ring = [(px+x, py+2.0) for (px, py) in glyph]
        area(ring) > 0 && reverse!(ring)
        push!(rings, ring)
        x += maximum(first, glyph)+1.25
    end
    width = x+0.75
    pushfirst!(rings, Point[(0, 0), (width, 0), (width, 11), (0, 11)])
    offsets = cumsum([1; length.(rings)])
    return Domain(reduce(vcat, rings), offsets), rings, width
end

# Every coordinate is dyadic. This shear is exact in binary64 at these scales,
# breaks x ties, and preserves orientations. The result is certified AGAIN on
# the untouched rectangle/letters, which are the coordinates used for drawing.
function triangulate_wordmark(d)
    projected = Point[(x+y/1024, y) for (x, y) in d.points]
    length(unique(first.(projected))) == length(projected) || error("remaining x tie")
    triangles = triangulate(projected, d.offsets)
    certify(d, triangles)
    return triangles, projected
end

function svg_points(points)
    return join(("$(p[1]),$(11-p[2])" for p in points), ' ')
end

function write_svg(path, d, rings, triangles, width)
    open(path, "w") do io
        println(
            io,
            """<svg xmlns="http://www.w3.org/2000/svg" viewBox="-0.15 -0.15 $(width+0.3) 11.3" role="img" aria-labelledby="wordmark-title wordmark-desc">
<title id="wordmark-title">TRIAGE, cut out of a triangulated rectangle</title>
<desc id="wordmark-desc">Six stencil letters are polygon holes. Triage computed $(length(triangles)) triangles using $(length(d.points)) original vertices, with no added points.</desc>
<rect x="0" y="0" width="$width" height="11" fill="white"/>
<g class="mesh" stroke="blue" stroke-width="0.022" stroke-linejoin="round">""",
        )
        for (k, t) in enumerate(triangles)
            pale = 232+mod(7k, 19)
            println(
                io,
                "<polygon points=\"$(svg_points(d.points[collect(t)]))\" fill=\"rgb($pale,$pale,255)\"/>",
            )
        end
        println(
            io,
            "</g><g class=\"boundary\" fill=\"none\" stroke=\"black\" stroke-width=\"0.055\" stroke-linejoin=\"round\">",
        )
        for (r, ring) in enumerate(rings)
            fill = r == 1 ? "none" : "#daf4da"
            println(io, "<polygon points=\"$(svg_points(ring))\" fill=\"$fill\"/>")
        end
        println(io, "</g><g class=\"vertices\" fill=\"blue\" style=\"display:none\">")
        for (x, y) in d.points
            println(io, "<circle cx=\"$x\" cy=\"$(11-y)\" r=\"0.07\"/>")
        end
        println(io, "</g></svg>")
    end
end

function write_ipe(path, d, rings, triangles, width)
    # Page coordinates have the same 20:1 scale for both axes; no distortion.
    points = [BCG.Point(20x+4, 20y+4) for (x, y) in d.points]
    figure(path; keep_source = true, preview = false, width = 20width+8, height = 228) do f
        set_layer!(f, "triangulation")
        for (k, t) in enumerate(triangles)
            pale = (232+mod(7k, 19))/255
            draw_polygon!(
                f,
                points[collect(t)];
                stroke = :blue,
                fill = Symbol("$pale $pale 1"),
                pen = Symbol("0.44"),
            )
        end
        set_layer!(f, "boundary")
        for (r, ring) in enumerate(rings)
            boundary = [BCG.Point(20x+4, 20y+4) for (x, y) in ring]
            fill = r == 1 ? :none : Symbol("$(218/255) $(244/255) $(218/255)")
            draw_polygon!(f, boundary; stroke = :black, fill, pen = Symbol("1.1"))
        end
    end
end

function write_check_inputs(d, projected, triangles)
    # Scratch-only interchange files let the C++ executable independently
    # reproduce the mesh. No library outside this checkout triangulates it.
    scratch = ENV["TMPDIR"]
    open(joinpath(scratch, "wordmark-input.bin"), "w") do io
        write(io, UInt64(1), UInt64(length(d.offsets)-1))
        for r in 1:(length(d.offsets)-1)
            write(io, UInt64(d.offsets[r+1]-d.offsets[r]))
            for i in d.offsets[r]:(d.offsets[r+1]-1)
                write(io, projected[i][1], projected[i][2])
            end
        end
    end
    open(joinpath(scratch, "wordmark-julia.bin"), "w") do io
        write(io, UInt64(0x484f4c4544554d31), UInt64(1))
        write(io, UInt64(length(d.points)), UInt64(0), UInt64(length(triangles)))
        for t in triangles, i in t
            write(io, UInt32(i-1))
        end
    end
end

function main()
    root = normpath(joinpath(@__DIR__, "../.."))
    d, rings, width = domain()
    HoleInputs.check_domain(rings; distinct_x = false)
    triangles, projected = triangulate_wordmark(d)
    mkpath(joinpath(root, "figs"))
    mkpath(joinpath(root, "docs/assets"))
    write_svg(joinpath(root, "docs/assets/triage-wordmark.svg"), d, rings, triangles, width)
    write_ipe(joinpath(root, "figs/triage-wordmark.pdf"), d, rings, triangles, width)
    write_check_inputs(d, projected, triangles)
    println(
        "PASS: Triage computed $(length(triangles)) triangles, $(length(d.points)) original vertices, 6 holes; exact original-coordinate coverage.",
    )
end

main()
