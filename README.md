# Triage

Triage triangulates simple polygons with holes using **only the original vertices**.
It includes a header-only C++17 library and a complete native Julia implementation.
Both implement the same three-way dispatcher:

| Input | Algorithm |
|---|---|
| No holes, at most 64 vertices | Ear cutting with a live reflex-vertex mask |
| Holes, at most 32 total vertices | Ear cutting with lazy hole joining |
| Larger domains | Chain-monotone partition and triangulation |

The chain algorithm sorts x extrema, keeps a forward cursor on each monotone
boundary chain, and triangulates compact lists of original-boundary ranges.
It never constructs ray-intersection vertices. See [the algorithm](docs/algorithm.md).
There is no Earcut fallback. Earcut is included **only for comparison**.

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

## Input contract

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

The active interval structure is an unsorted array. Split-event scans and
endpoint-occurrence searches can be quadratic on adversarial inputs; this is
an engineering implementation, not a claim of worst-case optimal triangulation.

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

Individual stages can be rerun with `download.rb`, `prepare_all.jl`,
`check_corpora.rb`, and `time_corpora.rb`; each prints its argument contract.
The benchmark consumes results, includes output/workspace allocation, and
excludes input parsing. Both languages warm up in the measuring process.
Julia first compiles on a small polygon, then warms the full corpus before
collecting 12 samples. C++ alternates Triage/Earcut order over 12 rounds.
C++ and Julia runs are serial, not interleaved; cross-language numbers are
indicative rather than a paired experiment. Julia timings include GC costs.

## Results

Release measurements and exact verification records will be inserted here
before publication.

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

## Sources and licensing

Triage: MIT, copyright 2026 Sariel Har-Peled. See [LICENSE](LICENSE).
The vendored Earcut benchmark header and adapted tile decoder are ISC; see
[EARCUT-LICENSE](bench/EARCUT-LICENSE) and [data provenance](data/README.md).
Downloaded GSHHG data are LGPL-3.0-or-later; US Census TIGER/Line data are not
copyrighted. These datasets are not bundled in the source distribution.
