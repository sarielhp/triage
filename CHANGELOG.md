# Changelog

## 0.1.0

Initial public release:

- Standalone header-only C++17 Triage library and CMake install/export target.
- Native Julia implementation of the same three algorithms.
- Original-vertex-only triangulation of trusted simple domains with holes.
- Filtered orientation predicates with exact rational fallback.
- Independent reference-sweep, exact coverage, cross-language, and sanitizer tests.
- Pinned downloads for Mapbox tiles/fixtures, GSHHG coastlines, and Census boundaries.
- Reproducible serial benchmarks and published raw samples.

This release targets valid prepared domains. It does not reproduce Earcut's
invalid-input recovery behavior or claim worst-case subquadratic running time.
