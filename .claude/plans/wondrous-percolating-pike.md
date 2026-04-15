# Zero hardcoded C in Codegen/ + restore ≥2× perf vs DynamicBVH

## Context

Two coupled goals:

1. **Zero hardcoded C in [thirdparty/predictive_bvh/PredictiveBVH/Codegen/](thirdparty/predictive_bvh/PredictiveBVH/Codegen/).** The split is now explicit: [predictive_bvh.h](thirdparty/predictive_bvh/predictive_bvh.h) is generated (must contain only genC-emitted ring polynomials + structural typedefs/#includes); [predictive_bvh_adapter.h](core/math/predictive_bvh_adapter.h) is hand-written (everywhere non-templated C belongs).
2. **pbvh ≥ 2× DBVH** on the per-frame bench. Current state: 0.11× / 0.21× / 0.28× / 0.33× at N ∈ {4k, 16k, 65k, 262k} — a 3×–9× regression from the 1.43× / 1.86× / 2.16× / 2.26× baseline.

Both goals resolve with one move: pull every raw-string C block out of CodeGen.lean / TreeC.lean into adapter.h. The perf regression is a direct consequence of wrapping hot-path predicates (`aabb_overlaps`, `aabb_union`) in ring-polynomial bridges that lose `&&` short-circuiting; once those short-circuit forms live in the adapter (where hand-written C is blessed), the pipeline fixes perf as a side effect.

## What stays in Codegen/ (generated)

Only genC-emitted ring polynomials, structural typedefs, and provenance artifacts:
- `ghostBoundC`, `surfaceAreaC`, `ghostAabbC`, `planeCornerValC`, `quinticHermiteC`, `deltaCostFnsC`, `scalarFnC`, `emlC` — already (a) classification per the survey.
- `ring_min_r128`, `ring_max_r128`, `aabb_overlaps_ring` — keep as genC'd provenance exports, callable from the adapter if needed (but not called on the hot path).
- `cPreamble` (#include / #ifndef guards), `constantsC` (#define macros + tick-rate parametric inline helpers), struct typedefs (`Aabb`, `pbvh_tree_t`, `pbvh_node_t`, etc.) — these are data-layout declarations, not algorithm C.

## What moves to adapter.h (hand-written)

Each block keeps a `// Proved: <lean theorem>` provenance comment pointing at the Lean source of truth.

### From [Codegen/CodeGen.lean](thirdparty/predictive_bvh/PredictiveBVH/Codegen/CodeGen.lean)

- `aabbC` body — `aabb_from_floats`, `aabb_union`, `aabb_overlaps`, `aabb_contains`, `aabb_contains_point`. **Restore short-circuit r128_le chains** for the three predicates (dominant perf regressor per survey: ~14k–28k excess R128 ops/frame at N=262k). `aabb_from_floats` is already partially in adapter — dedupe.
- `utilC` — `clz30`, `r128_half` bit-twiddling.
- `hilbertC` — `hilbert3d`, `hilbert3d_inverse`, `hilbert_of_aabb`, `hilbert_cell_of` (imperative bit manipulation).
- `ringMinMaxC` bridge wrappers — `r128_sign_bit`, `pbvh_r128_min`, `pbvh_r128_max` as **non-hot-path** alternatives. Callers on the hot path (aabb_union in refit, segmentAabb, half-space) use plain short-circuit forms.
- `deltaSelectC` control-flow wrapper around `deltaCostFnsC` polynomials — the if-chain is non-polynomial glue.

### From [Codegen/TreeC.lean](thirdparty/predictive_bvh/PredictiveBVH/Codegen/TreeC.lean)

The whole ~964 lines of control-flow C (23 tree ops: build, insert, remove, refit, aabb_query, aabb_query_n, aabb_query_b, ray_query, convex_query, etc.). Per survey, TreeC.lean has no genC'd content — it's pure strings calling helpers. This is the biggest move.

Two landing options, pick one:
- **(B1) Full port:** rewrite each tree-op body as a `static inline` free function or C++ method in `predictive_bvh_adapter.h`. Adapter `PredictiveBVH` class methods already wrap these; collapse the indirection.
- **(B2) Thin shim:** emit only the 23 function declarations in the generated header; put the bodies in a new file `core/math/predictive_bvh_adapter_tree.h` included by the adapter. Keeps TreeC.lean as the authoritative spec document (rename to `TreeCSpec.md` or similar).

Recommend **B1**. Simpler, removes one layer, enables the compiler to inline tree ops directly into adapter call sites.

## Revert the hot-path bridge regressions

The genC'd ring polynomials (`ring_min_r128`, `ring_max_r128`, `aabb_overlaps_ring`) stay in the header as proof artifacts — *not* wired to the hot path. Adapter-side fast C:

- `aabb_overlaps` / `aabb_contains` / `aabb_contains_point`: short-circuit `r128_le` chains (was the baseline).
- `aabb_union`: 6 inline `r128_le ? a : b` ternaries OR keep `pbvh_r128_min`/`pbvh_r128_max` calls (test both, pick faster — the min/max helpers branch-free might win on modern CPUs).
- `pbvh_segment_aabb_`: 6 r128_le ternaries inline (revert to baseline).
- `pbvh_half_space_keeps_`: keep the `pbvh_plane_corner_val` genC'd helper (that's a genuine polynomial and probably not the hot regressor — convex queries rare in the bench).

Each fast-path function carries a `// Proved equivalent to <ring fn> via bitDecompose; see Lean theorem <name>` comment so the provenance chain is explicit.

## Execution order

1. **Baseline measurement** — `bin/godot.macos.editor.dev.arm64 --headless --test --test-case="*per-frame*"` at HEAD. Record pbvh-x values.
2. **Step 1 — revert aabb_overlaps / contains / contains_point bridge in `aabbC`.** Restore short-circuit `r128_le` chains. Regen, rebuild, rebench. Expect ~80% of regression recovered.
3. **Step 2 — revert aabb_union bridge + pbvh_segment_aabb_ bridge.** Regen, rebuild, rebench. Expect remaining regression closed; target pbvh ≥ 2× DBVH at all N.
4. **Step 3 — move `aabbC` body to adapter.h.** Keep Aabb struct typedef in generated header (required for ABI). Move union/overlaps/contains/contains_point/from_floats. Keep `aabb_overlaps_ring` as genC-emitted proof artifact. Dedupe the `aabb_from_floats` I already added.
5. **Step 4 — move `utilC`, `hilbertC`, `ringMinMaxC` bridge wrappers to adapter.h.**
6. **Step 5 — move `deltaSelectC` control flow to adapter.h.** Keep the `deltaCostFnsC` genC'd polynomials in the header.
7. **Step 6 — move TreeC.lean bodies to adapter.h (option B1).** 23 functions. This is the largest step; do it in one pass to minimize header churn.
8. **Final regen + bench + regression gate.**

## Critical files

- [thirdparty/predictive_bvh/PredictiveBVH/Codegen/CodeGen.lean](thirdparty/predictive_bvh/PredictiveBVH/Codegen/CodeGen.lean) — remove aabbC / utilC / hilbertC / ringMinMaxC / deltaSelectC blocks; keep only genC-emitted helpers and structural glue.
- [thirdparty/predictive_bvh/PredictiveBVH/Codegen/TreeC.lean](thirdparty/predictive_bvh/PredictiveBVH/Codegen/TreeC.lean) — delete all treeBody content OR reduce to function-declaration stubs in the header.
- [core/math/predictive_bvh_adapter.h](core/math/predictive_bvh_adapter.h) — receives all moved C. Grows from ~current size to +~1200 lines.
- [thirdparty/predictive_bvh/predictive_bvh.h](thirdparty/predictive_bvh/predictive_bvh.h) — regenerated; shrinks to polynomial helpers + typedefs + declarations only.
- [tests/scene/test_predictive_bvh_bench.cpp](tests/scene/test_predictive_bvh_bench.cpp), [modules/multiplayer_fabric/fabric_zone.cpp](modules/multiplayer_fabric/fabric_zone.cpp) — already include `predictive_bvh_adapter.h`.
- [thirdparty/predictive_bvh/CONTRIBUTING.md](thirdparty/predictive_bvh/CONTRIBUTING.md) — update the codegen-discipline section: "Codegen/ emits only polynomial helpers and structural glue. All control-flow, bit-twiddling, and boolean predicate C lives in `predictive_bvh_adapter.h`."

## Verification

1. `cd thirdparty/predictive_bvh && lake build` — 313 jobs green, zero sorry.
2. `lake exe bvh-codegen` — `predictive_bvh.h` regenerates. Confirm:
   - `grep -E 'if \(|while \(|for \(' predictive_bvh.h | grep -v '^/\*'` — zero matches outside genC'd polynomial bodies.
   - `grep -c 'r128_le' predictive_bvh.h` — only appears inside `aabb_overlaps_ring` / ring-min/max proof exports.
   - `grep -c 'pbvh_tree_build\|pbvh_tree_insert\|...' predictive_bvh.h` — declarations only, no bodies with `{...;}`.
3. `scons platform=macos arch=arm64 dev_build=yes tests=yes -j8` — builds clean.
4. `bin/godot.macos.editor.dev.arm64 --headless --test --test-case="*FabricZone*,*PredictiveBVH*"` — 32/32 green, 4347+ assertions.
5. `bin/godot.macos.editor.dev.arm64 --headless --test --test-case="*per-frame*"` — pbvh ≥ 2.0× DBVH at N ∈ {4k, 16k, 65k, 262k}.
6. `bin/godot.macos.editor.dev.arm64 --headless --test --test-case="*stress*"` — truth=pbvh=dbvh at N ∈ {4k, 16k, 65k}.

## Chosen scope

TreeC.lean disposition: **B1 (full port to adapter.h)** — 23 tree-op bodies rewritten as static inline / C++ methods in `predictive_bvh_adapter.h`. TreeC.lean reduces to an empty shim or is deleted. The adapter becomes the single home for all non-polynomial C.
