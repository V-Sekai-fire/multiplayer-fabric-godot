/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026-present K. S. Ernest (iFire) Lee
 *
 * predictive_bvh_tree.h — hand-written Phase-1 scaffold for pbvh_tree_t.
 *
 * This header exists only until the Lean-side Tree.lean + TreeC.lean codegen
 * lands; at that point it is replaced by an emitted block in predictive_bvh.h.
 * The API here is the frozen contract the codegen must match: same structs,
 * same function signatures, same semantics. Callers of pbvh_tree_* should
 * include this header; once codegen takes over, this file becomes a
 * forwarding stub (or is deleted outright).
 *
 * Semantics match DynamicBVH::aabb_query for leaf-set equality: inserting N
 * AABBs then querying any AABB returns exactly the set of eclass_ids whose
 * stored AABB overlaps the query. Internal layout is *not* yet a real tree —
 * it is a flat array scan. That is intentional: Phase 1's job is to land the
 * API and the parity test; the Hilbert-prefix-keyed tree walk replaces the
 * scan in a later pass, guarded by the same parity harness.
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

/* Packed leaf/internal record. Phase 1 stores only leaves; `is_leaf` is
 * always 1. The left/right fields are reserved for the tree walk. */
typedef struct pbvh_node {
	Aabb bounds; /* 96 B (R128 × 6) */
	pbvh_eclass_id_t eclass;
	pbvh_node_id_t next_free; /* PBVH_NULL_NODE when live */
	uint32_t is_leaf; /* 1 = leaf (Phase 1 only emits leaves) */
	uint32_t _pad;
} pbvh_node_t;

typedef struct pbvh_tree {
	pbvh_node_t *nodes;
	uint32_t capacity;
	uint32_t count; /* number of slots ever allocated (high-water mark) */
	pbvh_node_id_t root; /* unused in Phase 1 scan impl; reserved */
	pbvh_node_id_t free_head;
} pbvh_tree_t;

static inline pbvh_node_id_t pbvh_tree_insert(pbvh_tree_t *t, pbvh_eclass_id_t ec, Aabb box) {
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
	n->_pad = 0u;
	return id;
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

/* cb returns 0 to continue, non-zero to stop early.
 * Phase-1 impl scans leaves linearly; parity with DynamicBVH is the contract,
 * the Hilbert-prefix-keyed tree walk replaces the scan in Phase 2. */
static inline void pbvh_tree_aabb_query(const pbvh_tree_t *t, const Aabb *query,
		int (*cb)(pbvh_eclass_id_t, void *), void *ud) {
	const uint32_t n = t->count;
	for (uint32_t i = 0; i < n; i++) {
		const pbvh_node_t *node = &t->nodes[i];
		if (!node->is_leaf) {
			continue;
		}
		if (aabb_overlaps(&node->bounds, query)) {
			if (cb(node->eclass, ud) != 0) {
				return;
			}
		}
	}
}

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* PREDICTIVE_BVH_TREE_H */
