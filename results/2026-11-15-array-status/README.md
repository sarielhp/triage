# BCG-style array status inside Triage's bounded sweep

The C++ `triangulate_bounded` API now uses the array AVL backend. It wins on
all six existing corpora and all ten adversarial inputs in this experiment.
The default `triangulate` algorithm is unchanged. The Julia array backend is
implemented and tested, but remains experimental: its results are mixed, so
Julia's public bounded API retains the recursive AVL backend.

This borrows the preallocated tree, parent links, iterative balancing, and
deletion-by-handle design from
[BasicCompGeometry 0.6.1](https://github.com/sarielhp/BasicCompGeometry.jl/blob/29e5ab0f676430ca70548fd5ba2a2a357f6ec0ad/src/SweepTriangulation.jl),
under the same MIT license. It is not a replacement by BCG's full triangulator.
Triage keeps its compressed chains, forward cursors, lazy helper updates,
sorted face construction, exact-filtered predicates, and small-polygon kernels.
The O(n + m log(m+1)) bound is unchanged. Six arrays are allocated for at most
2m inserted interval records; deletion performs no geometric comparisons.

## Results

**Milliseconds for a whole corpus**, or for one domain in the final two rows.
Each entry is a median of 12 samples. These compare bounded implementations;
they do not compare against default Triage or Earcut.

| Input | C++ previous (ms) | C++ array (ms) | Julia previous (ms) | Julia array (ms) |
|---|---:|---:|---:|---:|
| Single-ring tiles | 50.241 | 48.502 | 98.129 | 98.124 |
| Holed tiles | 67.414 | 60.504 | 87.177 | 86.074 |
| Large geographic rings | 403.741 | 368.580 | 473.794 | 457.014 |
| Geographic domains with holes | 28.270 | 25.410 | 33.645 | 39.279 |
| Named fixtures | 0.764 | 0.691 | 1.358 | 1.501 |
| Synthetic holed domains | 136.730 | 115.526 | 149.715 | 129.852 |
| Comb: 65,540 vertices | 36.306 | 22.270 | 35.143 | 30.851 |
| 16,384 holes: 65,540 vertices | 101.996 | 86.773 | 199.214 | 189.360 |

The C++ improvement is about 9% less time on large geographic rings, 10% on
geographic domains with holes, 16% on synthetic holed domains, and 39% on the
largest comb. Small single-ring polygons use the same ear cutter in both
variants, so the tile-batch difference comes from its larger polygons.

Julia improves on the combs and synthetic-hole batch, but its fixture and
geographic-hole medians regress. Several Julia ranges overlap substantially;
we do not interpret small median differences as established wins. GC is
included. There is no size-based dispatch tuned to these results.

Full raw samples, minimum/maximum values, input hashes, and environment records:
[existing corpora](corpora/summary.csv) and
[all ten adversarial cases](adversarial/summary.csv).
In these historical CSVs, `triage-bounded-cpp` means the **previous std::set
backend**, and `triage-array-cpp` is the newly adopted backend. A rerun now labels
the former `triage-legacy-bounded-cpp` to distinguish it from the public API.
Julia's `triage-bounded-julia` still identifies its public recursive backend.

## Measurement conditions

November 15, 2026; Intel Core i7-11700, CPU 2, Linux x86-64; GCC 16.2.0,
Boost 1.92.0, C++17, `-O3 -DNDEBUG -ffp-contract=off`, no `-march=native`;
Julia 1.13.3, one compute thread and one GC thread under CPU affinity.
Workspace/output allocation is timed; input loading, compilation, certification,
and instrumentation are excluded. Both methods warm up in the same process,
then alternate order across 12 samples. C++ and Julia run serially, with no
concurrent verification or compilation jobs.

The six original corpora contain 117,415 domains and 4,466,019 vertices. They
are unchanged from the [original published comparison](../2026-11-15/README.md).
Ten adversarial inputs add five combs and five stacked-hole domains. No Earcut
runs or timing extrapolations are involved in this experiment.

Environment files record parent HEAD `6535777` and working-source hashes at
the start of each run. Measurements preceded adoption in the public C++ API.
Subsequent changes select the measured array backend, retain an explicit legacy
benchmark selector, format Julia, and simplify an error message; the measured
valid-input algorithms are unchanged. A partially executed preliminary run
with an incorrectly wired C++ benchmark selector was discarded in full and is
not included here.

## Verification

- Independent exact orientation and oriented-boundary coverage certificates pass
  for both array implementations on all **117,425 domains**, with no new vertices.
- C++ and Julia array meshes agree byte for byte on every domain. They also
  match the previously certified bounded meshes byte for byte.
- Generated tests compare partition diagonals with an independent full-vertex
  reference. C++ tests also compare legacy and array triangle sequences.
- Julia passes 3,015 geometric/API assertions, 265,224 legacy AVL assertions,
  and 529,420 array AVL assertions, including ordering, balance, height,
  parent links, and interval-to-node handles after repeated insertions/deletions.
- C++ tests compare all predecessor queries against `std::set` after every
  operation in repeated randomized insertion/deletion cycles.
- ASan/UBSan passes 118,712 generated and corpus cases (23 equal-x variants
  skipped). The independent full-vertex reference is limited to corpus polygons
  of at most 4,096 vertices; full-size meshes are covered by the separate exact
  corpus certificate. LeakSanitizer is disabled because of the environment's
  tracing restriction; no leak-check result is claimed.
- Both default APIs still reproduce the originally published corpus meshes
  byte for byte. Ruby syntax/audit/RuboCop and Julia formatting checks pass.

Logs: [exact corpus coverage](coverage.log),
[agreement with previous bounded meshes](bounded-regression.log),
[Julia tests](julia-tests.log), [ASan/UBSan](sanitize.log),
[unchanged default outputs](default-regression.log).

## Reproduction

Prepare corpora with the existing download/preparation scripts, and build in
Release mode as described in the main README. Then run:

```sh
TRIAGE_CPU=2 ruby scripts/time_corpora.rb BUILD INPUTS TIMINGS --status
ruby scripts/check_corpora.rb BUILD INPUTS MESHES --array
julia scripts/prepare_adversarial.jl ADVERSARIAL_INPUTS
TRIAGE_CPU=2 ruby scripts/time_corpora.rb BUILD ADVERSARIAL_INPUTS ADVERSARIAL_TIMINGS --status
ruby scripts/check_corpora.rb BUILD ADVERSARIAL_INPUTS ADVERSARIAL_MESHES --array
```

Use project temporary directories for generated inputs and outputs. Both status
implementations are retained for reproduction; there is no dependency on an
installed BasicCompGeometry package.
