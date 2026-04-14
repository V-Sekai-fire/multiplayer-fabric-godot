/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026-present K. S. Ernest (iFire) Lee
 *
 * predictive_bvh_tree.h — hand-written Phase-1 scaffold for pbvh_tree_t.
 *
 * This header exists only until the Lean-side Tree.lean + TreeC.lean codegen
 * lands; at that point it is replaced by an emitted block in predictive_bvh.h.
 *
 * Two query APIs:
 *   pbvh_tree_aabb_query    — linear leaf scan (no hilbert needed). Matches
 *                             DynamicBVH::aabb_query for leaf-set equality.
 *   pbvh_tree_aabb_query_h  — Hilbert-prefix bucket query. Caller supplies a
 *                             query hilbert code and prefix bits; the tree
 *                             bisects the sorted-by-hilbert leaf array to the
 *                             matching prefix window, then AABB-tests within.
 *                             Requires pbvh_tree_build to have been called.
 */

#ifndef PREDICTIVE_BVH_TREE_H
#define PREDICTIVE_BVH_TREE_H

#include "predictive_bvh.h"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t pbvh_eclass_id_t;
typedef uint32_t pbvh_node_id_t;
typedef uint32_t pbvh_internal_id_t;

#define PBVH_NULL_NODE ((pbvh_node_id_t)0xFFFFFFFFu)

typedef struct pbvh_node {
	Aabb bounds; /* 96 B (R128 × 6) */
	pbvh_eclass_id_t eclass;
	pbvh_node_id_t next_free; /* PBVH_NULL_NODE when live */
	uint32_t is_leaf;
	uint32_t hilbert; /* 30-bit Hilbert code; sort key for query_h */
} pbvh_node_t;

/* Hilbert-radix internal node over sorted[]. Stored in pre-order DFS, so the
 * array itself is a nested set: the subtree rooted at internals[i] occupies
 * contiguous indices [i, i + subtree_count). On each node, (offset, span) is
 * the corresponding range inside t->sorted[] — the leaf nested set. */
typedef struct pbvh_internal {
	Aabb bounds; /* union of every leaf AABB in [offset, offset+span) */
	uint32_t offset; /* start index into t->sorted[] */
	uint32_t span; /* leaf count in this subtree */
	pbvh_internal_id_t left; /* PBVH_NULL_NODE when this is a leaf-range node */
	pbvh_internal_id_t right; /* PBVH_NULL_NODE when this is a leaf-range node */
} pbvh_internal_t;

typedef struct pbvh_tree {
	pbvh_node_t *nodes;
	uint32_t capacity;
	uint32_t count;
	pbvh_node_id_t root;
	pbvh_node_id_t free_head;
	/* Sorted-by-hilbert permutation of live leaf ids. Filled by pbvh_tree_build;
	 * consumed by pbvh_tree_aabb_query_h. Caller-owned storage of size capacity. */
	pbvh_node_id_t *sorted;
	uint32_t sorted_count;
	uint32_t last_visits; /* debug: # of leaves AABB-tested in the last query */
	/* Optional Hilbert-radix internal tree over sorted[]. Built by
	 * pbvh_tree_build iff `internals` is non-null and capacity allows.
	 * Consumed by pbvh_tree_aabb_query_n. Caller-owned. */
	pbvh_internal_t *internals;
	uint32_t internal_capacity;
	uint32_t internal_count;
	pbvh_internal_id_t internal_root;
} pbvh_tree_t;

static inline pbvh_node_id_t pbvh_tree_insert_h(pbvh_tree_t *t, pbvh_eclass_id_t ec,
		Aabb box, uint32_t hilbert) {
	pbvh_node_id_t id;
	if (t->free_head != PBVH_NULL_NODE) {
		id = t->free_head;
		t->free_head = t->nodes[id].next_free;
	} else {
		id = t->count++;
	}
	pbvh_node_t *n = &t->nodes[id];
	n->bounds = box;
	n->eclass = ec;
	n->next_free = PBVH_NULL_NODE;
	n->is_leaf = 1u;
	n->hilbert = hilbert;
	return id;
}

static inline pbvh_node_id_t pbvh_tree_insert(pbvh_tree_t *t, pbvh_eclass_id_t ec, Aabb box) {
	return pbvh_tree_insert_h(t, ec, box, 0u);
}

static inline void pbvh_tree_remove(pbvh_tree_t *t, pbvh_node_id_t id) {
	pbvh_node_t *n = &t->nodes[id];
	n->is_leaf = 0u;
	n->next_free = t->free_head;
	t->free_head = id;
}

static inline void pbvh_tree_update(pbvh_tree_t *t, pbvh_node_id_t id, Aabb box) {
	t->nodes[id].bounds = box;
}

/* Update bounds AND hilbert code together. Caller must pbvh_tree_build()
 * before the next h-query; the sort key has changed so sorted[] is stale. */
static inline void pbvh_tree_update_h(pbvh_tree_t *t, pbvh_node_id_t id,
		Aabb box, uint32_t hilbert) {
	pbvh_node_t *n = &t->nodes[id];
	n->bounds = box;
	n->hilbert = hilbert;
}

/* Build one internal node over sorted[lo, hi) by splitting on the highest
 * bit where the first and last Hilbert codes disagree. Pre-order layout:
 * the returned id is the slot claimed before any descendant, so internals[]
 * itself ends up in DFS order (nested-set property on the internals array).
 *
 * Returns PBVH_NULL_NODE if the range is empty or the caller-provided
 * internals[] capacity is exhausted. */
static inline pbvh_internal_id_t pbvh_build_internal_(pbvh_tree_t *t, uint32_t lo, uint32_t hi) {
	if (lo >= hi) {
		return PBVH_NULL_NODE;
	}
	if (t->internal_count >= t->internal_capacity) {
		return PBVH_NULL_NODE;
	}
	pbvh_internal_id_t id = t->internal_count++;
	pbvh_internal_t *n = &t->internals[id];
	n->offset = lo;
	n->span = hi - lo;
	n->bounds = t->nodes[t->sorted[lo]].bounds;
	for (uint32_t i = lo + 1; i < hi; i++) {
		n->bounds = aabb_union(&n->bounds, &t->nodes[t->sorted[i]].bounds);
	}
	if (hi - lo <= 1) {
		n->left = PBVH_NULL_NODE;
		n->right = PBVH_NULL_NODE;
		return id;
	}
	uint32_t h_lo = t->nodes[t->sorted[lo]].hilbert;
	uint32_t h_hi = t->nodes[t->sorted[hi - 1]].hilbert;
	uint32_t diff = h_lo ^ h_hi;
	uint32_t split = lo + (hi - lo) / 2;
	if (diff != 0u) {
		uint32_t bit = 31u;
		while ((diff & (1u << bit)) == 0u) {
			bit--;
		}
		uint32_t mask = 1u << bit;
		/* first i in [lo, hi) with that bit set — sorted[] is ascending, so
		 * the set-bit suffix is contiguous. */
		uint32_t s = hi;
		for (uint32_t i = lo; i < hi; i++) {
			if ((t->nodes[t->sorted[i]].hilbert & mask) != 0u) {
				s = i;
				break;
			}
		}
		if (s > lo && s < hi) {
			split = s;
		}
	}
	n->left = pbvh_build_internal_(t, lo, split);
	n->right = pbvh_build_internal_(t, split, hi);
	/* `n` pointer may have moved if internals[] were resizable; it's caller-
	 * owned fixed storage so the pointer stays valid across recursion. */
	return id;
}

/* Insertion sort `sorted[]` by nodes[sorted[i]].hilbert ascending.
 * For the tree sizes FabricZone operates on (<=1800) and the fact that
 * Hilbert codes change slowly between frames, insertion sort has the right
 * shape: O(N) on near-sorted inputs, no heap churn.
 *
 * If internals[] is provided, also build the Hilbert-radix internal tree
 * on top of sorted[] so pbvh_tree_aabb_query_n can use nested-set ranges. */
static inline void pbvh_tree_build(pbvh_tree_t *t) {
	uint32_t k = 0;
	for (uint32_t i = 0; i < t->count; i++) {
		if (t->nodes[i].is_leaf) {
			t->sorted[k++] = (pbvh_node_id_t)i;
		}
	}
	t->sorted_count = k;
	for (uint32_t i = 1; i < k; i++) {
		pbvh_node_id_t cur = t->sorted[i];
		uint32_t cur_h = t->nodes[cur].hilbert;
		uint32_t j = i;
		while (j > 0 && t->nodes[t->sorted[j - 1]].hilbert > cur_h) {
			t->sorted[j] = t->sorted[j - 1];
			j--;
		}
		t->sorted[j] = cur;
	}
	t->internal_count = 0u;
	t->internal_root = PBVH_NULL_NODE;
	if (t->internals != NULL && t->internal_capacity > 0u && k > 0u) {
		t->internal_root = pbvh_build_internal_(t, 0u, k);
	}
}

/* Bisect sorted[] to the window where hilbert >> shift == target. */
static inline void pbvh_tree_prefix_window_(const pbvh_tree_t *t, uint32_t target,
		uint32_t shift, uint32_t *r_lo, uint32_t *r_hi) {
	uint32_t lo = 0, hi = t->sorted_count;
	while (lo < hi) {
		uint32_t mid = lo + (hi - lo) / 2;
		if ((t->nodes[t->sorted[mid]].hilbert >> shift) < target) {
			lo = mid + 1;
		} else {
			hi = mid;
		}
	}
	*r_lo = lo;
	hi = t->sorted_count;
	uint32_t lo2 = lo;
	while (lo2 < hi) {
		uint32_t mid = lo2 + (hi - lo2) / 2;
		if ((t->nodes[t->sorted[mid]].hilbert >> shift) <= target) {
			lo2 = mid + 1;
		} else {
			hi = mid;
		}
	}
	*r_hi = lo2;
}

/* Linear scan. Sets t->last_visits to the total leaf count touched. */
static inline void pbvh_tree_aabb_query(pbvh_tree_t *t, const Aabb *query,
		int (*cb)(pbvh_eclass_id_t, void *), void *ud) {
	const uint32_t n = t->count;
	uint32_t visits = 0;
	for (uint32_t i = 0; i < n; i++) {
		const pbvh_node_t *node = &t->nodes[i];
		if (!node->is_leaf) {
			continue;
		}
		visits++;
		if (aabb_overlaps(&node->bounds, query)) {
			if (cb(node->eclass, ud) != 0) {
				t->last_visits = visits;
				return;
			}
		}
	}
	t->last_visits = visits;
}

/* Return 1 iff the query AABB fits inside a single Hilbert prefix cell at
 * the given prefix_bits under the supplied scene AABB. Hilbert3D at prefix
 * P (multiple of 3) is an axis-aligned 2^(P/3) × 2^(P/3) × 2^(P/3) grid,
 * so the check reduces to: do min/max corners agree on the top (P/3) bits
 * of each axis's 10-bit quantization? */
static inline int pbvh_query_fits_in_one_cell_(const Aabb *query, const Aabb *scene,
		uint32_t prefix_bits) {
	if (prefix_bits == 0u || (prefix_bits % 3u) != 0u) {
		return 0;
	}
	const uint32_t bits_per_axis = prefix_bits / 3u;
	const uint32_t axis_shift = 10u - bits_per_axis;
	R128 sw = r128_sub(scene->max_x, scene->min_x);
	R128 sh = r128_sub(scene->max_y, scene->min_y);
	R128 sd = r128_sub(scene->max_z, scene->min_z);
	R128 k1024 = r128_from_int(1024LL);
	int64_t swi = r128_to_int(sw), shi = r128_to_int(sh), sdi = r128_to_int(sd);
	if (swi <= 0) swi = 1;
	if (shi <= 0) shi = 1;
	if (sdi <= 0) sdi = 1;
	int64_t nxlo = r128_to_int(r128_mul(r128_sub(query->min_x, scene->min_x), k1024)) / swi;
	int64_t nxhi = r128_to_int(r128_mul(r128_sub(query->max_x, scene->min_x), k1024)) / swi;
	int64_t nylo = r128_to_int(r128_mul(r128_sub(query->min_y, scene->min_y), k1024)) / shi;
	int64_t nyhi = r128_to_int(r128_mul(r128_sub(query->max_y, scene->min_y), k1024)) / shi;
	int64_t nzlo = r128_to_int(r128_mul(r128_sub(query->min_z, scene->min_z), k1024)) / sdi;
	int64_t nzhi = r128_to_int(r128_mul(r128_sub(query->max_z, scene->min_z), k1024)) / sdi;
	const int64_t clamp_hi = 1023;
	if (nxlo < 0) nxlo = 0; if (nxlo > clamp_hi) nxlo = clamp_hi;
	if (nxhi < 0) nxhi = 0; if (nxhi > clamp_hi) nxhi = clamp_hi;
	if (nylo < 0) nylo = 0; if (nylo > clamp_hi) nylo = clamp_hi;
	if (nyhi < 0) nyhi = 0; if (nyhi > clamp_hi) nyhi = clamp_hi;
	if (nzlo < 0) nzlo = 0; if (nzlo > clamp_hi) nzlo = clamp_hi;
	if (nzhi < 0) nzhi = 0; if (nzhi > clamp_hi) nzhi = clamp_hi;
	return ((uint32_t)nxlo >> axis_shift) == ((uint32_t)nxhi >> axis_shift)
			&& ((uint32_t)nylo >> axis_shift) == ((uint32_t)nyhi >> axis_shift)
			&& ((uint32_t)nzlo >> axis_shift) == ((uint32_t)nzhi >> axis_shift);
}

/* Nested-set traversal over the internal tree. Descends from internal_root;
 * on a bounds miss, the whole subtree is pruned without touching any leaf.
 * On a terminal (leaf-range) node, iterates sorted[offset .. offset+span).
 * Falls back to pbvh_tree_aabb_query if the internal tree was not built. */
static inline int pbvh_tree_aabb_query_n_rec_(pbvh_tree_t *t, pbvh_internal_id_t nid,
		const Aabb *query, uint32_t *visits,
		int (*cb)(pbvh_eclass_id_t, void *), void *ud) {
	if (nid == PBVH_NULL_NODE) {
		return 0;
	}
	const pbvh_internal_t *n = &t->internals[nid];
	if (!aabb_overlaps(&n->bounds, query)) {
		return 0;
	}
	if (n->left == PBVH_NULL_NODE && n->right == PBVH_NULL_NODE) {
		for (uint32_t i = n->offset; i < n->offset + n->span; i++) {
			const pbvh_node_t *leaf = &t->nodes[t->sorted[i]];
			if (!leaf->is_leaf) {
				continue;
			}
			(*visits)++;
			if (aabb_overlaps(&leaf->bounds, query)) {
				if (cb(leaf->eclass, ud) != 0) {
					return 1;
				}
			}
		}
		return 0;
	}
	if (pbvh_tree_aabb_query_n_rec_(t, n->left, query, visits, cb, ud) != 0) {
		return 1;
	}
	return pbvh_tree_aabb_query_n_rec_(t, n->right, query, visits, cb, ud);
}

static inline void pbvh_tree_aabb_query_n(pbvh_tree_t *t, const Aabb *query,
		int (*cb)(pbvh_eclass_id_t, void *), void *ud) {
	if (t->internals == NULL || t->internal_root == PBVH_NULL_NODE) {
		pbvh_tree_aabb_query(t, query, cb, ud);
		return;
	}
	uint32_t visits = 0u;
	pbvh_tree_aabb_query_n_rec_(t, t->internal_root, query, &visits, cb, ud);
	t->last_visits = visits;
}

/* Hilbert-prefix bucket query. If `scene` is non-null and the query AABB
 * spans more than one prefix cell, falls back to a linear scan to preserve
 * correctness. Requires pbvh_tree_build() since the last mutation. */
static inline void pbvh_tree_aabb_query_h(pbvh_tree_t *t, const Aabb *query,
		uint32_t query_hilbert, uint32_t prefix_bits, const Aabb *scene,
		int (*cb)(pbvh_eclass_id_t, void *), void *ud) {
	if (prefix_bits == 0u || prefix_bits >= 30u) {
		pbvh_tree_aabb_query(t, query, cb, ud);
		return;
	}
	if (scene != NULL && !pbvh_query_fits_in_one_cell_(query, scene, prefix_bits)) {
		pbvh_tree_aabb_query(t, query, cb, ud);
		return;
	}
	const uint32_t shift = 30u - prefix_bits;
	const uint32_t target = query_hilbert >> shift;
	uint32_t lo, hi;
	pbvh_tree_prefix_window_(t, target, shift, &lo, &hi);
	uint32_t visits = 0u;
	for (uint32_t i = lo; i < hi; i++) {
		const pbvh_node_t *node = &t->nodes[t->sorted[i]];
		if (!node->is_leaf) {
			continue; // dead leaf — caller mutated without rebuilding
		}
		visits++;
		if (aabb_overlaps(&node->bounds, query)) {
			if (cb(node->eclass, ud) != 0) {
				t->last_visits = visits;
				return;
			}
		}
	}
	t->last_visits = visits;
}

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* PREDICTIVE_BVH_TREE_H */
