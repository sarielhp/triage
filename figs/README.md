# Triage wordmark

A rectangle with six stencil letter-shaped holes, triangulated by Triage:
89 original vertices, 99 triangles, and no added vertices. R and A have small
stencil openings so each letter is a simple hole without an isolated island.
The letter-shaped holes are shaded light green.

- [SVG for the README/site](../docs/assets/triage-wordmark.svg)
- [Vector PDF](triage-wordmark.pdf) and [editable Ipe](triage-wordmark.ipe)
- [Julia generator](../julia/figures/triage-wordmark.jl)

Regenerate from the repository root:

```sh
ruby scripts/draw_wordmark.rb
ruby scripts/build_site.rb
```

The generator uses QuickEnv and BasicCompGeometry's IpeDraw for drawing/export.
**Triage's own native Julia implementation computes the triangulation.**
It checks simplicity and hole containment, then independently certifies exact
positive triangle orientation and boundary cancellation in the original geometry.
C++ Triage was also run on the same input and produced byte-identical triangles.

Version 0.1.0 requires distinct x coordinates on its chain path. The generator
applies the exact dyadic shear `(x,y) -> (x+y/1024,y)` before triangulation;
all coordinates in this drawing are dyadic and the shear introduces no rounding.
The returned indices are verified and drawn on the **unchanged rectangular
layout**. No vertices are added, no hole is filled, and no different triangulator
is used. This preparation does not remove the library's current equal-x limitation.

The PDF and Ipe are exported together through IpeDraw. The SVG renders the same
verified triangles, boundary paths, colors, and line widths for browser use.
Temporary interchange files and Ipe caches are kept under the project temp tree.
