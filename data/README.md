# Benchmark sources

All methods receive the same prepared domains. Selection and normalization
happen before timing. Every candidate has an entry in an eligibility ledger.
Source archives and prepared data are downloaded/generated, not committed.

| Source | Revision | Use |
|---|---|---|
| [Mapbox earcut.hpp](https://github.com/mapbox/earcut.hpp/tree/2fbafada15dbe5350c606426e17111b91a964e55) | 2fbafada15dbe5350c606426e17111b91a964e55 | Unmodified ISC benchmark header |
| [Mapbox earcut JS](https://github.com/mapbox/earcut/tree/9e70986eb94054c621c926888dd05bc26bffb902) | 3.2.4, 9e70986eb94054c621c926888dd05bc26bffb902 | Tile corpus and named regression fixtures |
| [GSHHG](https://www.soest.hawaii.edu/pwessel/gshhg/) | 2.3.7 | Large coastline boundaries and holes |
| [Census TIGER/Line](https://www.census.gov/geographies/mapping-files/time-series/geo/tiger-line-file.html) | 2026 state and county shapefiles | Administrative boundaries and holes |

The vendored Earcut header SHA-256 is
`29091c0d7af22a2f985f5ebd9aedb1f1b056fe099d1d31395c393c5f1ecb8c52`.
Pinned fixture and geographic archive hashes are in `scripts/download.rb` and
`scripts/geographic/fetch.rb`. The tile fixture hash is checked again during
preparation. The tile decoder is adapted from Mapbox's ISC-licensed decoder;
its attribution/license is retained in `bench/EARCUT-LICENSE`.

Geographic extraction enumerates individual rings, chooses size strata before
timing, unwraps longitude without adding vertices, and records original and
prepared hashes. Large standalone rings represent individual boundaries, not
complete multipolygons. The separate holed geographic corpus contains entire
selected connected components with their interior holes. Coordinates are
planar test geometry, not a claim about geodesic triangulation.

GSHHG terms: [LICENSE](GSHHG-LICENSE.txt), [LGPL text](GSHHG-COPYING.LESSERv3).
Census attribution: US Census Bureau, TIGER/Line Shapefiles, 2026.
