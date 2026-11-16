# Optional strategy with a worst-case bound

`triangulate_bounded` provides an alternative to the default practical strategy
in both C++ and Julia. It has an **O(n + m log(m+1)) time bound and O(n) space
bound**, where n is the total number of input vertices and m is the number of
x-monotone boundary chains across all rings. In particular, its time is
O(n log n). The number of chains is not the number of holes: a simple polygon
can have Θ(n) chains.

The default `triangulate` function does not select this strategy automatically.
Both APIs use the same fixed-size ear-cutting kernels for small inputs. On
larger inputs, the bounded strategy replaces two potentially quadratic searches.
It adds no vertices and has the same geometric and numerical input assumptions.

See [measured C++/Julia performance and verification](../results/2026-11-15-bounded/README.md).

## Balanced sweep status

The sweep still processes only local x extrema and resolves helper updates
lazily. Active intervals are ordered by their lower boundary chains. A split
event locates the predecessor of its vertex in this order. Insertion, deletion,
and predecessor lookup take O(log(m+1)) comparisons each.

C++ uses a preallocated AVL tree, adapted from BasicCompGeometry's sweep-tree
design. Parent links support iterative balancing, and interval-to-node handles
allow deletion without geometric comparisons. At most two intervals are created
per extremum, so allocating space for 2m records covers the whole sweep; slots
need not be recycled. Julia retains its recursive AVL with inline array records:
the new array backend is implemented there too, but its timings were mixed.
Neither uses random priorities or offers only an expected-time bound.
Comparisons use orientation predicates on original edges, with no division or
computed ray-intersection coordinates. Two live lower chains cannot cross,
so their relative order remains unchanged as the sweep advances. Removal and
insertion handle changes at extrema explicitly.

Every chain retains its forward cursor, including chains queried while
inserting or deleting an interval. Queries occur at nondecreasing x coordinates.
With Q comparisons and helper queries, all cursor advancement costs O(n+Q).
The balanced status makes Q = O(m log(m+1)).

## Sorted endpoint directions

A balanced status alone is insufficient: the default face builder can scan
many occurrences of the same diagonal endpoint. The bounded strategy instead
builds the planar adjacency once all partition diagonals are known.

Mark extrema and diagonal endpoints. Create two directed halfedges for each
original-boundary range and each partition diagonal, keeping coordinates in
the original input array. Group outgoing halfedges by their original vertex
ID and sort their directions counterclockwise, using a half-plane test and
exact-filtered orientation comparisons. For a boundary range, use the direction
to its **adjacent original vertex**, not the chord joining its marked endpoints:
the range can bend between its ends.

At the destination of a directed halfedge, its successor around the face on
the left is the clockwise predecessor of its twin. Reverse original-boundary
halfedges bound the exterior or the holes, so those faces are excluded. The
remaining cycles are the same monotone faces as the default partition; the
existing boundary iterators and stack triangulate them. Triangle ordering may
differ between strategies.

## Running time and space

1. Scan all rings in O(n) time. There are m extrema and m chains.
2. Sort extrema in O(m log(m+1)) time. Each event performs a constant number
   of tree operations and helper updates, so the sweep costs
   O(n + m log(m+1)), including cursor advancement.
3. Each event emits at most a constant number of diagonals; hence d = O(m).
   There are O(m+d) marked vertices and halfedges. Sorting marks and outgoing
   directions costs O(m log(m+1)); linking faces is linear in their size.
4. Across all faces, the original boundary edges occur once and each diagonal
   occurs twice. Their streamed triangulation therefore costs O(n+d) = O(n+m).

The total is O(n + m log(m+1)), with O(m) sweep/topology storage and O(n)
worst-case stack/output storage. These are arithmetic-operation bounds for
valid inputs under the documented input assumptions. Orientation fallback
operates on the fixed-precision Float64 input coordinates; no constructed
coordinates accumulate additional precision.

The default strategy has the weaker O(n+m²) upper bound. Its contiguous status
array and incremental face construction can nevertheless be faster in practice.
The bounded variant is an explicit alternative, not a claim that balanced
trees improve every benchmark.

## Usage and reproduction

This API is available on `main`; the earlier v0.1.0 release predates it.

```cpp
auto mesh = triage::triangulate_bounded(points, offsets);
```

```julia
triangles = triangulate_bounded(points, offsets)
```

Run both strategies and Earcut on downloaded/prepared inputs:

```sh
ruby scripts/run.rb --full --geography --strategies
```

With an existing build and prepared corpora, avoid downloading again:

```sh
ruby scripts/check_corpora.rb BUILD INPUTS OUTPUT_MESHES --bounded
ruby scripts/time_corpora.rb BUILD INPUTS OUTPUT_TIMINGS --strategies
julia scripts/prepare_adversarial.jl OUTPUT_ADVERSARIAL_INPUTS
ruby scripts/check_corpora.rb BUILD OUTPUT_ADVERSARIAL_INPUTS OUTPUT_ADVERSARIAL_MESHES --bounded
ruby scripts/time_corpora.rb BUILD OUTPUT_ADVERSARIAL_INPUTS OUTPUT_ADVERSARIAL_TIMINGS --triage-only
```

Earcut is exceptionally slow on the largest stacked-hole cases, so the last
command compares only the two Triage strategies in both languages. To also
measure Earcut on a selected subset of inputs, use `--strategies` instead.
`triage_bench validate-earcut INPUT unused` checks Earcut's output with the
same independent exact coverage certificate.

Use separate output directories for default/bounded meshes. Input preparation,
compilation, exact certification, and instrumentation are outside timed runs.
Julia warms up in the same process before timing. Each comparison uses 12
samples and rotates the order of the methods. C++ and Julia run serially.

Tests compare both sweep strategies with the independent full-vertex reference,
check high-degree diagonal endpoints, check Julia AVL balance and ordering
after insertion/deletion, and independently certify triangle orientation and
boundary coverage. The corpus checker also requires byte-identical bounded
outputs between C++ and Julia. The adversarial inputs include simple combs
with no holes and rectangles with many stacked holes, from 260 to 65,540
vertices, with exact dyadic shears to resolve x-coordinate ties.

`ChainMonotoneStats::workspace_capacity_bytes` remains a sum of retained vector
capacities, not peak memory. It includes the new AVL arrays, but excludes
the legacy `std::set` allocations and temporary endpoint-sorting arrays.

## Comparing the status implementations

The [array-status experiment](../results/2026-11-15-array-status/README.md)
compares the previous and new bounded backends while retaining the same chains,
helper updates, sorted face topology, predicates, and small-input kernels.
The previous C++ `std::set` and Julia recursive AVL remain available internally
for reproduction. `triangulate` continues to use the original default strategy.

```sh
TRIAGE_CPU=2 ruby scripts/time_corpora.rb BUILD INPUTS STATUS_TIMINGS --status
ruby scripts/check_corpora.rb BUILD INPUTS ARRAY_MESHES --array
```

`--status` compares legacy bounded versus array bounded in each language;
it does not run Earcut. `--array` certifies the array backend in both languages.
The Julia candidate can also be exercised internally with
`Triage.triangulate_dispatch(points, offsets, Val(true), Val(true))`.
This is an experimental interface, not a second public dispatch policy.
