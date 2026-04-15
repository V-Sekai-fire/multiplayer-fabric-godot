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

// ─────────────────────────────────────────────────────────────────────────────
// pbvh_real_t — R128-backed scalar with a real_t-shaped C++ interface.
//
// This is the "real_t backend" type: callers pass real_t values in/out, but
// all arithmetic internally uses 64.64 fixed-point (R128) for the precision
// that the Lean-proved polynomial functions require.
//
// Template specialization selects this type transparently via pbvh_backend<T>:
//   pbvh_backend<real_t>::type  = pbvh_real_t   (R128 precision)
//   pbvh_backend<int64_t>::type = int64_t        (native integer)
// ─────────────────────────────────────────────────────────────────────────────
struct pbvh_real_t {
	R128 v;

	pbvh_real_t() : v(R128_ZERO) {}
	/* Construct from R128 — used internally and by r128_* return values. */
	pbvh_real_t(R128 r) : v(r) {}
	/* Construct from integer literal — satisfies T(n) in template code. */
	pbvh_real_t(int n) : v(r128_from_int((int64_t)n)) {}
	pbvh_real_t(int64_t n) : v(r128_from_int(n)) {}
	/* Construct from Godot real_t (float or double). */
	explicit pbvh_real_t(real_t f) : v(r128_from_float((float)f)) {}

	/* Implicit decay to R128 — lets r128_le/r128_add etc. accept pbvh_real_t
	 * arguments without explicit casts (single user-defined conversion). */
	operator R128() const { return v; }
	/* Explicit export to real_t for output side. */
	explicit operator real_t() const { return (real_t)r128_to_float(v); }

	/* Arithmetic operators — satisfy (a + b), (a * b) in template code. */
	pbvh_real_t operator+(pbvh_real_t o) const { return r128_add(v, o.v); }
	pbvh_real_t operator*(pbvh_real_t o) const { return r128_mul(v, o.v); }
	pbvh_real_t operator-() const { return r128_neg(v); }
	pbvh_real_t operator-(pbvh_real_t o) const { return r128_sub(v, o.v); }

	/* Comparison — satisfies operator<= used in template predicates. */
	bool operator<=(pbvh_real_t o) const { return r128_le(v, o.v); }
	bool operator==(pbvh_real_t o) const { return r128_eq(v, o.v); }
	bool operator!=(pbvh_real_t o) const { return !r128_eq(v, o.v); }
};

// ─────────────────────────────────────────────────────────────────────────────
// pbvh_backend<T> — traits class: maps caller-facing scalar types to the
// internal storage type used by the BVH template instantiations.
//
// Template specialization allows callers to write pbvh_tree_for<real_t> and
// get R128-backed precision, or pbvh_tree_for<int64_t> for integer coordinates,
// without knowing about the R128 representation.
// ─────────────────────────────────────────────────────────────────────────────
template <typename T>
struct pbvh_backend { using type = T; };

template <>
struct pbvh_backend<real_t> { using type = pbvh_real_t; };

// Convenience alias: pbvh_tree_for<real_t> → pbvh_tree<pbvh_real_t>, etc.
template <typename T>
using pbvh_tree_for = pbvh_tree<typename pbvh_backend<T>::type>;
template <typename T>
using pbvh_node_for = pbvh_node<typename pbvh_backend<T>::type>;
template <typename T>
using pbvh_internal_for = pbvh_internal<typename pbvh_backend<T>::type>;
template <typename T>
using AabbFor = AabbT<typename pbvh_backend<T>::type>;

// Named aliases for the two concrete instantiations.
using AabbReal     = AabbFor<real_t>;   // AabbT<pbvh_real_t>  — R128 precision
using AabbI64      = AabbFor<int64_t>;  // AabbT<int64_t>      — integer coords

// Float-AABB constructor glue. Non-templated boilerplate, so it lives here per
// the codegen discipline in thirdparty/predictive_bvh/CONTRIBUTING.md rather
// than inside the emitted header.
static inline Aabb aabb_from_floats(float x0, float x1, float y0, float y1, float z0, float z1) {
	Aabb a;
	a.min_x = r128_from_int((int64_t)(x0 * 1000000.0f));
	a.max_x = r128_from_int((int64_t)(x1 * 1000000.0f));
	a.min_y = r128_from_int((int64_t)(y0 * 1000000.0f));
	a.max_y = r128_from_int((int64_t)(y1 * 1000000.0f));
	a.min_z = r128_from_int((int64_t)(z0 * 1000000.0f));
	a.max_z = r128_from_int((int64_t)(z1 * 1000000.0f));
	return a;
}

// real_t variant — passes through R128 precision. Callers work with real_t;
// each field is stored as r128_from_float(x * 1e6) ≈ 1 µm resolution.
static inline AabbReal aabb_from_reals(real_t x0, real_t x1, real_t y0, real_t y1, real_t z0, real_t z1) {
	AabbReal a;
	a.min_x = pbvh_real_t(r128_from_float((float)(x0 * 1000000.0)));
	a.max_x = pbvh_real_t(r128_from_float((float)(x1 * 1000000.0)));
	a.min_y = pbvh_real_t(r128_from_float((float)(y0 * 1000000.0)));
	a.max_y = pbvh_real_t(r128_from_float((float)(y1 * 1000000.0)));
	a.min_z = pbvh_real_t(r128_from_float((float)(z0 * 1000000.0)));
	a.max_z = pbvh_real_t(r128_from_float((float)(z1 * 1000000.0)));
	return a;
}

// int64_t variant — integer µm coordinates, no floating-point conversion.
static inline AabbI64 aabb_from_um(int64_t x0, int64_t x1, int64_t y0, int64_t y1, int64_t z0, int64_t z1) {
	return { x0, x1, y0, y1, z0, z1 };
}

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
	LocalVector<uint64_t> touched_meta_bits_storage;
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
		const uint32_t touched_words = (internal_cap + 63u) / 64u;
		touched_bits_storage.resize(touched_words);
		touched_meta_bits_storage.resize((touched_words + 63u) / 64u);
		tree.nodes = node_storage.ptr();
		tree.sorted = sorted_storage.ptr();
		tree.internals = internal_storage.ptr();
		tree.capacity = new_cap;
		tree.internal_capacity = internal_cap;
		tree.parent_of_internal = parent_of_internal_storage.ptr();
		tree.leaf_to_internal = leaf_to_internal_storage.ptr();
		tree.touched_bits = touched_bits_storage.ptr();
		tree.touched_meta_bits = touched_meta_bits_storage.ptr();
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
