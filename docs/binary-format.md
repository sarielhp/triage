# Corpus and mesh interchange

These test formats require a little-endian machine and IEEE binary64 floats.
They are internal reproducibility formats, not a general untrusted-file API.

Corpus: UInt64 polygon count, then for each polygon UInt64 ring count, then
for each ring UInt64 vertex count followed by Float64 x/y pairs. Coordinates
are flattened in ring order. Exterior is CCW; holes are CW.

Mesh: UInt64 magic `0x484f4c4544554d31`, UInt64 polygon count, then per polygon:
UInt64 original vertex count, UInt64 zero (added-vertex count), UInt64 triangle
count, then three zero-based UInt32 indices per triangle. Julia converts its
one-based indices at this boundary. Equal files therefore mean equal ordered
triangles in both languages, without coordinate rounding or serialization noise.
