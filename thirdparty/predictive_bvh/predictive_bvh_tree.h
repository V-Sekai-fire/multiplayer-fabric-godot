/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026-present K. S. Ernest (iFire) Lee
 *
 * predictive_bvh_tree.h — hand-written Phase-1 scaffold for pbvh_tree_t.
 *
 * This header exists only until the Lean-side Tree.lean + TreeC.lean codegen
 * lands; at that point it is replaced by an emitted block in predictive_bvh.h.
 *
 * Query APIs (internals[] mandatory for the fast paths):
 *   pbvh_tree_aabb_query    — O(N) brute-force leaf scan. Kept as a
 *                             test-only correctness oracle; new code should
 *                             use _n or _b.
 *   pbvh_tree_aabb_query_n  — iterative nested-set descent over the Hilbert
 *                             radix internal tree. Branchless skip-pointer
 *                             flow, no recursion, prunes entire subtrees on
 *                             a bounds miss via a single index jump.
 *   pbvh_tree_aabb_query_b  — O(1)+k bucket-directory query. Caller provides
 *                             the query's 30-bit Hilbert code; the tree
 *                             precomputes a (lo, hi) window per Hilbert
 *                             prefix bucket so descent is replaced by a
 *                             single table lookup plus range iteration.
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
	uint32_t hilbert; /* 30-bit Hilbert code; sort key */
} pbvh_node_t;

/* Hilbert-radix internal node over sorted[]. Stored in pre-order DFS, so the
 * array itself is a nested set: the subtree rooted at internals[i] occupies
 * contiguous indices [i, skip). On each node, (offset, span) is the
 * corresponding range inside t->sorted[] — the leaf-side nested set. */
typedef struct pbvh_internal {
	Aabb bounds; /* union of every leaf AABB in [offset, offset+span) */
	uint32_t offset; /* start index into t->sorted[] */
	uint32_t span; /* leaf count in this subtree */
	pbvh_internal_id_t skip; /* next DFS index after this subtree ends */
	pbvh_internal_id_t left; /* PBVH_NULL_NODE when this is a leaf-range node */
	pbvh_internal_id_t right; /* PBVH_NULL_NODE when this is a leaf-range node */
} pbvh_internal_t;

typedef struct pbvh_tree {
	pbvh_node_t *nodes;
	uint32_t capacity;
	uint32_t count;
	pbvh_node_id_t root;
	pbvh_node_id_t free_head;
	/* Sorted-by-hilbert permutation of live leaf ids. Caller-owned, size capacity. */
	pbvh_node_id_t *sorted;
	uint32_t sorted_count;
	uint32_t last_visits; /* debug: # of leaves AABB-tested in the last query */
	/* Hilbert-radix internal tree over sorted[]. Mandatory for _n and _b
	 * queries. Caller-owned; size at least 2*capacity covers any split shape. */
	pbvh_internal_t *internals;
	uint32_t internal_capacity;
	uint32_t internal_count;
	pbvh_internal_id_t internal_root;
	/* Optional bucket directory: bucket_dir[p] is the half-open range
	 * [lo, hi) of sorted[] indices whose Hilbert code has prefix p at
	 * bucket_bits. Size must be 1u << bucket_bits; two uint32 per entry
	 * laid out flat as [lo0, hi0, lo1, hi1, …]. Set bucket_bits=0 to skip. */
	uint32_t *bucket_dir;
	uint32_t bucket_bits;
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
 * before the next _n or _b query; the sort key has changed. */
static inline void pbvh_tree_update_h(pbvh_tree_t *t, pbvh_node_id_t id,
		Aabb box, uint32_t hilbert) {
	pbvh_node_t *n = &t->nodes[id];
	n->bounds = box;
	n->hilbert = hilbert;
}

/* Build one internal node over sorted[lo, hi) by splitting on the highest
 * bit where the first and last Hilbert codes disagree. Pre-order layout:
 * the returned id is the slot claimed before any descendant, so internals[]
 * itself ends up in DFS order. The `skip` field is set after the children
 * are placed — it equals t->internal_count at that point, i.e. the index
 * that any ancestor would jump to when pruning this subtree. */
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
		n->skip = t->internal_count;
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
	pbvh_internal_id_t l = pbvh_build_internal_(t, lo, split);
	pbvh_internal_id_t r = pbvh_build_internal_(t, split, hi);
	/* Re-fetch: the `n` pointer to caller-owned fixed storage stays valid,
	 * but writing through it after recursion is the clearest shape. */
	t->internals[id].left = l;
	t->internals[id].right = r;
	t->internals[id].skip = t->internal_count;
	return id;
}

/* Populate bucket_dir[2*b], bucket_dir[2*b+1] with the (lo, hi) window in
 * sorted[] whose Hilbert prefix at bucket_bits equals b. Runs in O(N + B)
 * where B = 1 << bucket_bits. */
static inline void pbvh_build_bucket_dir_(pbvh_tree_t *t) {
	if (t->bucket_dir == NULL || t->bucket_bits == 0u || t->bucket_bits > 30u) {
		return;
	}
	const uint32_t B = 1u << t->bucket_bits;
	for (uint32_t i = 0; i < 2u * B; i++) {
		t->bucket_dir[i] = 0u;
	}
	const uint32_t shift = 30u - t->bucket_bits;
	uint32_t j = 0u;
	for (uint32_t b = 0; b < B; b++) {
		t->bucket_dir[2u * b] = j;
		while (j < t->sorted_count &&
				(t->nodes[t->sorted[j]].hilbert >> shift) == b) {
			j++;
		}
		t->bucket_dir[2u * b + 1u] = j;
	}
	/* Any Hilbert codes outside [0, B) (e.g. from queries with scene-mismatched
	 * codes) land past the last bucket — those queries must fall back to _n. */
}

/* Insertion sort sorted[] by hilbert, then build the internal tree and
 * (if provided) the bucket directory. O(N) on near-sorted input. */
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
	pbvh_build_bucket_dir_(t);
}

/* O(N) brute-force leaf scan. Kept only as the correctness oracle for
 * tests; production paths should use _n or _b. Sets last_visits. */
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

/* Iterative nested-set descent. Walks internals[] in pre-order; on a bounds
 * miss, jumps straight to internals[i].skip, which is the index past the
 * entire pruned subtree — a single assignment, no stack, no recursion.
 * On a leaf-range node, iterates sorted[offset .. offset+span) then jumps
 * to skip. Requires internals[] to have been built. */
static inline void pbvh_tree_aabb_query_n(pbvh_tree_t *t, const Aabb *query,
		int (*cb)(pbvh_eclass_id_t, void *), void *ud) {
	uint32_t visits = 0u;
	if (t->internal_root == PBVH_NULL_NODE) {
		t->last_visits = 0u;
		return;
	}
	uint32_t i = t->internal_root;
	const uint32_t end = t->internal_count;
	while (i < end) {
		const pbvh_internal_t *n = &t->internals[i];
		if (!aabb_overlaps(&n->bounds, query)) {
			i = n->skip;
			continue;
		}
		if (n->left == PBVH_NULL_NODE && n->right == PBVH_NULL_NODE) {
			const uint32_t o = n->offset;
			const uint32_t s = n->span;
			for (uint32_t j = o; j < o + s; j++) {
				const pbvh_node_t *leaf = &t->nodes[t->sorted[j]];
				if (!leaf->is_leaf) {
					continue;
				}
				visits++;
				if (aabb_overlaps(&leaf->bounds, query)) {
					if (cb(leaf->eclass, ud) != 0) {
						t->last_visits = visits;
						return;
					}
				}
			}
			i = n->skip;
			continue;
		}
		i++; /* descend: next DFS index is the left child */
	}
	t->last_visits = visits;
}

/* Bucket-directory query. Given the query's Hilbert code, computes the
 * owning prefix bucket in O(1) and iterates only the leaves in that window.
 * Total cost is O(1 + k) where k is the bucket's leaf count — strictly
 * better than the O(log N) descent of _n for queries the caller can tag
 * with a Hilbert code. Falls through to _n if bucket_dir wasn't built. */
static inline void pbvh_tree_aabb_query_b(pbvh_tree_t *t, const Aabb *query,
		uint32_t query_hilbert,
		int (*cb)(pbvh_eclass_id_t, void *), void *ud) {
	if (t->bucket_dir == NULL || t->bucket_bits == 0u) {
		pbvh_tree_aabb_query_n(t, query, cb, ud);
		return;
	}
	const uint32_t shift = 30u - t->bucket_bits;
	const uint32_t b = query_hilbert >> shift;
	const uint32_t B = 1u << t->bucket_bits;
	if (b >= B) {
		pbvh_tree_aabb_query_n(t, query, cb, ud);
		return;
	}
	const uint32_t lo = t->bucket_dir[2u * b];
	const uint32_t hi = t->bucket_dir[2u * b + 1u];
	uint32_t visits = 0u;
	for (uint32_t j = lo; j < hi; j++) {
		const pbvh_node_t *leaf = &t->nodes[t->sorted[j]];
		if (!leaf->is_leaf) {
			continue;
		}
		visits++;
		if (aabb_overlaps(&leaf->bounds, query)) {
			if (cb(leaf->eclass, ud) != 0) {
				t->last_visits = visits;
				return;
			}
		}
	}
	t->last_visits = visits;
}

/* Eclass-style self-query: look up the leaf that stores eclass `self` and
 * run _b using its stored bounds + hilbert. Skips `self` in results so the
 * callback only sees "other" eclasses that overlap. Caller works in eclass
 * IDs end-to-end; no AABB pointers, no Hilbert codes threaded through. */
typedef struct pbvh_eclass_skip_ud {
	pbvh_eclass_id_t self;
	int (*inner_cb)(pbvh_eclass_id_t, void *);
	void *inner_ud;
} pbvh_eclass_skip_ud_t;

static inline int pbvh_eclass_skip_cb_(pbvh_eclass_id_t other, void *ud) {
	pbvh_eclass_skip_ud_t *s = (pbvh_eclass_skip_ud_t *)ud;
	if (other == s->self) {
		return 0;
	}
	return s->inner_cb(other, s->inner_ud);
}

static inline void pbvh_tree_query_eclass(pbvh_tree_t *t, pbvh_eclass_id_t self,
		int (*cb)(pbvh_eclass_id_t, void *), void *ud) {
	const uint32_t n = t->count;
	for (uint32_t i = 0; i < n; i++) {
		const pbvh_node_t *node = &t->nodes[i];
		if (!node->is_leaf || node->eclass != self) {
			continue;
		}
		pbvh_eclass_skip_ud_t s = { self, cb, ud };
		pbvh_tree_aabb_query_b(t, &node->bounds, node->hilbert,
				pbvh_eclass_skip_cb_, &s);
		return;
	}
}

/* Enumerate every overlapping (a, b) pair with a.eclass < b.eclass exactly
 * once. Pure eclass-style API — no caller-side AABBs, no Hilbert threading,
 * just two eclass IDs per pair. Uses _n (nested-set skip descent) so ghost
 * AABBs that span multiple Hilbert cells stay correct. */
typedef struct pbvh_pair_enum_ud {
	pbvh_eclass_id_t self;
	int matched_count;
	int (*pair_cb)(pbvh_eclass_id_t, pbvh_eclass_id_t, void *);
	void *pair_ud;
} pbvh_pair_enum_ud_t;

static inline int pbvh_pair_enum_cb_(pbvh_eclass_id_t other, void *ud) {
	pbvh_pair_enum_ud_t *p = (pbvh_pair_enum_ud_t *)ud;
	if (other <= p->self) {
		return 0;
	}
	p->matched_count++;
	return p->pair_cb(p->self, other, p->pair_ud);
}

static inline int pbvh_tree_enumerate_pairs(pbvh_tree_t *t,
		int (*pair_cb)(pbvh_eclass_id_t, pbvh_eclass_id_t, void *), void *ud) {
	int pairs = 0;
	for (uint32_t i = 0; i < t->count; i++) {
		const pbvh_node_t *node = &t->nodes[i];
		if (!node->is_leaf) {
			continue;
		}
		pbvh_pair_enum_ud_t p = { node->eclass, 0, pair_cb, ud };
		pbvh_tree_aabb_query_n(t, &node->bounds,
				pbvh_pair_enum_cb_, &p);
		pairs += p.matched_count;
	}
	return pairs;
}

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* PREDICTIVE_BVH_TREE_H */
