# Bring `predictive_bvh` to `DynamicBVH` capability parity via Lean proofs

## Resumption state (2026-04-14 — paused mid-Phase-1)

**Branch**: `vsk-multiplayer-fabric-4.7` · **HEAD**: `b7839a08ca7` (bench committed).

**Phase 0 — COMPLETE**. Benchmark landed at [tests/scene/test_predictive_bvh_bench.cpp](tests/scene/test_predictive_bvh_bench.cpp). Four paths (float pairs, R128 pairs, R128+Hilbert-prefix, DynamicBVH query) cross-validated with `CHECK(match_count ==)`. Measured at N=1024 on macOS arm64 dev build:

| Path                        | ns/pair (or /query)  |
| --------------------------- | -------------------- |
| float `AABB::intersects`    | 12.02                |
| R128 `aabb_overlaps`        | 14.31  (1.19× float) |
| R128 + Hilbert prefix prune | 5.65   (0.47× float) |
| DynamicBVH `aabb_query`     | 391.60 ns/query      |

**Decision gate outcome**: R128 naive is 1.19× float (well under the 2× threshold) and Hilbert-prefix R128 is *faster* than float. Proceed to Phase 1 with full confidence. Engine-wide-swap follow-up is viable and should be tracked after Phase 4.

**Two user overrides locked in** (reflected below):
1. Leaf identity is `EClassId` (Nat), not `void*`. Payloads look up through `SpatialEGraph`.
2. Internal-node keys use **Hilbert prefix compare** (shift-and-equal on 30-bit Hilbert codes), not float coordinate splits. This is what made R128 beat float in Phase 0 — the tree must preserve that property.

**Phases 1–4 — PENDING**.

### Cold-resume checklist

1. `git rev-parse HEAD` → expect `b7839a08ca7…`. If not, `git log --oneline -5` and reorient.
2. Rerun bench as regression check: `gscons && bin/godot.macos.editor.dev.arm64 --test --test-case="*PredictiveBVH*Bench*"`. Confirm the prefix-prune path still beats float. If macOS arm64 numbers drift >20%, investigate before proceeding.
3. Start Phase 1 in [thirdparty/predictive_bvh/PredictiveBVH/Spatial/](thirdparty/predictive_bvh/PredictiveBVH/Spatial/) — new file `Tree.lean`, sibling to existing `HilbertBroadphase.lean`.
4. Watch for: `Aabb` is 96 B (R128×6) — node struct cache behavior matters; keep `pbvh_node_t` at ≤128 B. Watch for `xing_received` / `xing_done` counters during the Phase 4 live test — they gate migration correctness.

## Context

Today [thirdparty/predictive_bvh/predictive_bvh.h](thirdparty/predictive_bvh/predictive_bvh.h) exposes only flat R128 helpers (`aabb_from_floats`, `aabb_union`, `aabb_overlaps`, `aabb_contains`) plus ghost-projection / Hilbert-partition primitives. [core/math/dynamic_bvh.h](core/math/dynamic_bvh.h) exposes a dynamic tree with `insert`, `update`, `remove`, `aabb_query`, `ray_query`, `convex_query`, and rebalancing. There is no Lean-proved tree at all — `PartitionNode` in [Primitives/Types.lean](thirdparty/predictive_bvh/PredictiveBVH/Primitives/Types.lean) is E-graph vocabulary, not a runtime traversable BVH. The user wants capability parity, proved in Lean, emitted to C, to eventually replace DynamicBVH inside `FabricZone` (and potentially wider).

Two user decisions override my earlier assumptions:

- **Leaf identity is an `EClassId` (Nat), not a `void* userdata`.** Pointers don't fit Lean's functional world; the EGraph already indexes leaves by EClassId in [Types.lean:91](thirdparty/predictive_bvh/PredictiveBVH/Primitives/Types.lean#L91).
- **The R128-is-slower-than-float claim is unverified.** My earlier 5–10× slowdown estimate was a priors-based guess, not measured. The plan must prove or disprove it empirically before committing to the proof work.

## Phase 0 — Settle the R128-vs-float perf question experimentally

Before building a proof stack to match DynamicBVH, confirm whether the R128 tree would actually lose the perf race at all. If R128 turns out to match or beat float, the engine-wide-swap story changes entirely.

### Benchmark

Add a new doctest file [tests/scene/test_predictive_bvh_bench.cpp](tests/scene/test_predictive_bvh_bench.cpp) (keeps [test_fabric_zone.cpp](tests/scene/test_fabric_zone.cpp) uncluttered). Use the existing `TEST_CASE`/`CHECK` harness and `OS::get_singleton()->get_ticks_usec()` for timing. No new third-party dependencies.

Workloads (N ∈ {1024, 8192, 65536}):

1. **AABB overlap microbench (compare-bound, no tree)** — generate N random AABBs in [−SIM_BOUND, SIM_BOUND]³. Call `aabb_overlaps` N×N times for the R128 path, `AABB::intersects` N×N times for the float path. Report µs/op and total walltime. This isolates the per-compare cost.
2. **AABB union microbench (mul-bound)** — same N, N-way pairwise union. R128 `aabb_union` (6 compares, no mul) vs Godot `AABB::merge_with`. Confirms compare-only cost parity.
3. **Tree lookup sanity check** — DynamicBVH only. Insert N random AABBs + run M=1024 random query AABBs. Establishes the _destination_ performance budget that a future predictive_bvh tree must come within a reasonable factor of (say 2×) to be a viable replacement.

Report table emitted to doctest output:

```
               | N=1024       | N=8192       | N=65536
R128 cmp/op    | xx ns        | xx ns        | xx ns
float cmp/op   | xx ns        | xx ns        | xx ns
DynamicBVH q/op| xx ns        | xx ns        | xx ns
```

### Decision gate

- **If R128 per-compare ≤ 2× float**: proceed to Phase 1 with confidence a Lean-proved R128 tree can be perf-competitive; update this plan's Phase 4 to include an engine-wide-swap option as a follow-up.
- **If R128 per-compare is 3–10× float**: proceed to Phase 1 anyway (FabricZone-local swap still wins vs its current O(N²) naive path) but explicitly scope out engine-wide adoption.
- **If R128 is catastrophic (>10× float) or float-build double precision erases the gap entirely**: stop. Revisit the premise with the user.

## Phase 1 — Lean tree abstraction keyed by EClassId

New file [thirdparty/predictive_bvh/PredictiveBVH/Spatial/Tree.lean](thirdparty/predictive_bvh/PredictiveBVH/Spatial/Tree.lean):

```lean
-- Array-of-nodes, index-based children (matches DynamicBVH's internal layout
-- and avoids ownership issues in a functional setting).
abbrev NodeId := Nat

inductive BVHNode where
  | leaf     (eclass : EClassId) (aabb : Aabb) (hilbert : UInt32)
  | internal (prefix : UInt32) (prefixDepth : UInt32)
             (bounds : Aabb) (left right : NodeId)

structure BVHTree where
  nodes : Array BVHNode
  root  : Option NodeId
  -- Free-list of holes from removed nodes; keeps `nodes` compact across
  -- insert/remove churn without re-indexing every live node.
  freeList : List NodeId
```

Leaf identity is `EClassId`, matching the existing `SpatialEGraph.classes` indirection in [Types.lean:105](thirdparty/predictive_bvh/PredictiveBVH/Primitives/Types.lean#L105). Callers retrieve any "userdata-like" payload (entity id, migration state, etc.) through the EGraph, exactly as the existing LBVH build already does — see [Protocol/Build.lean](thirdparty/predictive_bvh/PredictiveBVH/Protocol/Build.lean).

### Operations (Lean, purely functional)

- `insert  : BVHTree → EClassId → Aabb → BVHTree × NodeId`
- `remove  : BVHTree → NodeId → BVHTree`
- `update  : BVHTree → NodeId → Aabb → BVHTree` _(remove + insert compositionally, preserves id where refit fits parent)_
- `aabbQuery : BVHTree → Aabb → List EClassId`
- `rayQuery  : BVHTree → (origin dir : R128×R128×R128) → List EClassId` _(slab test, uses existing R128 helpers)_

### Invariants

- **Bound containment**: every `internal` node's `bounds` covers both children's bounds (`aabb_contains` = true transitively).
- **EClass uniqueness**: each EClassId appears in at most one leaf at any time.
- **FreeList disjointness**: `freeList` indices are exactly the positions whose node is logically dead; live nodes never reference them.

### Theorems (the proof content)

1. `insert_preserves_containment` — after insert, invariant holds.
2. `remove_preserves_containment` — after remove, invariant holds.
3. `aabbQuery_sound` — every EClassId returned has a leaf whose AABB overlaps the query AABB (no false positives).
4. `aabbQuery_complete` — every leaf whose AABB overlaps the query AABB is in the result (no false negatives). Composes directly with the existing `aabbOverlapsDec_false_implies_disjoint` from [HilbertBroadphase.lean:214](thirdparty/predictive_bvh/PredictiveBVH/Spatial/HilbertBroadphase.lean#L214).
5. `prefix_prune_sound` — when a query AABB's Hilbert code shares fewer than `prefixDepth` bits with an internal node's `prefix`, no leaf under that subtree can overlap the query. Reuses `hilbert_prune_sound` from [HilbertBroadphase.lean:223](thirdparty/predictive_bvh/PredictiveBVH/Spatial/HilbertBroadphase.lean#L223). This is what makes the traversal faster than coordinate splits (Phase 0 confirmed 2× speedup).
6. `ghost_aabbQuery_complete` — combined with [Formula.lean:47](thirdparty/predictive_bvh/PredictiveBVH/Formulas/Formula.lean#L47) (`expansion_contains_original`), querying with a ghost-expanded AABB returns every leaf an entity can reach in δ ticks. This is the proof payload that makes the tree more useful than DynamicBVH for the fabric migration path.

Skip `convex_query` for now — DynamicBVH exposes it but FabricZone doesn't consume it, and it needs convex-hull Minkowski reasoning that isn't part of the existing lemma stack. Add if a caller materializes.

## Phase 2 — Extend the codegen backend to emit stateful C

Current [Codegen/CodeGen.lean](thirdparty/predictive_bvh/PredictiveBVH/Codegen/CodeGen.lean) only routes `Expr Int → LowLevelProgram → generateCFn`. It can't emit structs, arrays, or loops. Tree ops are fundamentally stateful. Two paths:

**(Chosen)** Add a bespoke Lean-side string-templating pass in `Codegen/TreeC.lean` that consumes the `BVHTree` inductive and emits `pbvh_tree_*` helpers directly. Same style as [constantsC / emlC at CodeGen.lean:1140+](thirdparty/predictive_bvh/PredictiveBVH/Codegen/CodeGen.lean#L1140) — literal C strings assembled from Lean `String`, not routed through AmoLean. No e-graph optimization needed for tree traversal — the hot inner math (R128 compares) already goes through codegen'd kernels.

**(Rejected)** Extend `AmoLean.CodeGen` with imperative constructs (structs, loops, pointer IR). Scope creep: the AmoLean fork would gain a whole new IR tier. Reserve for a future plan if a second consumer needs it.

### Emission layout in `predictive_bvh.h`

```c
typedef uint32_t pbvh_eclass_id_t;
typedef uint32_t pbvh_node_id_t;     /* PBVH_NULL_NODE = 0xFFFFFFFF */

typedef struct pbvh_node {
    Aabb     bounds;             /* 96 bytes — R128×6 */
    uint32_t eclass_or_left;     /* leaf: eclass_id  | internal: left child id */
    uint32_t parent_or_right;    /* leaf: parent id  | internal: right child id (high bit = is_leaf) */
} pbvh_node_t;

typedef struct pbvh_tree {
    pbvh_node_t *nodes;
    uint32_t     capacity;
    uint32_t     count;
    uint32_t     root;
    uint32_t     free_head;      /* singly-linked free list via eclass_or_left */
} pbvh_tree_t;

/* All helpers are `static inline` and deterministic (no alloc inside the hot path). */
pbvh_node_id_t pbvh_tree_insert   (pbvh_tree_t*, pbvh_eclass_id_t, Aabb);
void           pbvh_tree_remove   (pbvh_tree_t*, pbvh_node_id_t);
void           pbvh_tree_update   (pbvh_tree_t*, pbvh_node_id_t, Aabb);
/* aabb_query: caller-provided callback receives eclass ids, returns 0 to continue. */
void           pbvh_tree_aabb_query(const pbvh_tree_t*, const Aabb*,
                                    int (*cb)(pbvh_eclass_id_t, void*), void*);
```

Storage allocation is caller-provided (`pbvh_tree_t::nodes` pointer + `capacity`) so the emitted code stays pure C, no malloc, and FabricZone can pre-size from `_zone_capacity` exactly as it does today for its slot array.

## Phase 3 — Wire up `FabricZone` (module-local swap only)

Replace the four `aabb_from_floats` call sites ([fabric_zone.cpp:502, 580, 607, 1478](modules/multiplayer_fabric/fabric_zone.cpp#L502)) + the `naive_pairs` diagnostic with a `pbvh_tree_t` that tracks active entity slots. Each slot's EClassId is `slot_index`. Existing `pbvh_eml_c*` bounds integrate naturally as ghost-query AABBs for the migration path.

Engine-wide swap of `DynamicBVH` is explicitly deferred until Phase 0 benchmarks back it up.

## Phase 4 — Verify parity

1. **Functional parity**: a new doctest iterates a mixed workload of inserts/updates/removes/queries under both DynamicBVH and `pbvh_tree_t`, asserts identical result sets (modulo ordering).
2. **Perf parity**: re-run Phase 0 benchmarks with `pbvh_tree_t` added; report DynamicBVH vs predictive-tree numbers side-by-side.
3. **Proof regeneration**: `cd thirdparty/predictive_bvh && lake build && lake exe bvh-codegen`. `predictive_bvh.h` gains the `pbvh_tree_*` block. **Never hand-edit the header.**
4. **Live 2-zone test** with the existing scenarios (`concert`, `choke_point`, `convoy`, `ragdoll`) at default 60 Hz — zones boot, DEV_ASSERTs hold, migrations complete. Reuse the exact harness from the prior rename commit.

## Critical files

- [thirdparty/predictive_bvh/PredictiveBVH/Spatial/Tree.lean](thirdparty/predictive_bvh/PredictiveBVH/Spatial/Tree.lean) — new: tree inductive + ops + theorems.
- [thirdparty/predictive_bvh/PredictiveBVH/Codegen/TreeC.lean](thirdparty/predictive_bvh/PredictiveBVH/Codegen/TreeC.lean) — new: string-templating C emission for the tree.
- [thirdparty/predictive_bvh/PredictiveBVH/Codegen/CodeGen.lean](thirdparty/predictive_bvh/PredictiveBVH/Codegen/CodeGen.lean) — splice `treeC` into `cFile` after `emlC`.
- [thirdparty/predictive_bvh/predictive_bvh.h](thirdparty/predictive_bvh/predictive_bvh.h) — regenerated only.
- [tests/scene/test_predictive_bvh_bench.cpp](tests/scene/test_predictive_bvh_bench.cpp) — new: Phase 0 benchmarks + Phase 4 parity test.
- [modules/multiplayer_fabric/fabric_zone.cpp](modules/multiplayer_fabric/fabric_zone.cpp) — consume `pbvh_tree_t` at the four existing `aabb_from_floats` sites.

## Functions/helpers reused (not redefined)

- `aabb_overlaps`, `aabb_union`, `aabb_contains`, `aabb_from_floats` at [predictive_bvh.h:159–183](thirdparty/predictive_bvh/predictive_bvh.h#L159).
- `aabbOverlapsDec_false_implies_disjoint`, `hilbert_prune_sound` at [HilbertBroadphase.lean:214–223](thirdparty/predictive_bvh/PredictiveBVH/Spatial/HilbertBroadphase.lean#L214) (feed into soundness proofs).
- `expansion_contains_original` at [Formula.lean:47](thirdparty/predictive_bvh/PredictiveBVH/Formulas/Formula.lean#L47) (ghost-query completeness).
- `EClass`, `EClassId`, `SpatialEGraph` at [Primitives/Types.lean:91–105](thirdparty/predictive_bvh/PredictiveBVH/Primitives/Types.lean#L91) — leaf identity and payload lookup.
- Doctest harness (`TEST_CASE`, `CHECK`) and `OS::get_ticks_usec()` timing — same pattern already in [tests/scene/test_fabric_zone.cpp](tests/scene/test_fabric_zone.cpp).

## Verification

1. `cd thirdparty/predictive_bvh && lake build` — Lean typechecks including new `Tree.lean` proofs. No `sorry`.
2. `lake exe bvh-codegen` — regenerates `predictive_bvh.h`. `grep -c pbvh_tree_ thirdparty/predictive_bvh/predictive_bvh.h` ≥ 4.
3. `gscons` — Godot links cleanly.
4. `bin/godot.macos.editor.dev.arm64 --test --test-case="*PredictiveBVH*"` — runs Phase 0 + Phase 4 benchmarks and parity tests. Report walltime + µs/op per workload.
5. Live 2-zone test at 60 Hz for each scenario; confirm no regressions vs the post-rename baseline (zones reach drain at tick 1200 without crash, no DEV_ASSERT fires).

## Not in scope this iteration

- `convex_query` parity (no consumer in the fabric module).
- Engine-wide DynamicBVH swap — gated on Phase 0 decision; if pursued, separate plan.
- SAH rebalancing rotations — the initial insert uses incremental SAH on the new leaf only; rotation-based rebalance is a perf optimization, not a correctness requirement, and can ride on top once Phase 0 numbers justify it.
- Python / ML integration — still strictly Lean→C via `bvh-codegen`.
