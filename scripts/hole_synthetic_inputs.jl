# Included by prepare_holes.jl; all coordinates are generated before timing.

function radial_ring(n, radius, center = (0.0, 0.0); dent = 0.0, phase = 0.173)
    return [
        begin
            angle = 2pi*i/n + phase
            r = radius * (1 - (iseven(i) ? dent : 0.0))
            (center[1] + r*cos(angle), center[2] + r*sin(angle))
        end for i in 0:(n-1)
    ]
end

function annulus(n; dent = 0.0)
    exterior = radial_ring(n ÷ 2, 10.0; phase = 0.173)
    interior = radial_ring(n - length(exterior), 3.0; dent, phase = 0.291)
    return [exterior, interior]
end

function perforated_grid(side, per_hole; dent = 0.0)
    rings = [radial_ring(max(64, side*4), 2.0side; phase = 0.173)]
    for y in 0:(side-1), x in 0:(side-1)
        center = (2.0x - side + 1, 2.0y - side + 1)
        phase = 0.213 + 0.017x + 0.011y
        push!(rings, radial_ring(per_hole, 0.55, center; dent, phase))
    end
    return rings
end

function regression_domains()
    exterior = [(0.0, 0.0), (20.0, 0.0), (20.0, 20.0), (0.0, 20.0)]
    first = [(2.0, 2.0), (7.0, 2.0), (7.0, 8.0), (2.0, 8.0)]
    second = [(11.0, 10.0), (17.0, 10.0), (17.0, 17.0), (11.0, 17.0)]
    concave = [(3.0, 3.0), (8.0, 3.0), (8.0, 8.0), (6.0, 8.0), (6.0, 5.0), (3.0, 5.0)]
    cases = [
        ("rectangular-two-holes", [exterior, first, second]),
        ("concave-hole", [exterior, concave]),
        ("triangular-hole", [exterior, [(3.0, 3.0), (9.0, 4.0), (5.0, 8.0)]]),
    ]
    variants = Tuple{String,Vector{Vector{Tuple{Float64,Float64}}}}[]
    for (name, rings) in cases, shift in 0:3
        push!(variants, ("$name-rotation-$shift", [circshift(r, shift) for r in rings]))
    end
    push!(variants, ("reordered-holes", [exterior, second, first]))
    for (scale, translation) in ((1e-6, 0.0), (1e6, 0.0), (1.0, 1e8))
        rings = [
            [(scale*x + translation, scale*y - translation) for (x, y) in ring] for
            ring in [exterior, first, second]
        ]
        push!(variants, ("scaled-$scale-translated-$translation", rings))
    end
    return variants
end

function synthetic_domains()
    cases = regression_domains()
    for n in (32, 128, 1024, 10000, 100000)
        push!(cases, ("annulus-$n", annulus(n)))
        push!(cases, ("concave-annulus-$n", annulus(n; dent = 0.35)))
    end
    for (side, per_hole) in ((2, 8), (4, 16), (8, 32), (16, 64), (32, 96))
        push!(cases, ("grid-$side-$per_hole", perforated_grid(side, per_hole)))
        push!(
            cases,
            ("concave-grid-$side-$per_hole", perforated_grid(side, per_hole; dent = 0.3)),
        )
    end
    return cases
end
