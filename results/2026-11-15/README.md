# Release measurements, 2026-11-15

Measured code revision: `3133f424f5bf6cfadbe3d6fba2fab5ecf48bf68d`.
The equivalent published code revision is `e9a6a15f93b80dc051b078a38edbcd8187f8de15` (the inactive
CI template was relocated for publication). Later release changes affect orchestration/documentation only; exact measured
library and benchmark source hashes are in [source-sha256.txt](source-sha256.txt).

- [Summary CSV](timings/summary.csv), [environment](timings/environment.json).
- Raw twelve-sample CSV files are in [timings](timings/).
- [Exact coverage and C++/Julia agreement](full-cross-check.log).
- [ASan/UBSan plus full-vertex reference checks](sanitizers.log).
- [Corpus counts/hashes](records/corpora.csv) and [source archive metadata](records/geographic-downloads.csv).
- [Eligibility and selection ledgers](records/) (large CSVs are gzip compressed).

All figures are **medians of whole-batch measurements**, including geographic
batches. These differ from the research prototype's sum-of-per-case-medians
protocol. C++ uses twelve alternating-order rounds and common repetition counts
for Triage/Earcut. Julia uses twelve same-process warmed samples, measured
serially after C++; its GC is enabled. Output allocation and consumption are
included. Parsing, eligibility checks, normalization, and shearing are excluded.

C++ and Julia share the same input files. Earcut sees nonowning ring views over
the same flat coordinate array as C++ Triage. C++ output indices are UInt32;
Julia uses Int64 on the tested machine. No algorithm adds vertices.

The raw tile source has 119,680 polygons. All 111,539 single-ring candidates
are retained after preparation. Of 8,141 holed candidates, 5,799 satisfy the
strict domain contract. The named-fixture source has 59 files; 12 satisfy the
contract after preparation (including two single-ring fixtures). Unsupported
self-intersections, touching boundaries, point holes, etc. are recorded in the
ledgers, not counted as passing raw fixtures. All 36 synthetic, 19 standalone
geographic, and 10 holed geographic cases passed preparation and validation.

Sanitizers: GCC ASan/UBSan, RelWithDebInfo, `ASAN_OPTIONS=detect_leaks=0` in this
restricted environment. The corpus reference sweep covers n <= 4096; the
independent exact Julia check covers **all** 4,466,019 vertices, including the
1,180,959-vertex ring. Sanitizer timings are not included in performance data.

Reproduction from checkout root:

```sh
TRIAGE_CPU=2 JULIA_NUM_THREADS=1 ruby scripts/run.rb --full --geography
ASAN_OPTIONS=detect_leaks=0 ruby scripts/run.rb --full --geography --sanitize
```

Choose an available CPU. The commands print a temporary artifact directory;
copy results before its 24-hour cleanup. The source/hash ledger allows checking
that preparation reproduced the measured corpus. Geo archives, fixture data,
and mesh dumps are deliberately not included in this repository.
