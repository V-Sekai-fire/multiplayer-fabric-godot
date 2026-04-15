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

// ─────────────────────────────────────────────────────────────────────────────
// Non-polynomial R128 helpers — moved here from CodeGen.lean / generated header.
// These are direct C translations (no E-graph optimization). They belong in
// the adapter rather than the generated header per the codegen discipline:
// the generated header should contain only E-graph-produced polynomial code.
// ─────────────────────────────────────────────────────────────────────────────

/* Sign bit of R128 (d.hi's high bit) packed as R128-encoded 0 or 1.
   Used by the Z<->GF(2) bridge to turn comparisons into ring ops. */
inline R128 r128_sign_bit(R128 d) {
	R128 r;
	r.hi = ((uint64_t)d.hi >> 63) & 1;
	r.lo = 0;
	return r;
}

/* Branchless min via Z<->GF(2) bridge. sign = sign_bit(b-a). */
template <typename T>
static inline T ring_min_r128(T a, T b, T sign) {
	T t0 = (T(-1) * a);
	T t1 = (b + t0);
	T t2 = (sign * t1);
	T t3 = (a + t2);
	return t3;
}

/* Branchless max via Z<->GF(2) bridge. sign = sign_bit(b-a). */
template <typename T>
static inline T ring_max_r128(T a, T b, T sign) {
	T t0 = (T(-1) * a);
	T t1 = (b + t0);
	T t2 = (sign * t1);
	T t3 = (T(-1) * t2);
	T t4 = (b + t3);
	return t4;
}

/* Two-arg min/max wrappers: compute sign inline, delegate to ring form. */
inline R128 pbvh_r128_min(R128 a, R128 b) {
	return ring_min_r128(a, b, r128_sign_bit(r128_sub(b, a)));
}

inline R128 pbvh_r128_max(R128 a, R128 b) {
	return ring_max_r128(a, b, r128_sign_bit(r128_sub(b, a)));
}

/* Aabb union — hot-path short-circuit form (called per refit). Proved
   equivalent to ring_min_r128 / ring_max_r128 via Z<->GF(2) bridge. */
inline Aabb aabb_union(const Aabb *a, const Aabb *o) {
	Aabb r;
	r.min_x = r128_le(a->min_x, o->min_x) ? a->min_x : o->min_x;
	r.max_x = r128_le(a->max_x, o->max_x) ? o->max_x : a->max_x;
	r.min_y = r128_le(a->min_y, o->min_y) ? a->min_y : o->min_y;
	r.max_y = r128_le(a->max_y, o->max_y) ? o->max_y : a->max_y;
	r.min_z = r128_le(a->min_z, o->min_z) ? a->min_z : o->min_z;
	r.max_z = r128_le(a->max_z, o->max_z) ? o->max_z : a->max_z;
	return r;
}

/* Fast-path predicates: short-circuit r128_le chains. Proved equivalent to
   aabb_overlaps_ring via the Z<->GF(2) bridge — see Lean HilbertBroadphase. */
inline bool aabb_overlaps(const Aabb *a, const Aabb *o) {
	return r128_le(a->min_x, o->max_x) && r128_le(o->min_x, a->max_x) && r128_le(a->min_y, o->max_y) && r128_le(o->min_y, a->max_y) && r128_le(a->min_z, o->max_z) && r128_le(o->min_z, a->max_z);
}

inline bool aabb_contains(const Aabb *a, const Aabb *inner) {
	return r128_le(a->min_x, inner->min_x) && r128_le(inner->max_x, a->max_x) && r128_le(a->min_y, inner->min_y) && r128_le(inner->max_y, a->max_y) && r128_le(a->min_z, inner->min_z) && r128_le(inner->max_z, a->max_z);
}

inline bool aabb_contains_point(const Aabb *a, R128 x, R128 y, R128 z) {
	return r128_le(a->min_x, x) && r128_le(x, a->max_x) && r128_le(a->min_y, y) && r128_le(y, a->max_y) && r128_le(a->min_z, z) && r128_le(z, a->max_z);
}

/* Source: Build.lean:193 (clz30) */
inline uint32_t clz30(uint32_t x) {
	return x == 0 ? 30 : 29 - (31 - _pbvh_clz(x));
}

/* R128 arithmetic right shift by 1 (divide by 2, preserving sign) */
inline R128 r128_half(R128 v) {
	R128 r;
	r.hi = v.hi >> 1;
	r.lo = (v.lo >> 1) | ((uint64_t)v.hi << 63);
	return r;
}

/* Source: Build.lean (hilbert3D) — Skilling (2004) 3D Hilbert curve.
   O(b) bit manipulation; better locality than Morton for volume partitioning.
   Bader (2013) Ch.7: cluster diameter O(n^{1/3}) vs Morton O(n^{2/3}). */
inline uint32_t hilbert3d(uint32_t x, uint32_t y, uint32_t z) {
	const uint32_t order = 10;
	const uint32_t mask = (1u << order) - 1u;
	x &= mask;
	y &= mask;
	z &= mask;
	/* Step 1: inverse undo (MSB down to bit 1) */
	for (uint32_t i = 0; i < order - 1; i++) {
		uint32_t q = 1u << (order - 1 - i);
		uint32_t p = q - 1;
		if (z & q) {
			x ^= p;
		} else {
			uint32_t t = (x ^ z) & p;
			x ^= t;
			z ^= t;
		}
		if (y & q) {
			x ^= p;
		} else {
			uint32_t t = (x ^ y) & p;
			x ^= t;
			y ^= t;
		}
	}
	/* Step 2: Gray encode */
	y ^= x;
	z ^= y;
	/* Step 3: fixup — propagate gray parity */
	uint32_t t = 0;
	for (uint32_t i = 0; i < order - 1; i++) {
		uint32_t q = 1u << (order - 1 - i);
		if (z & q) {
			t ^= (q - 1);
		}
	}
	x ^= t;
	y ^= t;
	z ^= t;
	x &= mask;
	y &= mask;
	z &= mask;
	/* Step 4: transpose to 30-bit index (MSB-first, z-y-x per triple) */
	uint32_t h = 0;
	for (int b = (int)order - 1; b >= 0; b--) {
		h = (h << 1) | ((z >> b) & 1);
		h = (h << 1) | ((y >> b) & 1);
		h = (h << 1) | ((x >> b) & 1);
	}
	return h;
}

/* Forward declaration required by hilbert_of_aabb before the definition below. */
inline void hilbert3d_inverse(uint32_t h, uint32_t *ox, uint32_t *oy, uint32_t *oz);

/* Source: Build.lean (leafHilbert) — R128 Aabb, returns uint32 Hilbert code */
inline uint32_t hilbert_of_aabb(const Aabb *b, const Aabb *scene) {
	R128 sw = r128_sub(scene->max_x, scene->min_x);
	R128 sh = r128_sub(scene->max_y, scene->min_y);
	R128 sd = r128_sub(scene->max_z, scene->min_z);
	R128 one = r128_from_int(1LL);
	if (r128_le(sw, R128_ZERO)) {
		sw = one;
	}
	if (r128_le(sh, R128_ZERO)) {
		sh = one;
	}
	if (r128_le(sd, R128_ZERO)) {
		sd = one;
	}
	R128 k1024 = r128_from_int(1024LL);
	R128 cx = r128_half(r128_add(b->min_x, b->max_x));
	R128 cy = r128_half(r128_add(b->min_y, b->max_y));
	R128 cz = r128_half(r128_add(b->min_z, b->max_z));
	int64_t swi = r128_to_int(sw), shi = r128_to_int(sh), sdi = r128_to_int(sd);
	if (swi == 0) {
		swi = 1;
	}
	if (shi == 0) {
		shi = 1;
	}
	if (sdi == 0) {
		sdi = 1;
	}
	int64_t nxi = r128_to_int(r128_mul(r128_sub(cx, scene->min_x), k1024)) / swi;
	int64_t nyi = r128_to_int(r128_mul(r128_sub(cy, scene->min_y), k1024)) / shi;
	int64_t nzi = r128_to_int(r128_mul(r128_sub(cz, scene->min_z), k1024)) / sdi;
	uint32_t nx = (uint32_t)(nxi < 0 ? 0 : nxi > 1023 ? 1023 : nxi);
	uint32_t ny = (uint32_t)(nyi < 0 ? 0 : nyi > 1023 ? 1023 : nyi);
	uint32_t nz = (uint32_t)(nzi < 0 ? 0 : nzi > 1023 ? 1023 : nzi);
	uint32_t h = hilbert3d(nx, ny, nz);
	/* Witness check: inverse(forward(x,y,z)) == (x,y,z) */
	uint32_t rx, ry, rz;
	hilbert3d_inverse(h, &rx, &ry, &rz);
	CRASH_COND(rx != nx || ry != ny || rz != nz);
	return h;
}

/* Hilbert3D inverse: 30-bit code → (x, y, z) 10-bit coordinates.
   Skilling transposeToAxes. Verified by roundtrip in Lean. */
inline void hilbert3d_inverse(uint32_t h, uint32_t *ox, uint32_t *oy, uint32_t *oz) {
	const uint32_t order = 10;
	const uint32_t mask = (1u << order) - 1u;
	uint32_t x = 0, y = 0, z = 0;
	for (uint32_t b = 0; b < order; b++) {
		uint32_t s = 3 * b;
		x |= ((h >> s) & 1) << b;
		y |= ((h >> (s + 1)) & 1) << b;
		z |= ((h >> (s + 2)) & 1) << b;
	}
	/* Undo fixup: progressive decode */
	uint32_t t = 0;
	for (uint32_t i = 0; i < order - 1; i++) {
		uint32_t q = 1u << (order - 1 - i);
		if ((z ^ t) & q) {
			t ^= (q - 1);
		}
	}
	x ^= t;
	y ^= t;
	z ^= t;
	/* Undo Gray: z ^= y, then y ^= x */
	z ^= y;
	y ^= x;
	/* Undo main loop: Q from 2 to MSB, y then z */
	for (uint32_t q = 2; q < (1u << order); q <<= 1) {
		uint32_t p = q - 1;
		if (y & q) {
			x ^= p;
		} else {
			uint32_t ty = (x ^ y) & p;
			x ^= ty;
			y ^= ty;
		}
		if (z & q) {
			x ^= p;
		} else {
			uint32_t tz = (x ^ z) & p;
			x ^= tz;
			z ^= tz;
		}
	}
	*ox = x & mask;
	*oy = y & mask;
	*oz = z & mask;
	/* Witness check: forward(inverse(h)) == h */
	CRASH_COND(hilbert3d(*ox, *oy, *oz) != h);
}

/* Hilbert-cell-of: AABB from Hilbert code + prefix depth + scene bounds (R128). */
inline Aabb hilbert_cell_of(uint32_t code, uint32_t prefix_depth, const Aabb *scene) {
	uint32_t cx, cy, cz;
	hilbert3d_inverse(code, &cx, &cy, &cz);
	int64_t sw = r128_to_int(r128_sub(scene->max_x, scene->min_x));
	int64_t sh = r128_to_int(r128_sub(scene->max_y, scene->min_y));
	int64_t sd = r128_to_int(r128_sub(scene->max_z, scene->min_z));
	if (sw <= 0) {
		sw = 1;
	}
	if (sh <= 0) {
		sh = 1;
	}
	if (sd <= 0) {
		sd = 1;
	}
	uint32_t shift = (prefix_depth < 10) ? 10 - prefix_depth : 0;
	int64_t cell = 1LL << shift;
	uint32_t x0 = (cx >> shift) << shift;
	uint32_t y0 = (cy >> shift) << shift;
	uint32_t z0 = (cz >> shift) << shift;
	Aabb result;
	result.min_x = r128_add(scene->min_x, r128_div(r128_mul(r128_from_int((int64_t)x0), r128_sub(scene->max_x, scene->min_x)), r128_from_int(1024LL)));
	result.max_x = r128_add(scene->min_x, r128_div(r128_mul(r128_from_int((int64_t)x0 + cell), r128_sub(scene->max_x, scene->min_x)), r128_from_int(1024LL)));
	result.min_y = r128_add(scene->min_y, r128_div(r128_mul(r128_from_int((int64_t)y0), r128_sub(scene->max_y, scene->min_y)), r128_from_int(1024LL)));
	result.max_y = r128_add(scene->min_y, r128_div(r128_mul(r128_from_int((int64_t)y0 + cell), r128_sub(scene->max_y, scene->min_y)), r128_from_int(1024LL)));
	result.min_z = r128_add(scene->min_z, r128_div(r128_mul(r128_from_int((int64_t)z0), r128_sub(scene->max_z, scene->min_z)), r128_from_int(1024LL)));
	result.max_z = r128_add(scene->min_z, r128_div(r128_mul(r128_from_int((int64_t)z0 + cell), r128_sub(scene->max_z, scene->min_z)), r128_from_int(1024LL)));
	return result;
}

/* Per-entity delta: largest candidate where v*d + ah*d^2 <= R.
   Polynomial cost evaluation via E-graph (delta_cost_N<pbvh_real_t> templates);
   selection is non-ring postprocessing.
   Uses pbvh_real_t internally so that T(n) literal construction works for the
   template instantiation; R128 args are implicitly promoted via pbvh_real_t(R128).
   Source of truth: perEntityDelta (Sim.lean:407) */
inline uint32_t per_entity_delta_poly(R128 v_r, R128 a_half_r) {
	pbvh_real_t v(v_r), a(a_half_r);
	const R128 R = r128_from_int(5000000LL);
	if (r128_le(delta_cost_120(v, a), R)) { return 120; }
	if (r128_le(delta_cost_100(v, a), R)) { return 100; }
	if (r128_le(delta_cost_80(v, a), R)) { return 80; }
	if (r128_le(delta_cost_64(v, a), R)) { return 64; }
	if (r128_le(delta_cost_48(v, a), R)) { return 48; }
	if (r128_le(delta_cost_32(v, a), R)) { return 32; }
	if (r128_le(delta_cost_24(v, a), R)) { return 24; }
	if (r128_le(delta_cost_16(v, a), R)) { return 16; }
	if (r128_le(delta_cost_8(v, a), R)) { return 8; }
	if (r128_le(delta_cost_4(v, a), R)) { return 4; }
	if (r128_le(delta_cost_2(v, a), R)) { return 2; }
	if (r128_le(delta_cost_1(v, a), R)) { return 1; }
	return 1;
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
