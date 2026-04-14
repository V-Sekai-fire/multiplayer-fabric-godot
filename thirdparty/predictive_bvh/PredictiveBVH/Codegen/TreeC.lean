-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee
--
-- TreeC.lean — emits the pbvh_tree_* block into predictive_bvh.h.
--
-- The hand-written predictive_bvh_tree.h scaffold lives at
-- thirdparty/predictive_bvh/predictive_bvh_tree.h and is deleted once this
-- emitted block passes the existing 23-case doctest suite. Algorithm and
-- field layout mirror Spatial/Tree.lean verbatim so the proofs there hold
-- for the code emitted here.

namespace PredictiveBVH.Codegen.TreeC

def treeBanner : String :=
  "/* ══════════════════════════════════════════════════════════════════════════\n" ++
  "   PBVH TREE (Hilbert-radix nested-set BVH; emitted from Spatial/Tree.lean)\n" ++
  "   ══════════════════════════════════════════════════════════════════════════ */\n\n"

def treeBody : String := "typedef uint32_t pbvh_eclass_id_t;
typedef uint32_t pbvh_node_id_t;
typedef uint32_t pbvh_internal_id_t;

#define PBVH_NULL_NODE ((pbvh_node_id_t)0xFFFFFFFFu)

typedef struct pbvh_node {
\tAabb bounds; /* 96 B (R128 × 6) */
\tpbvh_eclass_id_t eclass;
\tpbvh_node_id_t next_free; /* PBVH_NULL_NODE when live */
\tuint32_t is_leaf;
\tuint32_t hilbert; /* 30-bit Hilbert code; sort key */
} pbvh_node_t;

/* Hilbert-radix internal node over sorted[]. Stored in pre-order DFS, so the
 * array itself is a nested set: the subtree rooted at internals[i] occupies
 * contiguous indices [i, skip). On each node, (offset, span) is the
 * corresponding range inside t->sorted[] — the leaf-side nested set. */
typedef struct pbvh_internal {
\tAabb bounds; /* union of every leaf AABB in [offset, offset+span) */
\tuint32_t offset; /* start index into t->sorted[] */
\tuint32_t span; /* leaf count in this subtree */
\tpbvh_internal_id_t skip; /* next DFS index after this subtree ends */
\tpbvh_internal_id_t left; /* PBVH_NULL_NODE when this is a leaf-range node */
\tpbvh_internal_id_t right; /* PBVH_NULL_NODE when this is a leaf-range node */
} pbvh_internal_t;

typedef struct pbvh_tree {
\tpbvh_node_t *nodes;
\tuint32_t capacity;
\tuint32_t count;
\tpbvh_node_id_t root;
\tpbvh_node_id_t free_head;
\t/* Sorted-by-hilbert permutation of live leaf ids. Caller-owned, size capacity. */
\tpbvh_node_id_t *sorted;
\tuint32_t sorted_count;
\tuint32_t last_visits; /* debug: # of leaves AABB-tested in the last query */
\t/* Hilbert-radix internal tree over sorted[]. Mandatory for _n and _b
\t * queries. Caller-owned; size at least 2*capacity covers any split shape. */
\tpbvh_internal_t *internals;
\tuint32_t internal_capacity;
\tuint32_t internal_count;
\tpbvh_internal_id_t internal_root;
\t/* Optional bucket directory: bucket_dir[p] is the half-open range
\t * [lo, hi) of sorted[] indices whose Hilbert code has prefix p at
\t * bucket_bits. Size must be 1u << bucket_bits; two uint32 per entry
\t * laid out flat as [lo0, hi0, lo1, hi1, …]. Set bucket_bits=0 to skip. */
\tuint32_t *bucket_dir;
\tuint32_t bucket_bits;
} pbvh_tree_t;

static inline pbvh_node_id_t pbvh_tree_insert_h(pbvh_tree_t *t, pbvh_eclass_id_t ec,
\t\tAabb box, uint32_t hilbert) {
\tpbvh_node_id_t id;
\tif (t->free_head != PBVH_NULL_NODE) {
\t\tid = t->free_head;
\t\tt->free_head = t->nodes[id].next_free;
\t} else {
\t\tid = t->count++;
\t}
\tpbvh_node_t *n = &t->nodes[id];
\tn->bounds = box;
\tn->eclass = ec;
\tn->next_free = PBVH_NULL_NODE;
\tn->is_leaf = 1u;
\tn->hilbert = hilbert;
\treturn id;
}

static inline pbvh_node_id_t pbvh_tree_insert(pbvh_tree_t *t, pbvh_eclass_id_t ec, Aabb box) {
\treturn pbvh_tree_insert_h(t, ec, box, 0u);
}

static inline void pbvh_tree_remove(pbvh_tree_t *t, pbvh_node_id_t id) {
\tpbvh_node_t *n = &t->nodes[id];
\tn->is_leaf = 0u;
\tn->next_free = t->free_head;
\tt->free_head = id;
}

static inline void pbvh_tree_update(pbvh_tree_t *t, pbvh_node_id_t id, Aabb box) {
\tt->nodes[id].bounds = box;
}

/* Update bounds AND hilbert code together. Caller must pbvh_tree_build()
 * before the next _n or _b query; the sort key has changed. */
static inline void pbvh_tree_update_h(pbvh_tree_t *t, pbvh_node_id_t id,
\t\tAabb box, uint32_t hilbert) {
\tpbvh_node_t *n = &t->nodes[id];
\tn->bounds = box;
\tn->hilbert = hilbert;
}

/* Build one internal node over sorted[lo, hi) by splitting on the highest
 * bit where the first and last Hilbert codes disagree. Pre-order layout:
 * the returned id is the slot claimed before any descendant, so internals[]
 * itself ends up in DFS order. The `skip` field is set after the children
 * are placed — it equals t->internal_count at that point, i.e. the index
 * that any ancestor would jump to when pruning this subtree. */
static inline pbvh_internal_id_t pbvh_build_internal_(pbvh_tree_t *t, uint32_t lo, uint32_t hi) {
\tif (lo >= hi) {
\t\treturn PBVH_NULL_NODE;
\t}
\tif (t->internal_count >= t->internal_capacity) {
\t\treturn PBVH_NULL_NODE;
\t}
\tpbvh_internal_id_t id = t->internal_count++;
\tpbvh_internal_t *n = &t->internals[id];
\tn->offset = lo;
\tn->span = hi - lo;
\tn->bounds = t->nodes[t->sorted[lo]].bounds;
\tfor (uint32_t i = lo + 1; i < hi; i++) {
\t\tn->bounds = aabb_union(&n->bounds, &t->nodes[t->sorted[i]].bounds);
\t}
\tif (hi - lo <= 1) {
\t\tn->left = PBVH_NULL_NODE;
\t\tn->right = PBVH_NULL_NODE;
\t\tn->skip = t->internal_count;
\t\treturn id;
\t}
\tuint32_t h_lo = t->nodes[t->sorted[lo]].hilbert;
\tuint32_t h_hi = t->nodes[t->sorted[hi - 1]].hilbert;
\tuint32_t diff = h_lo ^ h_hi;
\tuint32_t split = lo + (hi - lo) / 2;
\tif (diff != 0u) {
\t\tuint32_t bit = 31u;
\t\twhile ((diff & (1u << bit)) == 0u) {
\t\t\tbit--;
\t\t}
\t\tuint32_t mask = 1u << bit;
\t\tuint32_t s = hi;
\t\tfor (uint32_t i = lo; i < hi; i++) {
\t\t\tif ((t->nodes[t->sorted[i]].hilbert & mask) != 0u) {
\t\t\t\ts = i;
\t\t\t\tbreak;
\t\t\t}
\t\t}
\t\tif (s > lo && s < hi) {
\t\t\tsplit = s;
\t\t}
\t}
\tpbvh_internal_id_t l = pbvh_build_internal_(t, lo, split);
\tpbvh_internal_id_t r = pbvh_build_internal_(t, split, hi);
\t/* Re-fetch: the `n` pointer to caller-owned fixed storage stays valid,
\t * but writing through it after recursion is the clearest shape. */
\tt->internals[id].left = l;
\tt->internals[id].right = r;
\tt->internals[id].skip = t->internal_count;
\treturn id;
}

/* Populate bucket_dir[2*b], bucket_dir[2*b+1] with the (lo, hi) window in
 * sorted[] whose Hilbert prefix at bucket_bits equals b. Runs in O(N + B)
 * where B = 1 << bucket_bits. */
static inline void pbvh_build_bucket_dir_(pbvh_tree_t *t) {
\tif (t->bucket_dir == NULL || t->bucket_bits == 0u || t->bucket_bits > 30u) {
\t\treturn;
\t}
\tconst uint32_t B = 1u << t->bucket_bits;
\tfor (uint32_t i = 0; i < 2u * B; i++) {
\t\tt->bucket_dir[i] = 0u;
\t}
\tconst uint32_t shift = 30u - t->bucket_bits;
\tuint32_t j = 0u;
\tfor (uint32_t b = 0; b < B; b++) {
\t\tt->bucket_dir[2u * b] = j;
\t\twhile (j < t->sorted_count &&
\t\t\t\t(t->nodes[t->sorted[j]].hilbert >> shift) == b) {
\t\t\tj++;
\t\t}
\t\tt->bucket_dir[2u * b + 1u] = j;
\t}
\t/* Any Hilbert codes outside [0, B) (e.g. from queries with scene-mismatched
\t * codes) land past the last bucket — those queries must fall back to _n. */
}

/* Phase 2c refit-only fast path. Caller guarantees that no dirty leaf has
 * changed bucket (hilbert prefix at bucket_bits stable), so sorted[] order
 * and internals[] topology stay valid — only bounds need re-unioning.
 *
 * Walks internals[] bottom-up in reverse DFS order: leaf-range nodes
 * refit from sorted[offset..offset+span), inner nodes union their two
 * children's already-refit bounds. Runs in O(internal_count), but every
 * pass is sequential memory reads over a contiguous array — cache-friendly
 * and free of sort/rebuild churn. When the dirty set is sparse relative
 * to N, this is the frame-budget win vs pbvh_tree_build. */
static inline void pbvh_tree_refit(pbvh_tree_t *t) {
\tif (t->internal_count == 0u) {
\t\treturn;
\t}
\tuint32_t idx = t->internal_count;
\twhile (idx > 0u) {
\t\tidx--;
\t\tpbvh_internal_t *n = &t->internals[idx];
\t\tif (n->left == PBVH_NULL_NODE && n->right == PBVH_NULL_NODE) {
\t\t\tconst uint32_t o = n->offset;
\t\t\tconst uint32_t s = n->span;
\t\t\tif (s == 0u) {
\t\t\t\tcontinue;
\t\t\t}
\t\t\tAabb acc = t->nodes[t->sorted[o]].bounds;
\t\t\tfor (uint32_t j = o + 1u; j < o + s; j++) {
\t\t\t\tacc = aabb_union(&acc, &t->nodes[t->sorted[j]].bounds);
\t\t\t}
\t\t\tn->bounds = acc;
\t\t} else if (n->left != PBVH_NULL_NODE && n->right != PBVH_NULL_NODE) {
\t\t\tn->bounds = aabb_union(&t->internals[n->left].bounds,
\t\t\t\t\t&t->internals[n->right].bounds);
\t\t} else {
\t\t\tconst pbvh_internal_id_t only =
\t\t\t\t\t(n->left != PBVH_NULL_NODE) ? n->left : n->right;
\t\t\tn->bounds = t->internals[only].bounds;
\t\t}
\t}
}

/* Insertion sort sorted[] by hilbert, then build the internal tree and
 * (if provided) the bucket directory. O(N) on near-sorted input. */
static inline void pbvh_tree_build(pbvh_tree_t *t) {
\tuint32_t k = 0;
\tfor (uint32_t i = 0; i < t->count; i++) {
\t\tif (t->nodes[i].is_leaf) {
\t\t\tt->sorted[k++] = (pbvh_node_id_t)i;
\t\t}
\t}
\tt->sorted_count = k;
\tfor (uint32_t i = 1; i < k; i++) {
\t\tpbvh_node_id_t cur = t->sorted[i];
\t\tuint32_t cur_h = t->nodes[cur].hilbert;
\t\tuint32_t j = i;
\t\twhile (j > 0 && t->nodes[t->sorted[j - 1]].hilbert > cur_h) {
\t\t\tt->sorted[j] = t->sorted[j - 1];
\t\t\tj--;
\t\t}
\t\tt->sorted[j] = cur;
\t}
\tt->internal_count = 0u;
\tt->internal_root = PBVH_NULL_NODE;
\tif (t->internals != NULL && t->internal_capacity > 0u && k > 0u) {
\t\tt->internal_root = pbvh_build_internal_(t, 0u, k);
\t}
\tpbvh_build_bucket_dir_(t);
}

/* O(N) brute-force leaf scan. Kept only as the correctness oracle for
 * tests; production paths should use _n or _b. Sets last_visits. */
static inline void pbvh_tree_aabb_query(pbvh_tree_t *t, const Aabb *query,
\t\tint (*cb)(pbvh_eclass_id_t, void *), void *ud) {
\tconst uint32_t n = t->count;
\tuint32_t visits = 0;
\tfor (uint32_t i = 0; i < n; i++) {
\t\tconst pbvh_node_t *node = &t->nodes[i];
\t\tif (!node->is_leaf) {
\t\t\tcontinue;
\t\t}
\t\tvisits++;
\t\tif (aabb_overlaps(&node->bounds, query)) {
\t\t\tif (cb(node->eclass, ud) != 0) {
\t\t\t\tt->last_visits = visits;
\t\t\t\treturn;
\t\t\t}
\t\t}
\t}
\tt->last_visits = visits;
}

/* Iterative nested-set descent. Walks internals[] in pre-order; on a bounds
 * miss, jumps straight to internals[i].skip, which is the index past the
 * entire pruned subtree — a single assignment, no stack, no recursion.
 * On a leaf-range node, iterates sorted[offset .. offset+span) then jumps
 * to skip. Requires internals[] to have been built. */
static inline void pbvh_tree_aabb_query_n(pbvh_tree_t *t, const Aabb *query,
\t\tint (*cb)(pbvh_eclass_id_t, void *), void *ud) {
\tuint32_t visits = 0u;
\tif (t->internal_root == PBVH_NULL_NODE) {
\t\tt->last_visits = 0u;
\t\treturn;
\t}
\tuint32_t i = t->internal_root;
\tconst uint32_t end = t->internal_count;
\twhile (i < end) {
\t\tconst pbvh_internal_t *n = &t->internals[i];
\t\tif (!aabb_overlaps(&n->bounds, query)) {
\t\t\ti = n->skip;
\t\t\tcontinue;
\t\t}
\t\tif (n->left == PBVH_NULL_NODE && n->right == PBVH_NULL_NODE) {
\t\t\tconst uint32_t o = n->offset;
\t\t\tconst uint32_t s = n->span;
\t\t\tfor (uint32_t j = o; j < o + s; j++) {
\t\t\t\tconst pbvh_node_t *leaf = &t->nodes[t->sorted[j]];
\t\t\t\tif (!leaf->is_leaf) {
\t\t\t\t\tcontinue;
\t\t\t\t}
\t\t\t\tvisits++;
\t\t\t\tif (aabb_overlaps(&leaf->bounds, query)) {
\t\t\t\t\tif (cb(leaf->eclass, ud) != 0) {
\t\t\t\t\t\tt->last_visits = visits;
\t\t\t\t\t\treturn;
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t\t\ti = n->skip;
\t\t\tcontinue;
\t\t}
\t\ti++; /* descend: next DFS index is the left child */
\t}
\tt->last_visits = visits;
}

/* Bucket-directory query. Given the query's Hilbert code, computes the
 * owning prefix bucket in O(1) and iterates only the leaves in that window.
 * Total cost is O(1 + k) where k is the bucket's leaf count — strictly
 * better than the O(log N) descent of _n for queries the caller can tag
 * with a Hilbert code. Falls through to _n if bucket_dir wasn't built. */
static inline void pbvh_tree_aabb_query_b(pbvh_tree_t *t, const Aabb *query,
\t\tuint32_t query_hilbert,
\t\tint (*cb)(pbvh_eclass_id_t, void *), void *ud) {
\tif (t->bucket_dir == NULL || t->bucket_bits == 0u) {
\t\tpbvh_tree_aabb_query_n(t, query, cb, ud);
\t\treturn;
\t}
\tconst uint32_t shift = 30u - t->bucket_bits;
\tconst uint32_t b = query_hilbert >> shift;
\tconst uint32_t B = 1u << t->bucket_bits;
\tif (b >= B) {
\t\tpbvh_tree_aabb_query_n(t, query, cb, ud);
\t\treturn;
\t}
\tconst uint32_t lo = t->bucket_dir[2u * b];
\tconst uint32_t hi = t->bucket_dir[2u * b + 1u];
\tuint32_t visits = 0u;
\tfor (uint32_t j = lo; j < hi; j++) {
\t\tconst pbvh_node_t *leaf = &t->nodes[t->sorted[j]];
\t\tif (!leaf->is_leaf) {
\t\t\tcontinue;
\t\t}
\t\tvisits++;
\t\tif (aabb_overlaps(&leaf->bounds, query)) {
\t\t\tif (cb(leaf->eclass, ud) != 0) {
\t\t\t\tt->last_visits = visits;
\t\t\t\treturn;
\t\t\t}
\t\t}
\t}
\tt->last_visits = visits;
}

/* Eclass-style self-query: look up the leaf that stores eclass `self` and
 * run _b using its stored bounds + hilbert. Skips `self` in results so the
 * callback only sees \"other\" eclasses that overlap. Caller works in eclass
 * IDs end-to-end; no AABB pointers, no Hilbert codes threaded through. */
typedef struct pbvh_eclass_skip_ud {
\tpbvh_eclass_id_t self;
\tint (*inner_cb)(pbvh_eclass_id_t, void *);
\tvoid *inner_ud;
} pbvh_eclass_skip_ud_t;

static inline int pbvh_eclass_skip_cb_(pbvh_eclass_id_t other, void *ud) {
\tpbvh_eclass_skip_ud_t *s = (pbvh_eclass_skip_ud_t *)ud;
\tif (other == s->self) {
\t\treturn 0;
\t}
\treturn s->inner_cb(other, s->inner_ud);
}

static inline void pbvh_tree_query_eclass(pbvh_tree_t *t, pbvh_eclass_id_t self,
\t\tint (*cb)(pbvh_eclass_id_t, void *), void *ud) {
\tconst uint32_t n = t->count;
\tfor (uint32_t i = 0; i < n; i++) {
\t\tconst pbvh_node_t *node = &t->nodes[i];
\t\tif (!node->is_leaf || node->eclass != self) {
\t\t\tcontinue;
\t\t}
\t\tpbvh_eclass_skip_ud_t s = { self, cb, ud };
\t\tpbvh_tree_aabb_query_b(t, &node->bounds, node->hilbert,
\t\t\t\tpbvh_eclass_skip_cb_, &s);
\t\treturn;
\t}
}

/* Enumerate every overlapping (a, b) pair with a.eclass < b.eclass exactly
 * once. Pure eclass-style API — no caller-side AABBs, no Hilbert threading,
 * just two eclass IDs per pair. Uses _n (nested-set skip descent) so ghost
 * AABBs that span multiple Hilbert cells stay correct. */
typedef struct pbvh_pair_enum_ud {
\tpbvh_eclass_id_t self;
\tint matched_count;
\tint (*pair_cb)(pbvh_eclass_id_t, pbvh_eclass_id_t, void *);
\tvoid *pair_ud;
} pbvh_pair_enum_ud_t;

static inline int pbvh_pair_enum_cb_(pbvh_eclass_id_t other, void *ud) {
\tpbvh_pair_enum_ud_t *p = (pbvh_pair_enum_ud_t *)ud;
\tif (other <= p->self) {
\t\treturn 0;
\t}
\tp->matched_count++;
\treturn p->pair_cb(p->self, other, p->pair_ud);
}

static inline int pbvh_tree_enumerate_pairs(pbvh_tree_t *t,
\t\tint (*pair_cb)(pbvh_eclass_id_t, pbvh_eclass_id_t, void *), void *ud) {
\tint pairs = 0;
\tfor (uint32_t i = 0; i < t->count; i++) {
\t\tconst pbvh_node_t *node = &t->nodes[i];
\t\tif (!node->is_leaf) {
\t\t\tcontinue;
\t\t}
\t\tpbvh_pair_enum_ud_t p = { node->eclass, 0, pair_cb, ud };
\t\tpbvh_tree_aabb_query_n(t, &node->bounds,
\t\t\t\tpbvh_pair_enum_cb_, &p);
\t\tpairs += p.matched_count;
\t}
\treturn pairs;
}
"

def treeC : String := treeBanner ++ treeBody

end PredictiveBVH.Codegen.TreeC
