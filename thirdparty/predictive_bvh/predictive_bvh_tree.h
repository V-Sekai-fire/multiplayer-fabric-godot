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

#define PBVH_NULL_NODE ((pbvh_node_id_t)0xFFFFFFFFu)

typedef struct pbvh_node {
	Aabb bounds; /* 96 B (R128 × 6) */
	pbvh_eclass_id_t eclass;
	pbvh_node_id_t next_free; /* PBVH_NULL_NODE when live */
	uint32_t is_leaf;
	uint32_t hilbert; /* 30-bit Hilbert code; sort key for query_h */
} pbvh_node_t;

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

/* Insertion sort `sorted[]` by nodes[sorted[i]].hilbert ascending.
 * For the tree sizes FabricZone operates on (<=1800) and the fact that
 * Hilbert codes change slowly between frames, insertion sort has the right
 * shape: O(N) on near-sorted inputs, no heap churn. */
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

/* Hilbert-prefix bucket query. Visits only the prefix window in `sorted[]`.
 * Requires pbvh_tree_build() to have been called since the last mutation. */
static inline void pbvh_tree_aabb_query_h(pbvh_tree_t *t, const Aabb *query,
		uint32_t query_hilbert, uint32_t prefix_bits,
		int (*cb)(pbvh_eclass_id_t, void *), void *ud) {
	if (prefix_bits == 0u || prefix_bits >= 30u) {
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
