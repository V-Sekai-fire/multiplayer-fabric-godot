# Zero hardcoded C in Codegen/ + restore ≥2× perf vs DynamicBVH

## Context
1. **Zero hardcoded C in thirdparty/predictive_bvh/PredictiveBVH/Codegen/**: All hand-written C must be in `core/math/predictive_bvh_adapter.h`. `predictive_bvh.h` should only contain generated ring polynomials and structural typedefs/macros. This fixes the redefinition errors seen when variables and functions conflict.
2. **Restore pbvh ≥ 2× DBVH perf**: By moving `aabb_overlaps`, `aabb_contains`, `aabb_contains_point`, and `aabb_union` to the adapter, they can use short-circuit `&&` and `r128_le` instead of polynomial bridges.

## What stays in Codegen/
- `ghostBoundC`, `surfaceAreaC`, `ghostAabbC`, `planeCornerValC`, `quinticHermiteC`, `deltaCostFnsC`, `scalarFnC`, `emlC`
- `ring_min_r128`, `ring_max_r128`, `aabb_overlaps_ring`
- `constantsC`, struct typedefs (`Aabb`, `pbvh_tree_t`, etc.)

## What moves to adapter.h
- `aabbC`'s fast-path bodies (`aabb_union`, `aabb_overlaps`, etc.)
- `utilC` (`clz30`, `r128_half`)
- `hilbertC` (`hilbert3d`, `hilbert3d_inverse`, `hilbert_of_aabb`, `hilbert_cell_of`)
- `ringMinMaxC` bridge wrappers (`r128_sign_bit`, `pbvh_r128_min`, etc.)
- `deltaSelectC` control flow wrapper (`per_entity_delta_poly`)
- **All TreeC functions** (e.g. `pbvh_tree_build`, `pbvh_tree_insert`, `pbvh_tree_aabb_query_n`, etc.)

## Execution Steps
1. **Move `aabbC` body, `utilC`, `hilbertC`, `ringMinMaxC`, and `deltaSelectC` out of CodeGen.lean and into `core/math/predictive_bvh_adapter.h`.**
   - Retain `aabb_overlaps_ring` in CodeGen.lean.
   - Remove the `aabb_union_fn` typedefs from `CodeGen.lean`.
2. **Move all functions from `TreeC.lean` to `core/math/predictive_bvh_adapter.h`.** 
   - `TreeC.lean` should be left with only the structs and typedefs (e.g., `pbvh_node_t`, `pbvh_internal_t`, `pbvh_tree_t`).
3. **Regenerate the header**: `cd thirdparty/predictive_bvh && lake exe bvh-codegen`
4. **Build and Test**: Rebuild with `scons dev_build=yes tests=yes` and run the benchmarks. Ensure `pbvh` restores the ≥2× performance compared to DBVH and the build completes without redefinition errors.
