# Chain-based monotone triangulation without added vertices

`chain_monotone.hpp` combines the direct dual's monotone-chain representation
with original-vertex helper diagonals. It processes chain extrema, resolves
ordinary helper updates lazily, and triangulates compact boundary tapes.
It constructs no boundary-intersection coordinates and requires no vertex
removal pass. The public dispatcher uses small ear-cutting kernels before this core.

## Input and output

Input consists of original coordinates and ring offsets: a simple CCW exterior
and optionally disjoint simple CW holes strictly inside it. Rings have at least
three vertices and no repeated closing vertex. The existing bounded-coordinate
and normal-intermediate-arithmetic assumptions apply. Original x coordinates
must be distinct. The entry point checks cheap shape, coordinate, adjacent-x,
and extremum-x guards, but does not sort all vertices merely to validate global
x uniqueness or validate the domain topology. Those are caller preconditions.

`triangulate_chain_monotone<SearchMode>(points, offsets)` returns triangles
using only original IDs. It throws on a detected invalid condition; there is
no hidden Earcut or other triangulator fallback. The benchmark applies the
previous small kernels before calling it on larger inputs, as described below.

## Chain sweep

Scan the original rings once to identify local x extrema. Each consecutive
pair of extrema defines one monotone chain, stored as a signed range in the
original ring. The chain's traversal for searches always runs in increasing x,
regardless of its orientation along the boundary. Sort only the extrema.

An active interior interval stores its lower chain, upper chain, and helper
vertex. Each chain records the interval it bounds. An unsorted array contains
the live intervals.

- At a convex minimum, create an interval with the event as helper.
- At a reflex minimum, find the interval containing the event by scanning its
  lower boundaries. Connect the event to that interval's current helper, then
  split the interval into two.
- At a convex maximum, finish any pending merge connection and remove the
  terminating interval.
- At a reflex maximum, finish pending connections in the two incident
  intervals and join them. The event becomes the new pending merge helper.

The chain-to-interval links identify both neighbors of a merge, so merge
events need no active-set search. Only reflex minima search the status.
Comparisons use original-coordinate orientation predicates. Selecting the
nearest lower boundary requires no computed ray intersection coordinate.

## Lazy helper updates

Between extrema affecting an interval, its two boundary chains are fixed.
The ordinary full-vertex sweep would update its helper at each regular vertex
on either chain. With no pending merge, the result at the next event is simply
the most recent boundary vertex strictly before that event, or the interval's
last explicitly assigned helper if that is later.

A merge helper has one additional obligation. The first subsequent vertex on
either boundary would connect to it in the full sweep. At interval creation,
remember that first successor without moving either chain cursor into the
future. When the interval is next touched, emit that diagonal if the successor
has already been passed, then advance the helper normally. If the successor
is the current event, leave the helper pending for the event's normal handler.

This resolves the event retrospectively within an interval whose boundaries
have not changed. No additional priority queue or globally sorted ordinary
vertex events are needed. The test-only full-vertex reference independently
checks the resulting diagonal set; independent triangle certificates check
the subsequent face construction and triangulation.

## Persistent chain fingers

Each original chain owns one cursor; subdividing faces never resets it.
Three interchangeable searches are retained:

- `ChainSearch::Binary`: search the whole chain for each query.
- `ChainSearch::Walk`: advance the cursor until the edge spans the query x.
- `ChainSearch::Gallop`: check nearby edges, then exponentially bracket and
  binary-search a longer jump.

The edge convention is a strict predecessor: a query at an endpoint uses the
edge ending there. Search queries never move backward in x. Reading the next
vertex for a pending merge does not advance the cursor. Tests exercise forward
and reversed chains, wrapping ring ranges, repeated queries, endpoint queries,
and long jumps.

Walking costs O(n+Q) in total for Q chain queries: each original edge is passed
at most once. Galloping costs O(1+log(d+1)) per query advancing d edges and
has the same aggregate O(n+Q) bound. Neither bound removes the separate cost
of scanning active intervals to locate a split event.

## Compact face tapes

Mark the chain extrema and all diagonal endpoints, sort their original IDs,
and create circular boundary lists with records only at those marked vertices.
Each outgoing link represents either a whole original-boundary range or a
single diagonal. Insert a diagonal by splicing these lists and duplicating
its endpoint occurrences. Coordinates are never duplicated.

A vertex can acquire multiple occurrences after earlier cuts. Local interior
sector tests choose the appropriate occurrence for each new endpoint.
There is no general half-edge graph or sort of incident directions. The
integer sort orders marks along their original rings; sector tests resolve
only endpoint occurrences created by previous diagonals.

The optional `triangulate_bounded` entry point replaces both status scans and
endpoint-occurrence scans. It retains the chain sweep, helper rules, and
streaming monotone triangulation. See [the bounded strategy](bounded.md) for
its data structures and running-time argument. The default remains unchanged.

All extrema are marked, so each original range is x-monotone. Find the leftmost
and rightmost marked occurrences of each final face. A forward iterator and
a backward iterator traverse its two boundary chains directly in the original
coordinate array, crossing range/diagonal links as necessary. Merge these
streams by x and feed the standard monotone triangulation stack. No complete
face vertex array or sorted face event array is materialized.

## Costs and current limits

With m original chains and d partition diagonals, preparation sorts O(m)
events and O(m+d) marked IDs. Topology uses O(m+d) range/occurrence records,
plus the triangulation stack and output. The stack streams O(n+d) boundary
occurrences in total. The output has n+2h-2 triangles for h holes.

The sweep status remains an unsorted array; its scan cost is the sum of active
interval counts at split events. Endpoint sector selection scans duplicate
occurrences of an endpoint, so no universal linear bound is claimed for the
topology stage. `workspace_capacity_bytes` reports live vector capacities
excluding input and output; it is not a count of all allocation requests or
the memory used internally by exact-predicate fallback.

