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

/* 4-pass LSD radix sort of sorted[] by 30-bit hilbert (O(N)), then build
 * the internal tree and (if provided) the bucket directory. The radix
 * passes reuse t->internals[] as a pbvh_node_id_t scratch buffer — its
 * contents are overwritten immediately after by pbvh_build_internal_, and
 * sizeof(pbvh_internal_t) >= sizeof(pbvh_node_id_t) with internal_capacity
 * >= count so the aliasing is in-bounds. Four passes is even, so the sorted
 * result lands back in t->sorted[] without a final copy. */
static inline void pbvh_tree_build(pbvh_tree_t *t) {
\tuint32_t k = 0;
\tfor (uint32_t i = 0; i < t->count; i++) {
\t\tif (t->nodes[i].is_leaf) {
\t\t\tt->sorted[k++] = (pbvh_node_id_t)i;
\t\t}
\t}
\tt->sorted_count = k;
\tif (k > 1u && t->internals != NULL && t->internal_capacity >= k) {
\t\tpbvh_node_id_t *scratch = (pbvh_node_id_t *)t->internals;
\t\tpbvh_node_id_t *src = t->sorted;
\t\tpbvh_node_id_t *dst = scratch;
\t\tfor (uint32_t pass = 0u; pass < 4u; pass++) {
\t\t\tuint32_t count_bin[256];
\t\t\tfor (uint32_t b = 0u; b < 256u; b++) { count_bin[b] = 0u; }
\t\t\tconst uint32_t shift = pass * 8u;
\t\t\tfor (uint32_t i = 0u; i < k; i++) {
\t\t\t\tuint32_t b = (t->nodes[src[i]].hilbert >> shift) & 0xFFu;
\t\t\t\tcount_bin[b]++;
\t\t\t}
\t\t\tuint32_t sum = 0u;
\t\t\tfor (uint32_t b = 0u; b < 256u; b++) {
\t\t\t\tuint32_t c = count_bin[b];
\t\t\t\tcount_bin[b] = sum;
\t\t\t\tsum += c;
\t\t\t}
\t\t\tfor (uint32_t i = 0u; i < k; i++) {
\t\t\t\tuint32_t b = (t->nodes[src[i]].hilbert >> shift) & 0xFFu;
\t\t\t\tdst[count_bin[b]++] = src[i];
\t\t\t}
\t\t\tpbvh_node_id_t *tmp = src; src = dst; dst = tmp;
\t\t}
\t} else if (k > 1u) {
\t\t/* Fallback insertion sort when no internals scratch is attached.
\t\t * Production paths always supply internals; this branch exists for
\t\t * tiny harnesses that skip the allocation. */
\t\tfor (uint32_t i = 1u; i < k; i++) {
\t\t\tpbvh_node_id_t cur = t->sorted[i];
\t\t\tuint32_t cur_h = t->nodes[cur].hilbert;
\t\t\tuint32_t j = i;
\t\t\twhile (j > 0u && t->nodes[t->sorted[j - 1u]].hilbert > cur_h) {
\t\t\t\tt->sorted[j] = t->sorted[j - 1u];
\t\t\t\tj--;
\t\t\t}
\t\t\tt->sorted[j] = cur;
\t\t}
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

/* ── Phase 2b primitives: ray, convex, clear, is_empty, optimize, index ─── */

/* Oriented half-space {p : normal · p + d >= 0}. Kept side is positive. */
typedef struct pbvh_plane {
\tR128 nx, ny, nz;
\tR128 d;
} pbvh_plane_t;

/* Build the segment-AABB of a ray segment from (ox,oy,oz) to (tx,ty,tz).
 * Conservative broadphase: a segment hits `b` only if its AABB overlaps `b`. */
static inline Aabb pbvh_segment_aabb_(R128 ox, R128 oy, R128 oz,
\t\tR128 tx, R128 ty, R128 tz) {
\tAabb s;
\ts.min_x = r128_le(ox, tx) ? ox : tx;
\ts.max_x = r128_le(ox, tx) ? tx : ox;
\ts.min_y = r128_le(oy, ty) ? oy : ty;
\ts.max_y = r128_le(oy, ty) ? ty : oy;
\ts.min_z = r128_le(oz, tz) ? oz : tz;
\ts.max_z = r128_le(oz, tz) ? tz : oz;
\treturn s;
}

/* Iterative skip-pointer descent over internals[] using a ray segment. Every
 * live leaf whose AABB overlaps the segment's AABB has its eclass passed to
 * `cb`. Callback returns nonzero to stop early. Mirrors _n's traversal shape
 * exactly; only the prune predicate changes. Emitted from Spatial/Tree.lean
 * `rayQueryN`; soundness of a tight slab test is deferred to Phase 2b'. */
static inline void pbvh_tree_ray_query(pbvh_tree_t *t,
\t\tR128 ox, R128 oy, R128 oz, R128 tx, R128 ty, R128 tz,
\t\tint (*cb)(pbvh_eclass_id_t, void *), void *ud) {
\tif (t->internal_root == PBVH_NULL_NODE) {
\t\treturn;
\t}
\tconst Aabb seg = pbvh_segment_aabb_(ox, oy, oz, tx, ty, tz);
\tuint32_t i = t->internal_root;
\tconst uint32_t end = t->internal_count;
\twhile (i < end) {
\t\tconst pbvh_internal_t *n = &t->internals[i];
\t\tif (!aabb_overlaps(&n->bounds, &seg)) {
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
\t\t\t\tif (aabb_overlaps(&leaf->bounds, &seg)) {
\t\t\t\t\tif (cb(leaf->eclass, ud) != 0) {
\t\t\t\t\t\treturn;
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t\t\ti = n->skip;
\t\t\tcontinue;
\t\t}
\t\ti++;
\t}
}

/* Half-space test: does AABB `b` have any corner `c` satisfying
 * normal · c + d >= 0 ? If every corner is strictly below the plane,
 * the entire box is rejected. Unrolled 8-corner loop in R128. */
static inline bool pbvh_half_space_keeps_(const pbvh_plane_t *p, const Aabb *b) {
\tconst R128 zero = r128_from_int(0);
\tR128 xs[2]; xs[0] = b->min_x; xs[1] = b->max_x;
\tR128 ys[2]; ys[0] = b->min_y; ys[1] = b->max_y;
\tR128 zs[2]; zs[0] = b->min_z; zs[1] = b->max_z;
\tfor (int ix = 0; ix < 2; ix++) {
\t\tfor (int iy = 0; iy < 2; iy++) {
\t\t\tfor (int iz = 0; iz < 2; iz++) {
\t\t\t\tR128 dot = r128_add(r128_add(r128_mul(p->nx, xs[ix]),
\t\t\t\t\t\tr128_mul(p->ny, ys[iy])),
\t\t\t\t\t\tr128_mul(p->nz, zs[iz]));
\t\t\t\tR128 val = r128_add(dot, p->d);
\t\t\t\tif (r128_le(zero, val)) {
\t\t\t\t\treturn true;
\t\t\t\t}
\t\t\t}
\t\t}
\t}
\treturn false;
}

static inline bool pbvh_convex_keeps_box_(const pbvh_plane_t *planes,
\t\tuint32_t plane_count, const Aabb *b) {
\tfor (uint32_t k = 0; k < plane_count; k++) {
\t\tif (!pbvh_half_space_keeps_(&planes[k], b)) {
\t\t\treturn false;
\t\t}
\t}
\treturn true;
}

/* Convex-hull broadphase: every live leaf whose AABB has at least one corner
 * on the kept side of every plane is passed to `cb`. Hull `points` parameter
 * is accepted for DynamicBVH-FFI parity (convex_query callers pass both a
 * plane list and the hull vertices); we use plane-only pruning which is the
 * safer over-approximation. Callback returns nonzero to stop early. */
static inline void pbvh_tree_convex_query(pbvh_tree_t *t,
\t\tconst pbvh_plane_t *planes, uint32_t plane_count,
\t\tconst R128 *points, uint32_t point_count,
\t\tint (*cb)(pbvh_eclass_id_t, void *), void *ud) {
\t(void)points; (void)point_count;
\tif (t->internal_root == PBVH_NULL_NODE || plane_count == 0u) {
\t\treturn;
\t}
\tuint32_t i = t->internal_root;
\tconst uint32_t end = t->internal_count;
\twhile (i < end) {
\t\tconst pbvh_internal_t *n = &t->internals[i];
\t\tif (!pbvh_convex_keeps_box_(planes, plane_count, &n->bounds)) {
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
\t\t\t\tif (pbvh_convex_keeps_box_(planes, plane_count, &leaf->bounds)) {
\t\t\t\t\tif (cb(leaf->eclass, ud) != 0) {
\t\t\t\t\t\treturn;
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}
\t\t\ti = n->skip;
\t\t\tcontinue;
\t\t}
\t\ti++;
\t}
}

/* Reset the tree to empty. Preserves caller-owned buffer pointers/capacities
 * and the `index` tag; zeroes every *_count and clears the free list. */
static inline void pbvh_tree_clear(pbvh_tree_t *t) {
\tt->count = 0u;
\tt->sorted_count = 0u;
\tt->internal_count = 0u;
\tt->root = PBVH_NULL_NODE;
\tt->free_head = PBVH_NULL_NODE;
\tt->internal_root = PBVH_NULL_NODE;
\tt->last_visits = 0u;
}

/* True iff the tree has no live leaves (no live `is_leaf` node). */
static inline bool pbvh_tree_is_empty(const pbvh_tree_t *t) {
\tfor (uint32_t i = 0; i < t->count; i++) {
\t\tif (t->nodes[i].is_leaf) {
\t\t\treturn false;
\t\t}
\t}
\treturn true;
}

/* Phase 2c: per-frame dirty-leaf entry handed to pbvh_tree_tick. old_hilbert
 * is the Hilbert code the leaf had on the previous build/tick; the current
 * code lives in t->nodes[leaf_id].hilbert. Comparing the two, masked by
 * bucket_bits, classifies the leaf as stayed-in-bucket (refit-compatible)
 * vs crossed-boundary (needs full rebuild). */
typedef struct pbvh_dirty_leaf {
\tpbvh_node_id_t leaf_id;
\tuint32_t old_hilbert;
} pbvh_dirty_leaf_t;

/* Per-frame rebalance. When every dirty leaf kept its Hilbert-prefix bucket
 * (so sorted[] order and internals[] topology are still valid), we can skip
 * the O(N) sort+build and just re-union bounds bottom-up via pbvh_tree_refit
 * — O(internal_count) sequential reads. Any condition that could leave
 * sorted[] / internals[] out of sync with the current leaf set forces a
 * full pbvh_tree_build. The conditions are enumerated in order of cost:
 *
 *   (1) trivial: empty dirty list, NULL dirty pointer, or bucket_bits out
 *       of range (0 or >30). Cheap to check; same cost as a full build.
 *   (2) structural: NULL t or t->nodes. Defensive; refit would crash.
 *   (3) insert since build: t->count > t->sorted_count means at least one
 *       leaf was allocated in nodes[] after the last build and is therefore
 *       NOT indexed in sorted[]. Refit cannot reach it and queries would
 *       silently miss it. This is the main adversarial-caller footgun we
 *       harden against: a consumer that does insert() → tick() without an
 *       intermediate build() would lose the inserted leaf without this
 *       check.
 *   (4) empty internals: nothing built yet; refit is a no-op that leaves
 *       internal_root == PBVH_NULL_NODE, queries return empty. A build
 *       from scratch is the correct recovery.
 *   (5) per-leaf: each dirty entry must name a live leaf within sorted[]'s
 *       address range and must not have crossed its Hilbert prefix bucket.
 *       Out-of-range leaf_id is silently skipped (caller may have stale
 *       IDs); is_leaf=0 or bucket crossing forces a build. Callers that
 *       lie about old_hilbert are not a correctness risk — refit unions
 *       the current bounds, so inflated internal AABBs over-emit rather
 *       than under-emit.
 *
 * Passing (dirty=NULL, dirty_count=0) is an explicit \"reset internals
 * from current leaves\" request and behaves as pbvh_tree_build. */
static inline void pbvh_tree_tick(pbvh_tree_t *t,
\t\tconst pbvh_dirty_leaf_t *dirty, uint32_t dirty_count) {
\t/* (2) Defensive NULL guard. */
\tif (t == NULL || t->nodes == NULL) {
\t\treturn;
\t}
\t/* (1) Trivial fallback. */
\tif (dirty_count == 0u || dirty == NULL || t->bucket_bits == 0u ||
\t\t\tt->bucket_bits > 30u) {
\t\tpbvh_tree_build(t);
\t\treturn;
\t}
\t/* (3) Inserts since last build are invisible to sorted[]/internals[];
\t * only a full rebuild can pick them up. */
\tif (t->count > t->sorted_count) {
\t\tpbvh_tree_build(t);
\t\treturn;
\t}
\t/* (4) No internals yet → nothing to refit; build instead. */
\tif (t->internal_count == 0u || t->internal_root == PBVH_NULL_NODE) {
\t\tpbvh_tree_build(t);
\t\treturn;
\t}
\tconst uint32_t shift = 30u - t->bucket_bits;
\tfor (uint32_t i = 0; i < dirty_count; i++) {
\t\tconst pbvh_dirty_leaf_t *d = &dirty[i];
\t\t/* (5a) Stale/out-of-range leaf_id: caller may hold ids past remove;
\t\t * skipping is safe because the slot contributes nothing to queries. */
\t\tif (d->leaf_id >= t->count) {
\t\t\tcontinue;
\t\t}
\t\tconst pbvh_node_t *n = &t->nodes[d->leaf_id];
\t\t/* (5b) Dead slot → topology changed. */
\t\tif (!n->is_leaf) {
\t\t\tpbvh_tree_build(t);
\t\t\treturn;
\t\t}
\t\t/* (5c) Bucket boundary crossed → sorted[] order is stale. */
\t\tif ((n->hilbert >> shift) != (d->old_hilbert >> shift)) {
\t\t\tpbvh_tree_build(t);
\t\t\treturn;
\t\t}
\t}
\t/* All dirty leaves stayed in their bucket and every precondition holds:
\t * bounds-only refit suffices. */
\tpbvh_tree_refit(t);
}

/* DynamicBVH-parity wrapper: ignore `passes`, route through pbvh_tree_tick
 * with an empty dirty list → pbvh_tree_build. Consumers that want the
 * Phase 2c fast path call pbvh_tree_tick directly with their dirty list. */
static inline void pbvh_tree_optimize_incremental(pbvh_tree_t *t, int passes) {
\t(void)passes;
\tpbvh_tree_tick(t, NULL, 0u);
}

/* Opaque uint32 tag for consumers that multiplex multiple trees (e.g.
 * RendererSceneCull::Scenario::indexers[] distinguishes GEOMETRY/VOLUMES).
 * Stored in bucket_bits' high bits is avoided; the adapter allocates a
 * dedicated member on the C++ side. These two accessors exist only so the
 * adapter surface matches DynamicBVH byte-for-byte. Stored in t->bucket_bits
 * is unavailable (it has spatial meaning), so this pair operates on a
 * separate caller-owned `uint32_t *out_index` the adapter threads alongside. */
static inline uint32_t pbvh_tree_get_index(const uint32_t *idx_slot) {
\treturn *idx_slot;
}

static inline void pbvh_tree_set_index(uint32_t *idx_slot, uint32_t idx) {
\t*idx_slot = idx;
}
"

def treeC : String := treeBanner ++ treeBody

end PredictiveBVH.Codegen.TreeC
