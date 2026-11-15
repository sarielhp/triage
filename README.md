# Triage

**Created using Codex. This project is the result of vibe programming.**

[Project website](https://sarielhp.github.io/triage/) ·
[Download the release](https://github.com/sarielhp/triage/releases/latest)

[![TRIAGE as six letter-shaped holes in a rectangle, triangulated by Triage using only the original vertices.](docs/assets/triage-wordmark.svg)](https://sarielhp.github.io/triage/)

Triage triangulates simple polygons with holes using **only the original vertices**.
It includes a header-only C++17 library and a complete native Julia implementation.

Triage draws on ideas from theoretical computational geometry, including
monotone chains and implicit vertical decomposition, whose practical benefits
emerge on sufficiently large inputs. Such polygons arise in GIS applications,
for example in detailed country, state, and county boundaries.

On our large geographic benchmarks, C++ Triage was **3.8× faster for single-ring
boundaries and 6.8× faster for domains with holes** than
[Mapbox Earcut](https://github.com/mapbox/earcut.hpp). Performance varies by input;
see the [results and measurement conditions](#results), including smaller inputs
and the Julia implementation.

Both implementations use the same three-way dispatcher:

| Input | Algorithm |
|---|---|
| No holes, at most 64 vertices | Ear cutting with a live reflex-vertex mask |
| Holes, at most 32 total vertices | Ear cutting with lazy hole joining |
| Larger domains | Chain-monotone partition and triangulation |

The chain algorithm sorts x extrema, keeps a forward cursor on each monotone
boundary chain, and triangulates compact lists of original-boundary ranges.
It never constructs ray-intersection vertices. See [the algorithm](docs/algorithm.md).
There is no Earcut fallback. Earcut is included **only for comparison**.

An optional **`triangulate_bounded`** function is also available in C++ and
Julia. It uses a balanced sweep status and sorted endpoint directions to give
an **O(n + m log(m+1))** worst-case time bound, where n counts vertices and m
counts x-monotone chains. This is O(n log n) in general. The default algorithm
is unchanged; the bounded variant is a separate choice with additional overhead.
See [the algorithm, bound, and reproduction commands](docs/bounded.md).

## C++

Requires GCC or Clang with C++17 and Boost headers (1.65+). No compiled Boost
library is needed. Boost.Multiprecision supplies the exact predicate fallback.
The package is independent of the research repository and BasicCompGeometry.

```cpp
#include <triage/triage.hpp>

std::vector<triage::Point> points{
    {0,0}, {4,0}, {5,4}, {1,5},       // CCW exterior
    {1.5,1}, {2,2}, {3,1}            // CW hole
};
auto mesh = triage::triangulate(points, {0,4,7});
// mesh.triangles: vector<array<uint32_t,3>>, zero-based original indices.
```

For one ring, `triage::triangulate(points)` supplies its offsets.
Coordinates are `std::array<double,2>` stored inline in one flat vector.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel 2
ctest --test-dir build --output-on-failure
./build/triage_example
```

Use `add_subdirectory(triage)` and link `Triage::triage`, or install with
`cmake --install build --prefix /your/prefix` and use `find_package(Triage CONFIG REQUIRED)`.
The CMake target propagates C++17, Boost, and `-ffp-contract=off`.
For direct compilation use `-Iinclude -std=c++17 -ffp-contract=off` and your
Boost include directory. **Do not use `-ffast-math`**: filtered exact predicates
rely on ordinary floating-point evaluation.

## Julia

Requires Julia 1.10+. The library has no non-stdlib runtime dependencies.
It is a full Julia implementation, not a wrapper around the C++ code.

From this checkout:

```sh
julia --project=julia julia/test/runtests.jl
```

```julia
# Start with: julia --project=julia
using Triage
points = Point[(0,0), (4,0), (5,4), (1,5), (1.5,1), (2,2), (3,1)]
triangles = triangulate(points, [1,5,8])
# Vector{NTuple{3,Int}}, one-based original indices.
```

To install from GitHub into your own Julia project:

```julia
using Pkg
Pkg.add(url="https://github.com/sarielhp/triage", subdir="julia", rev="v0.1.0")
using Triage
```

Julia uses inline tuples for points, chains, intervals, and face records.
Its exact fallback uses `Rational{BigInt}`. It uses the same forward-walking
chain search as the C++ dispatcher; C++ additionally exposes binary/galloping
variants for experiments.

## Input format

Supply a simple counterclockwise exterior, followed by simple clockwise holes.
Holes must be disjoint and strictly inside the exterior. Ring offsets delimit
half-open ranges; omit repeated closing vertices. Every ring has at least three
vertices. Output has exactly **n + 2h − 2** positive-area triangles for n
vertices and h holes, all indexing the original coordinate array.

The chain path assumes globally distinct original x coordinates. Use finite
Float64 coordinates of magnitude below 1e12, with normal (non-underflowing)
intermediate determinant arithmetic. The fast API checks shape and some
invariants, **not full topology or global x uniqueness**. These are trusted-input
preconditions; exceptions are diagnostics, not a complete invalid-input validator.

The data-preparation scripts normalize orientation, remove repeated/straight
boundary points, apply a common shear `x += sqrt(2)/10*y`, and check simplicity,
strict hole containment, and x separation. All compared methods receive the
same prepared coordinates. Preparation is excluded from triangulation timings.
This release does not implement recovery for self-intersections, touching rings,
point holes, or the other malformed inputs accepted by Earcut's recovery logic.

The default active interval structure is an unsorted array. Split-event scans and
endpoint-occurrence searches can be quadratic on adversarial inputs; this is
an engineering implementation, not a claim of worst-case optimal triangulation.
Use `triangulate_bounded` for the optional O(n log n) worst-case alternative.

## Reproduce tests and timings

Requirements for the full workflow: C++ build requirements above, Julia 1.10+,
Ruby 3.1+, `curl`, `tar`, and `unzip`. Install QuickEnv once for the standalone
preparation/benchmark scripts:

```sh
julia -e 'using Pkg; Pkg.add("QuickEnv")'
ruby scripts/run.rb                         # generated C++ and Julia tests
ruby scripts/run.rb --sanitize              # C++ ASan + UBSan, Julia tests
ruby scripts/run.rb --full                  # download tiles/fixtures; prepare, check, time
TRIAGE_CPU=2 ruby scripts/run.rb --full --geography
```

`TRIAGE_CPU` is optional and requires Linux `taskset`. Choose an allowed CPU on
your machine. Run timing without other CPU-intensive jobs. Downloads are pinned
and SHA-256 checked; geography adds about 202 MB of compressed archives.
Every run prints its artifact directory under the system temporary directory,
`<user>/triage/verification/`. New runs sweep entries older than 24 hours;
copy results you want to keep. No administrator privileges are needed.

Each full run produces:

- `records/`: source provenance, corpus hashes, and acceptance/exclusion ledgers;
- `meshes/`: C++ and Julia outputs, required to match byte for byte;
- `timings/`: raw samples, environment metadata, and summary CSV;
- `build/`: runnable tests, example, and comparison executable.

Add `--sanitize` to a full run to check its corpora under ASan/UBSan; timings
are deliberately skipped in that mode. Leak detection may need disabling
(`ASAN_OPTIONS=detect_leaks=0`) in restricted debugging environments.

Individual stages can be rerun with `download.rb`, `prepare_all.jl`,
`check_corpora.rb`, and `time_corpora.rb`; each prints its argument contract.
The benchmark consumes results, includes output/workspace allocation, and
excludes input parsing. Both languages warm up in the measuring process.
Julia first compiles on a small polygon, then warms the full corpus before
collecting 12 samples. C++ alternates Triage/Earcut order over 12 rounds.
C++ and Julia runs are serial, not interleaved; cross-language numbers are
indicative rather than a paired experiment. Julia timings include GC costs.

## Results

Measured November 15, 2026 on an Intel Core i7-11700, Linux x86-64,
GCC 16.2.0 (`-O3 -DNDEBUG -ffp-contract=off`, without `-march=native`),
Boost 1.92.0, Julia 1.13.3, one thread, CPU 2. Each number is the median
time for the **whole corpus** after warmup; speedup is Earcut time / C++ Triage
time. Lower time is better. These are measurements of this package, not
numbers copied from the research implementation.

| Corpus | Polygons | Vertices | C++ Triage (ms) | Julia Triage (ms) | Earcut C++ (ms) | C++ speedup |
|---|---:|---:|---:|---:|---:|---:|
| Single-ring tiles | 111539 | 1089415 | 44.369 | 93.229 | 46.451 | 1.05× |
| Holed tiles | 5799 | 318887 | 37.170 | 58.035 | 44.270 | 1.19× |
| Large geographic rings | 19 | 2351828 | 224.932 | 272.317 | 855.080 | 3.80× |
| Geographic domains with holes | 10 | 244564 | 13.778 | 20.419 | 93.124 | 6.76× |
| Accepted named fixtures | 12 | 3977 | 0.665 | 2.220 | 0.651 | 0.98× |
| Synthetic holed domains | 36 | 457348 | 358.216 | 403.816 | 6386.496 | 17.83× |

C++ Triage wins both tile batches and the large geographic batches in this
run. It is about 2% slower on the accepted named fixtures. Julia remains
competitive on large geometry, but loses to Earcut on the small-tile batches.
The synthetic advantage should not be interpreted as representative of maps.
Differences of only a few percent can vary with hardware and run conditions;
raw min/max values are provided, and no statistical significance is claimed.

**Verification:** 117,415 prepared domains, 4,466,019 vertices: C++/Julia
outputs match byte for byte and pass independent exact coverage checks,
with zero added vertices. The ASan/UBSan run passed 118,708 generated and
corpus cases (the reference sweep limits corpus tests to 4,096 vertices);
23 generated equal-x variants were explicitly skipped. Julia's generated
package suite passed 867 assertions. Full-size geographic outputs were
checked separately by the exact corpus validator.

Source revisions, checksums, raw samples, eligibility ledgers, and logs:
[results/2026-11-15](results/2026-11-15/README.md).

### Optional bounded-time strategy

The separate `triangulate_bounded` API is available on `main` (it postdates
v0.1.0). A fresh comparison on the same machine and corpora gives these
**whole-corpus median timings in milliseconds**, with 12 samples per method:

| Corpus | C++ default (ms) | C++ bounded (ms) | Earcut C++ (ms) |
|---|---:|---:|---:|
| Single-ring tiles | 42.234 | 50.358 | 47.300 |
| Holed tiles | 38.014 | 67.405 | 44.722 |
| Large geographic rings | 231.396 | 401.063 | 853.812 |
| Geographic domains with holes | 14.188 | 26.312 | 92.216 |
| Accepted named fixtures | 0.717 | 0.774 | 0.646 |
| Synthetic holed domains | 359.133 | 134.625 | 6393.211 |

The bounded variant is slower on these geographic and tile batches, but
2.67× faster on the synthetic-hole batch. It is an optional worst-case
alternative; the default remains unchanged. See the
[full C++/Julia results, adversarial cases, and verification](results/2026-11-15-bounded/README.md)
and the [running-time argument](docs/bounded.md).


## Verification scope

C++ generated tests compare partition diagonals with an independent full-vertex
sweep, check binary/walking/galloping agreement, and exercise wrapping chains,
long jumps, collinear chains, holes, scales, rotations, and shape rejection.
Both language test suites check exact positive orientation and cancellation of
oriented triangle edges against the original boundary. These checks certify
geometric coverage, rather than just comparing total floating-point areas.
The full corpus check repeats this independently in Julia, and requires C++
and Julia to emit identical original-vertex triangles.

Passing the **prepared valid subset** of the Earcut fixtures is not the same
as passing Earcut's entire raw recovery suite. The ledgers preserve this
distinction, including unsupported cases; no exclusions depend on timing.

An [optional GitHub Actions template](ci/README.md) is included. Hosted test CI is
not enabled in this initial release because the publication token lacks the
`workflow` scope; the verification results above are local runs.

## Sources and licensing

Triage: MIT, copyright 2026 Sariel Har-Peled. See [LICENSE](LICENSE).
The vendored Earcut benchmark header and adapted tile decoder are ISC; see
[EARCUT-LICENSE](bench/EARCUT-LICENSE) and [data provenance](data/README.md).
Downloaded GSHHG data are LGPL-3.0-or-later; US Census TIGER/Line data are not
copyrighted. These datasets are not bundled in the source distribution.
