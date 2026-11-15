# Optional bounded-time strategy: measurements and verification

Measured November 15, 2026 on an Intel Core i7-11700, Linux x86-64, CPU 2.
C++: GCC 16.2.0, Boost 1.92.0, `-O3 -DNDEBUG -ffp-contract=off`, no
`-march=native`. Julia: 1.13.3. Algorithms are single-threaded. Both languages
warm up before measurement in the same process. Each table entry is a median
over 12 samples; times include workspace/output allocation and exclude parsing,
preparation, compilation, certification, and instrumentation. Julia includes GC.
C++ rotates all three methods; Julia alternates its two methods. Languages and
corpora run serially, with no concurrent verification or compilation jobs.

The implementation is commit `bbc5025`. The ordinary-corpus run began before
that commit was made; its environment file records the earlier HEAD and the
SHA256 of every implementation, test, and benchmark source. Those source hashes
were checked against the committed implementation. Inputs and source hashes,
raw samples, and per-method min/max values accompany both runs below. The
benchmark-only Earcut header is unchanged from the original package comparison.
Commit `3278a5c` adds only benchmark controls and an Earcut certificate command;
it is used for the resumed adversarial measurements. The triangulators are
unchanged between those runs.

## Existing corpora

These are exactly the same 117,415 prepared domains and 4,466,019 vertices as
the original comparison, with matching input SHA256 values. The
[original eligibility ledgers and provenance](../2026-11-15/README.md) apply.
Every value is **milliseconds for the whole corpus**, not per polygon.

| Corpus | C++ default (ms) | C++ bounded (ms) | Earcut C++ (ms) | Julia default (ms) | Julia bounded (ms) |
|---|---:|---:|---:|---:|---:|
| Single-ring tiles | 42.234 | 50.358 | 47.300 | 87.432 | 99.527 |
| Holed tiles | 38.014 | 67.405 | 44.722 | 58.443 | 88.059 |
| Large geographic rings | 231.396 | 401.063 | 853.812 | 269.872 | 464.558 |
| Geographic domains with holes | 14.188 | 26.312 | 92.216 | 19.748 | 41.052 |
| Accepted named fixtures | 0.717 | 0.774 | 0.646 | 1.964 | 1.533 |
| Synthetic holed domains | 359.133 | 134.625 | 6393.211 | 401.821 | 153.774 |

On geographic inputs the C++ bounded variant is 1.73–1.85× slower than the
default. It is also slower on the tile batches and fixtures, but 2.67× faster
on the synthetic-hole batch. Julia shows the same geographic slowdown and
synthetic speedup, with a different result on the small fixture batch. Small
differences and GC-sensitive timings should not be treated as statistically
established advantages. See [raw samples and summary](corpora/summary.csv).

## Adversarial inputs

Each row is one polygonal domain. All coordinates use an exact dyadic shear
to resolve x ties. The combs create many active intervals even with zero holes;
the stacked-hole family creates many active intervals in a holed domain.
These are deliberately difficult inputs, not a representative GIS sample.

| Domain | Vertices | C++ default (ms) | C++ bounded (ms) | Earcut C++ (ms) | Julia default (ms) | Julia bounded (ms) |
|---|---:|---:|---:|---:|---:|---:|
| Comb, no holes | 260 | 0.215 | 0.046 | 0.008 | 0.627 | 0.060 |
| Comb, no holes | 1028 | 1.144 | 0.278 | 0.033 | 2.792 | 0.294 |
| Comb, no holes | 4100 | 8.706 | 1.468 | 0.142 | 15.214 | 1.393 |
| Comb, no holes | 16388 | 100.671 | 7.216 | 0.612 | 126.457 | 7.754 |
| Comb, no holes | 65540 | 1452.159 | 36.163 | 2.774 | 1554.311 | 33.556 |
| 64 stacked holes | 260 | 0.572 | 0.240 | 0.667 | 1.787 | 0.574 |
| 256 stacked holes | 1028 | 2.576 | 1.189 | 39.070 | 7.356 | 3.185 |
| 1024 stacked holes | 4100 | 14.105 | 5.260 | 2691.557 | 33.136 | 13.349 |
| 4096 stacked holes | 16388 | 110.292 | 22.852 | — | 184.916 | 46.470 |
| 16384 stacked holes | 65540 | 1310.895 | 100.662 | — | 1675.294 | 203.597 |

At 65,540 vertices, the bounded C++ variant is 40.16× faster than the default
on the comb and 13.02× faster on the stacked-hole domain. Julia gains 46.32×
and 8.23×, respectively. Earcut nevertheless beats both strategies on every
comb in this experiment. Conversely, its time rises sharply on the stacked
holes: 2,691.557 ms already at 1,024 holes.

The dashes mean **not measured**, not a zero or an inferred time. The initial
16,384-hole Earcut warmup was interrupted; its incomplete output is excluded.
The 4,096-hole Earcut run was omitted after observing the smaller case's cost.
Both large cases were then measured with `--triage-only`, retaining all 12
samples for each Triage implementation. There is no timing extrapolation.

[Combined summary](adversarial/summary.csv) and raw samples:
[initial complete comparisons](adversarial/initial/),
[remaining small-hole comparisons](adversarial/small/),
[large Triage-only comparisons](adversarial/large/). Each directory includes
its environment and source hashes. Every reported adversarial Earcut result
also passes the independent exact coverage certificate.

## Verification

- Both bounded implementations pass independent exact triangle-orientation and
  oriented-boundary coverage checks on all 117,415 existing domains and all ten
  adversarial domains. Their outputs are byte-identical between languages, with
  zero added vertices. Triangle order can differ from the default strategy.
- Both default implementations still reproduce the original published meshes
  byte for byte on every existing domain.
- C++ ASan/UBSan: 118,708 generated and corpus cases pass; the independent
  full-vertex reference is applied to corpus polygons up to 4,096 vertices.
  The generated tests also cover high-degree diagonal endpoints with both
  diagonal insertion orders. Twenty-three equal-x generated variants are
  explicitly skipped, as in the original suite.
- Julia: 2,157 geometric/API assertions pass, plus 265,224 assertions checking
  AVL ordering, heights, and balance throughout random insertion/deletion
  sequences. The geometric tests compare the two sweep diagonal sequences.
- Full-size geographic and adversarial meshes are certified separately from
  the size-limited reference suite.
- Ruby syntax, structural audit, and RuboCop checks pass for the changed runner
  scripts; Julia sources are formatted with the package's JuliaFormatter config.

LeakSanitizer cannot run under this execution environment's tracing. The
successful sanitizer run uses `ASAN_OPTIONS=detect_leaks=0`; AddressSanitizer
and UndefinedBehaviorSanitizer remain enabled. No leak-check result is claimed.

Logs: [existing corpus coverage](coverage.log),
[adversarial coverage](adversarial-coverage.log),
[unchanged default output](default-regression.log),
[adversarial default/Earcut coverage](adversarial-baselines.log),
[ASan/UBSan](sanitize-no-leaks.log).

## Reproduction

See [the bounded strategy](../../docs/bounded.md) for the API, bound, and full
download/prepare/check/time commands. Add `--strategies` to the full runner
to include the optional method, or reuse prepared inputs with the individual
scripts. The adversarial generator writes ten separate single-domain corpora
so that growth with size is visible rather than hidden in a batch total.
