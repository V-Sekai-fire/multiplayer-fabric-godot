# Zero hardcoded C in Codegen/ + restore ≥2× perf vs DynamicBVH

## Status: COMPLETE (2026-04-15)

## What was done
1. ✅ `aabbC` fast-paths, `utilC`, `hilbertC`, `ringMinMaxC`, `deltaSelectC` moved out of CodeGen.lean → `core/math/predictive_bvh_adapter.h`. Only `aabb_overlaps_ring` polynomial retained in CodeGen.lean.
2. ✅ All tree functions from `TreeC.lean` moved to `core/math/predictive_bvh_adapter.h` as `inline`. TreeC.lean is now 114 lines (structs/typedefs only).
3. ✅ Header regenerated: `lake exe bvh-codegen` exits 0.
4. ✅ Build passes (`gscons tests=yes -j8`). 201/201 per-frame tests pass.
5. ✅ Rust adapter (`thirdparty/predictive_bvh/predictive_bvh_adapter.rs`) with full feature parity.
6. ✅ Cargo crate + CLI test binary (`pbvh_test`) — all 8 tests pass: hilbert round-trip, query correctness, tick correctness, remove, clear/re-insert, ray query, enumerate_pairs, index slot.

## What stays in Codegen/ (by design)
- R128 ring arithmetic primitives (`static inline`): `r128_from_int`, `r128_add/sub/mul/div`, `r128_le`, etc.
- Generated polynomial template + `deltaCostFnsC`, `quinticHermiteC`, `scalarFnC`, `emlC`
- `aabb_overlaps_ring` polynomial (proof export)
- `pbvh_hysteresis_threshold`, `pbvh_latency_ticks`, `pbvh_v_max_physical_um_per_tick`, `pbvh_accel_floor_um_per_tick2`
- Struct typedefs (`AabbT<T>`, `pbvh_node_t`, `pbvh_internal_t`, `pbvh_tree_t`)

## Open
- ~~Verify ≥2× perf vs DynamicBVH~~ — DONE, exceeded target (see below).

## int64_t migration (2026-04-15)
Switched all tree node AABB storage from `R128` (software 128-bit) to `int64_t` (native µm integers).

### What changed
- `TreeC.lean`: `pbvh_node_t`, `pbvh_internal_t`, `pbvh_tree_t` aliases → `<int64_t>`
- `CodeGen.lean`: `using Aabb = AabbT<int64_t>`
- `predictive_bvh_adapter.h`: `aabb_union`, `aabb_overlaps`, `aabb_contains`, `aabb_contains_point` now use native `<=`; `hilbert_of_aabb` and `hilbert_cell_of` use pure int64 arithmetic; `pbvh_segment_aabb_` and `pbvh_tree_ray_query` take `int64_t` coords; `_aabb_to_i64` / `_scalar_to_i64` added to `PredictiveBVH` class (R128 retained only for `pbvh_plane_t` dot products)
- `lake exe bvh-codegen` regenerated header; build clean, 217/217 assertions pass

### Perf before → after (per-frame tick, pbvh vs dbvh)
| N | Before (R128) | After (int64_t) | vs DBVH |
|---|---|---|---|
| 4,096 | 50us | 28us | 3.17× |
| 16,384 | 177us | 104us | 3.82× |
| 65,536 | 925us | 534us | 3.65× |
| 262,144 | 3,950us | 2,489us | 3.59× |
| STRESS 65k | — | 8,316us | **4.07×** |

Hit counts identical across pbvh/dbvh/truth at all scales. Plan goal (≥2×) comfortably exceeded.

## Godot integration (2026-04-15)
Swapped `DynamicBVH` → `PredictiveBVH` at two call sites (commit f89228a9a0e):
- [servers/rendering/renderer_scene_cull.h](servers/rendering/renderer_scene_cull.h) + [.cpp](servers/rendering/renderer_scene_cull.cpp) — scene culling BVH
- [modules/godot_physics_3d/godot_soft_body_3d.h](modules/godot_physics_3d/godot_soft_body_3d.h) — soft body broadphase
- [core/math/dynamic_bvh.h](core/math/dynamic_bvh.h) / [.cpp](core/math/dynamic_bvh.cpp) — kept as-is (still used elsewhere)
- [tests/scene/test_predictive_bvh_bench.cpp](tests/scene/test_predictive_bvh_bench.cpp) — bench expanded (+529 lines) to cover the new integration paths

## Outstanding
- Working tree: [thirdparty/predictive_bvh/PredictiveBVH/Protocol/ScaleContradictionsGapClass.lean](thirdparty/predictive_bvh/PredictiveBVH/Protocol/ScaleContradictionsGapClass.lean) modified, uncommitted
- Branch `vsk-multiplayer-fabric-4.7` is 17 commits ahead of origin — not pushed
