/**************************************************************************/
/*  predictive_bvh_adapter.h                                              */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* SPDX-License-Identifier: MIT                                           */
/* Copyright (c) 2026-present K. S. Ernest (iFire) Lee                    */
/**************************************************************************/

#pragma once

// Drop-in adapter exposing a DynamicBVH-shaped C++ surface over predictive_bvh's
// codegen'd pbvh_tree_* symbols. Hand-written once; no algorithm content —
// every method is dispatch glue onto the emitted C primitives in
// thirdparty/predictive_bvh/predictive_bvh.h (from TreeC.lean). Lean-side
// proofs reason over EClassId; this adapter treats the pbvh_node_id_t as the
// eclass id and stores caller-supplied void * payloads in a parallel sidecar.

#include "core/math/aabb.h"
#include "core/math/plane.h"
#include "core/math/vector3.h"
#include "core/templates/local_vector.h"
#include "core/typedefs.h"

#include "thirdparty/predictive_bvh/predictive_bvh.h"

class PredictiveBVH {
public:
	struct ID {
		pbvh_node_id_t id = PBVH_NULL_NODE;
		_FORCE_INLINE_ bool is_valid() const { return id != PBVH_NULL_NODE; }
	};

private:
	pbvh_tree_t tree = {};
	LocalVector<pbvh_node_t> node_storage;
	LocalVector<pbvh_node_id_t> sorted_storage;
	LocalVector<pbvh_internal_t> internal_storage;
	LocalVector<void *> userdata; // parallel to node_storage
	// Phase 2c incremental-refit sidecars. Allocated lazily via _ensure_capacity
	// so pbvh_tree_tick can do O(K + n_touched) ancestor refits rather than
	// the O(internal_count) bottom-up pass.
	LocalVector<uint32_t> parent_of_internal_storage;
	LocalVector<uint32_t> leaf_to_internal_storage;
	LocalVector<uint64_t> touched_bits_storage;
	uint32_t index_slot = 0;
	bool dirty = false; // true if insert/update/remove happened since last build

	_FORCE_INLINE_ void _ensure_capacity(uint32_t need) {
		if (need <= tree.capacity) {
			return;
		}
		uint32_t new_cap = MAX(need, (uint32_t)16);
		while (new_cap < need) {
			new_cap *= 2;
		}
		const uint32_t internal_cap = new_cap * 2u;
		node_storage.resize(new_cap);
		sorted_storage.resize(new_cap);
		internal_storage.resize(internal_cap);
		userdata.resize(new_cap);
		parent_of_internal_storage.resize(internal_cap);
		leaf_to_internal_storage.resize(new_cap);
		touched_bits_storage.resize((internal_cap + 63u) / 64u);
		tree.nodes = node_storage.ptr();
		tree.sorted = sorted_storage.ptr();
		tree.internals = internal_storage.ptr();
		tree.capacity = new_cap;
		tree.internal_capacity = internal_cap;
		tree.parent_of_internal = parent_of_internal_storage.ptr();
		tree.leaf_to_internal = leaf_to_internal_storage.ptr();
		tree.touched_bits = touched_bits_storage.ptr();
	}

	// Scale by 1e6 (micrometres) to preserve sub-meter precision; keep the
	// multiply in double regardless of real_t so open-world consumers
	// (renderer, physics) don't lose precision through a float intermediate.
	_FORCE_INLINE_ static R128 _scalar_to_r128(real_t v) {
		return r128_from_int((int64_t)((double)v * 1000000.0));
	}

	_FORCE_INLINE_ static Aabb _aabb_to_r128(const AABB &b) {
		Aabb a;
		a.min_x = _scalar_to_r128(b.position.x);
		a.max_x = _scalar_to_r128(b.position.x + b.size.x);
		a.min_y = _scalar_to_r128(b.position.y);
		a.max_y = _scalar_to_r128(b.position.y + b.size.y);
		a.min_z = _scalar_to_r128(b.position.z);
		a.max_z = _scalar_to_r128(b.position.z + b.size.z);
		return a;
	}

	_FORCE_INLINE_ static pbvh_plane_t _plane_to_pbvh(const Plane &p) {
		pbvh_plane_t r;
		r.nx = _scalar_to_r128(p.normal.x);
		r.ny = _scalar_to_r128(p.normal.y);
		r.nz = _scalar_to_r128(p.normal.z);
		// Godot Plane: normal·p - d = 0; kept side is normal·p - d >= 0.
		// pbvh Plane: kept side is nx·x + ny·y + nz·z + d_pbvh >= 0, so
		// d_pbvh = -d.
		r.d = _scalar_to_r128(-p.d);
		return r;
	}

	_FORCE_INLINE_ void _maybe_build() {
		if (dirty) {
			pbvh_tree_build(&tree);
			dirty = false;
		}
	}

	template <typename QueryResult>
	struct Ctx {
		PredictiveBVH *self;
		QueryResult *result;
	};

	template <typename QueryResult>
	static int _aabb_cb(pbvh_eclass_id_t eclass, void *ud) {
		auto *ctx = (Ctx<QueryResult> *)ud;
		void *payload = ctx->self->userdata[eclass];
		return ctx->result->operator()(payload) ? 1 : 0;
	}

public:
	PredictiveBVH() {
		tree.root = PBVH_NULL_NODE;
		tree.free_head = PBVH_NULL_NODE;
		tree.internal_root = PBVH_NULL_NODE;
		tree.bucket_bits = 0u;
		tree.bucket_dir = nullptr;
	}

	_FORCE_INLINE_ bool is_empty() const { return pbvh_tree_is_empty(&tree); }

	_FORCE_INLINE_ void clear() {
		pbvh_tree_clear(&tree);
		userdata.clear();
		dirty = false;
	}

	ID insert(const AABB &p_box, void *p_userdata) {
		_ensure_capacity(tree.count + 1u);
		const Aabb r = _aabb_to_r128(p_box);
		pbvh_node_id_t id = pbvh_tree_insert(&tree, (pbvh_eclass_id_t)tree.count, r);
		if (id >= userdata.size()) {
			userdata.resize(id + 1u);
		}
		userdata[id] = p_userdata;
		// Rewrite the eclass to be id (stable across free-list reuse).
		tree.nodes[id].eclass = (pbvh_eclass_id_t)id;
		dirty = true;
		return ID{ id };
	}

	bool update(const ID &p_id, const AABB &p_box) {
		if (!p_id.is_valid() || p_id.id >= tree.capacity) {
			return false;
		}
		const Aabb r = _aabb_to_r128(p_box);
		pbvh_tree_update(&tree, p_id.id, r);
		dirty = true;
		return true;
	}

	void remove(const ID &p_id) {
		if (!p_id.is_valid() || p_id.id >= tree.capacity) {
			return;
		}
		pbvh_tree_remove(&tree, p_id.id);
		dirty = true;
	}

	_FORCE_INLINE_ void optimize_incremental(int p_passes) {
		if (dirty) {
			pbvh_tree_build(&tree);
			dirty = false;
		}
		(void)p_passes;
	}

	// Phase 2c per-frame rebalance. Pass the leaves that moved this frame
	// paired with their previous Hilbert code; the emitted C tick picks
	// refit vs full build based on whether any leaf crossed its Hilbert
	// bucket. tree.bucket_bits must be non-zero for the fast path to
	// fire; when it is zero (default), tick routes to pbvh_tree_build.
	struct DirtyLeaf {
		ID id;
		uint32_t old_hilbert;
	};

	void tick(const DirtyLeaf *p_dirty, uint32_t p_count) {
		if (p_count == 0 || p_dirty == nullptr) {
			pbvh_tree_tick(&tree, nullptr, 0);
			dirty = false;
			return;
		}
		LocalVector<pbvh_dirty_leaf_t> scratch;
		scratch.resize(p_count);
		for (uint32_t i = 0; i < p_count; i++) {
			scratch[i].leaf_id = p_dirty[i].id.id;
			scratch[i].old_hilbert = p_dirty[i].old_hilbert;
		}
		pbvh_tree_tick(&tree, scratch.ptr(), p_count);
		dirty = false;
	}

	_FORCE_INLINE_ void set_index(uint32_t p_index) { index_slot = p_index; }
	_FORCE_INLINE_ uint32_t get_index() const { return index_slot; }

	template <typename QueryResult>
	_FORCE_INLINE_ void aabb_query(const AABB &p_box, QueryResult &r_result) {
		_maybe_build();
		if (tree.internal_root == PBVH_NULL_NODE) {
			return;
		}
		Ctx<QueryResult> ctx = { this, &r_result };
		const Aabb q = _aabb_to_r128(p_box);
		pbvh_tree_aabb_query_n(&tree, &q, &_aabb_cb<QueryResult>, &ctx);
	}

	template <typename QueryResult>
	_FORCE_INLINE_ void ray_query(const Vector3 &p_from, const Vector3 &p_to, QueryResult &r_result) {
		_maybe_build();
		if (tree.internal_root == PBVH_NULL_NODE) {
			return;
		}
		Ctx<QueryResult> ctx = { this, &r_result };
		pbvh_tree_ray_query(&tree,
				_scalar_to_r128(p_from.x), _scalar_to_r128(p_from.y), _scalar_to_r128(p_from.z),
				_scalar_to_r128(p_to.x), _scalar_to_r128(p_to.y), _scalar_to_r128(p_to.z),
				&_aabb_cb<QueryResult>, &ctx);
	}

	template <typename QueryResult>
	_FORCE_INLINE_ void convex_query(const Plane *p_planes, int p_plane_count,
			const Vector3 *p_points, int p_point_count, QueryResult &r_result) {
		_maybe_build();
		if (tree.internal_root == PBVH_NULL_NODE || p_plane_count <= 0) {
			return;
		}
		LocalVector<pbvh_plane_t> planes;
		planes.resize((uint32_t)p_plane_count);
		for (int i = 0; i < p_plane_count; i++) {
			planes[i] = _plane_to_pbvh(p_planes[i]);
		}
		// Hull points: unused by our prune (plane-only), pass nullptr/0.
		(void)p_points;
		(void)p_point_count;
		Ctx<QueryResult> ctx = { this, &r_result };
		pbvh_tree_convex_query(&tree, planes.ptr(), (uint32_t)p_plane_count,
				nullptr, 0u, &_aabb_cb<QueryResult>, &ctx);
	}
};
