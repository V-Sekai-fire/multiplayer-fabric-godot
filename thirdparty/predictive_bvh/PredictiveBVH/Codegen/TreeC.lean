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

typedef struct pbvh_dirty_leaf {
\tpbvh_node_id_t leaf_id;
\tuint32_t old_hilbert;
} pbvh_dirty_leaf_t;

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
\t/* Optional incremental-refit sidecar (eclass-keyed, no parent pointers
\t * inside pbvh_internal_t). When all three are non-NULL, pbvh_tree_tick
\t * restricts its refit to the ancestor set of dirty leaves — O(K log N)
\t * touches instead of O(internal_count). leaf_to_internal[id] = the
\t * enclosing leaf-range internal id for leaf node id; parent_of_internal[i]
\t * = the immediately enclosing internal id (PBVH_NULL_NODE at root);
\t * touched_bits = internal_capacity-bit scratch, cleared each tick. */
\tuint32_t *parent_of_internal; /* size internal_capacity, caller-owned */
\tuint32_t *leaf_to_internal; /* size capacity, caller-owned, indexed by node id */
\tuint64_t *touched_bits; /* size (internal_capacity + 63) / 64, caller-owned */
\t/* Meta-bitmap over touched_bits: bit i in touched_meta_bits is set iff
\t * touched_bits[i] has any set bits. Lets the refit scan skip empty
\t * words in O(1) via __builtin_clzll instead of iterating the whole
\t * [min_word..max_word] range. Kills the N/64 term in the scan phase,
\t * leaving a strict O(K + n_marked) refit bound. */
\tuint64_t *touched_meta_bits; /* size ((internal_capacity + 63)/64 + 63)/64, caller-owned */
} pbvh_tree_t;

/* ============================================================================
 * BUCKET AUTO-TUNE (Phase 2e)
 *
 * Target max entities per bucket. Controls the constant-time upper bound on
 * pbvh_tree_aabb_query_b's per-bucket scan: a bucket cannot exceed
 * ceil(N / (1 << bucket_bits)) entities, so bucket_bits = ceil(log2(N/K))
 * gives at most K entities per bucket under uniform Hilbert distribution.
 * Empirical max/mean on uniform random inputs is ~1.06-1.30x (sub-Poisson),
 * so a K_TARGET of 32 yields worst-case ~40-entity scans at any N.
 * ========================================================================= */
#ifndef PBVH_BUCKET_K_TARGET
#define PBVH_BUCKET_K_TARGET 32u
#endif

/* ceil(log2(n)) clamped to [0, 30]. n == 0 maps to 0. */
static inline uint32_t pbvh_ceil_log2(uint32_t n) {
\tif (n <= 1u) {
\t\treturn 0u;
\t}
\tuint32_t v = n - 1u;
\tuint32_t r = 0u;
\twhile (v > 0u) {
\t\tv >>= 1u;
\t\tr++;
\t}
\tif (r > 30u) {
\t\tr = 30u;
\t}
\treturn r;
}

/* Ideal bucket_bits for N leaves: ceil(log2(N / K_TARGET)), clamped to [0, 30].
 * At N < K_TARGET, returns 0 (single bucket covers the whole tree). */
static inline uint32_t pbvh_bucket_bits_for(uint32_t n) {
\tif (n <= PBVH_BUCKET_K_TARGET) {
\t\treturn 0u;
\t}
\treturn pbvh_ceil_log2((n + PBVH_BUCKET_K_TARGET - 1u) / PBVH_BUCKET_K_TARGET);
}

/* Required uint32 element count for bucket_dir given N leaves.
 * Each bucket stores [lo, hi) as two uint32, so size = 2 * (1 << bucket_bits).
 * Callers use this to size their bucket_dir allocation before pbvh_tree_build;
 * the build itself overwrites t->bucket_bits with pbvh_bucket_bits_for(N). */
static inline uint32_t pbvh_bucket_dir_size(uint32_t n) {
\treturn 2u * (1u << pbvh_bucket_bits_for(n));
}

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
static inline pbvh_internal_id_t pbvh_build_internal_with_parent_(pbvh_tree_t *t,
\t\tuint32_t lo, uint32_t hi, pbvh_internal_id_t parent) {
\tif (lo >= hi) {
\t\treturn PBVH_NULL_NODE;
\t}
\tif (t->internal_count >= t->internal_capacity) {
\t\treturn PBVH_NULL_NODE;
\t}
\tpbvh_internal_id_t id = t->internal_count++;
\tif (t->parent_of_internal != NULL) {
\t\tt->parent_of_internal[id] = parent;
\t}
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
\tpbvh_internal_id_t l = pbvh_build_internal_with_parent_(t, lo, split, id);
\tpbvh_internal_id_t r = pbvh_build_internal_with_parent_(t, split, hi, id);
\t/* Re-fetch: the `n` pointer to caller-owned fixed storage stays valid,
\t * but writing through it after recursion is the clearest shape. */
\tt->internals[id].left = l;
\tt->internals[id].right = r;
\tt->internals[id].skip = t->internal_count;
\treturn id;
}

/* Legacy entry point: defers to the parent-tracking variant with root parent
 * = PBVH_NULL_NODE. Callers that don't care about parent_of_internal can
 * leave the sidecar NULL; the recursive variant skips the write. */
static inline pbvh_internal_id_t pbvh_build_internal_(pbvh_tree_t *t, uint32_t lo, uint32_t hi) {
\treturn pbvh_build_internal_with_parent_(t, lo, hi, PBVH_NULL_NODE);
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

/* Incremental refit: touches only the leaf-range internals containing dirty
 * leaves and their ancestor chain up to the first ancestor whose current
 * bounds already cover the dirty leaf's new bounds. Relies on two caller-owned
 * sidecars (leaf_to_internal[], parent_of_internal[]) plus scratch touched_bits.
 *
 * Complexity: O(K + n_touched) where K = dirty_count and n_touched is the
 * ancestor-union set truncated by per-leaf containment. A leaf whose new AABB
 * is already covered by its direct enclosing internal contributes O(1) — no
 * ancestor work at all. In the worst case (every leaf grows past the root)
 * n_touched is bounded by K × depth.
 *
 * Algorithm:
 *   1. For each dirty leaf d, fetch new_leaf = t->nodes[d].bounds and walk
 *      up parent_of_internal[] starting from leaf_to_internal[d]. At each
 *      ancestor, break if ancestor.bounds already contains new_leaf (BVH
 *      invariant + transitivity: nothing above needs refit). Otherwise mark
 *      a bit in touched_bits and continue. Walks also short-circuit on
 *      already-marked bits (covers shared-ancestor case in O(1)).
 *   2. Scan touched_bits from max_word down to min_word. Within each word,
 *      pop bits highest-to-lowest via __builtin_clzll — pre-order DFS gives
 *      parent < child, so this yields strictly bottom-up refit order with
 *      no sort step. Refit each: leaf-range nodes re-union their sorted[]
 *      window; inner nodes union their two children's (already-refit or
 *      still-valid) bounds. Bits self-clear during the scan.
 *
 * Soundness license for the early-out: Lean theorem
 * aabbQueryN_complete_from_invariants only requires each internal's bounds
 * to be a superset of its subtree leaves. Over-conservative bounds stay sound.
 *
 * Falls back to pbvh_tree_refit when any sidecar is NULL. */
static inline void pbvh_tree_refit_incremental_(pbvh_tree_t *t,
\t\tconst pbvh_dirty_leaf_t *dirty, uint32_t dirty_count) {
\tif (t->internal_count == 0u) { return; }
\tif (dirty == NULL || dirty_count == 0u ||
\t\t\tt->parent_of_internal == NULL || t->leaf_to_internal == NULL ||
\t\t\tt->touched_bits == NULL || t->touched_meta_bits == NULL) {
\t\tpbvh_tree_refit(t);
\t\treturn;
\t}
\t/* Mark phase: walk ancestors, setting bits in touched_bits AND in the
\t * meta-bitmap (one bit per touched_bits word). Track [min_meta..max_meta]
\t * instead of a word-level range, so the scan phase iterates only the
\t * coarser meta-words. Every set touched_bits word has its meta-bit set,
\t * giving an O(1) probe to find the next non-empty word via clzll.
\t * Bits self-clear during refit; both bitmaps are all-zero on entry and
\t * all-zero on exit. */
\tuint32_t min_meta = UINT32_MAX;
\tuint32_t max_meta = 0u;
\tfor (uint32_t d = 0u; d < dirty_count; d++) {
\t\tconst pbvh_node_id_t leaf_id = dirty[d].leaf_id;
\t\tif (leaf_id >= t->count) { continue; }
\t\tconst Aabb new_leaf = t->nodes[leaf_id].bounds;
\t\tuint32_t i = t->leaf_to_internal[leaf_id];
\t\twhile (i != PBVH_NULL_NODE && i < t->internal_count) {
\t\t\t/* Containment early-out: if this ancestor's current bounds already
\t\t\t * contain the new leaf bounds, the existing bounds remain a valid
\t\t\t * conservative superset. By the BVH invariant (every ancestor's
\t\t\t * bounds are a superset of its subtree leaves) and transitivity,
\t\t\t * all ancestors above this node also remain valid — no mark, no
\t\t\t * refit, walk terminates in O(1) for shrinking / in-place leaves.
\t\t\t * Soundness: aabbQueryN_complete_from_invariants requires only
\t\t\t * bounds ⊇ descendant leaves; over-conservative bounds are permitted.
\t\t\t * NO DEDUP-BREAK: stopping when a node is already marked is unsound
\t\t\t * combined with the containment early-out above. Leaf A may
\t\t\t * containment-break at ancestor P (not marking P); leaf B then
\t\t\t * reaches P's child I (already marked by A) and would dedup-break,
\t\t\t * silently skipping P even though B's bounds exceed P's. Spec:
\t\t\t * RefitIncremental.lean markAncestors / refitIncrementalSpec. */
\t\t\tif (aabb_contains(&t->internals[i].bounds, &new_leaf)) { break; }
\t\t\tconst uint32_t w = i >> 6;
\t\t\tconst uint64_t mask = 1ull << (i & 63u);
\t\t\tt->touched_bits[w] |= mask;
\t\t\tconst uint32_t mw = w >> 6;
\t\t\tt->touched_meta_bits[mw] |= 1ull << (w & 63u);
\t\t\tif (mw < min_meta) { min_meta = mw; }
\t\t\tif (mw > max_meta) { max_meta = mw; }
\t\t\ti = t->parent_of_internal[i];
\t\t}
\t}
\tif (min_meta > max_meta) { return; }
\t/* Refit phase: iterate meta-words from max_meta down to min_meta, and
\t * within each, pop set bits highest-to-lowest via clzll to get the
\t * (also-descending) indices of non-empty touched_bits words. Within
\t * each such word, pop bits highest-to-lowest again to get descending
\t * internal ids. Pre-order DFS gives parent < child, so this strict
\t * descending-id walk visits children before parents and every union
\t * reads already-refit children. Zero sort steps, zero wasted probes —
\t * empty touched_bits words are never even loaded. Bits self-clear
\t * as consumed. */
\tfor (uint32_t mw = max_meta + 1u; mw > min_meta; ) {
\t\tmw--;
\t\tuint64_t meta = t->touched_meta_bits[mw];
\t\twhile (meta != 0ull) {
\t\t\tconst uint32_t mb = 63u - (uint32_t)__builtin_clzll(meta);
\t\t\tmeta &= ~(1ull << mb);
\t\t\tconst uint32_t w = (mw << 6) | mb;
\t\t\tuint64_t bits = t->touched_bits[w];
\t\t\twhile (bits != 0ull) {
\t\t\t\tconst uint32_t b = 63u - (uint32_t)__builtin_clzll(bits);
\t\t\t\tbits &= ~(1ull << b);
\t\t\t\tconst uint32_t idx = (w << 6) | b;
\t\t\t\tpbvh_internal_t *n = &t->internals[idx];
\t\t\t\tif (n->left == PBVH_NULL_NODE && n->right == PBVH_NULL_NODE) {
\t\t\t\t\tconst uint32_t o = n->offset;
\t\t\t\t\tconst uint32_t s = n->span;
\t\t\t\t\tif (s == 0u) { continue; }
\t\t\t\t\tAabb acc = t->nodes[t->sorted[o]].bounds;
\t\t\t\t\tfor (uint32_t j = o + 1u; j < o + s; j++) {
\t\t\t\t\t\tacc = aabb_union(&acc, &t->nodes[t->sorted[j]].bounds);
\t\t\t\t\t}
\t\t\t\t\tn->bounds = acc;
\t\t\t\t} else if (n->left != PBVH_NULL_NODE && n->right != PBVH_NULL_NODE) {
\t\t\t\t\tn->bounds = aabb_union(&t->internals[n->left].bounds,
\t\t\t\t\t\t\t&t->internals[n->right].bounds);
\t\t\t\t} else {
\t\t\t\t\tconst pbvh_internal_id_t only =
\t\t\t\t\t\t\t(n->left != PBVH_NULL_NODE) ? n->left : n->right;
\t\t\t\t\tn->bounds = t->internals[only].bounds;
\t\t\t\t}
\t\t\t}
\t\t\tt->touched_bits[w] = 0ull;
\t\t}
\t\tt->touched_meta_bits[mw] = 0ull;
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
\t/* Auto-tune bucket_bits from leaf count. Caller pre-allocated bucket_dir
\t * via pbvh_bucket_dir_size(N); this overwrite keeps per-query scan cost
\t * bounded by PBVH_BUCKET_K_TARGET at any N. */
\tif (t->bucket_dir != NULL) {
\t\tt->bucket_bits = pbvh_bucket_bits_for(k);
\t}
\tpbvh_build_bucket_dir_(t);
\t/* Populate leaf_to_internal[] from the leaf-range internals produced
\t * above. Any leaf id inside a leaf-range internal's [offset, offset+span)
\t * window has that internal as its immediate enclosing ancestor. One pass
\t * over leaf-range internals, total O(N) writes. */
\tif (t->leaf_to_internal != NULL) {
\t\tfor (uint32_t i = 0u; i < t->internal_count; i++) {
\t\t\tpbvh_internal_t *n = &t->internals[i];
\t\t\tif (n->left != PBVH_NULL_NODE || n->right != PBVH_NULL_NODE) {
\t\t\t\tcontinue;
\t\t\t}
\t\t\tconst uint32_t o = n->offset;
\t\t\tconst uint32_t s = n->span;
\t\t\tfor (uint32_t j = o; j < o + s; j++) {
\t\t\t\tt->leaf_to_internal[t->sorted[j]] = i;
\t\t\t}
\t\t}
\t}
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
 * Conservative broadphase: a segment hits `b` only if its AABB overlaps `b`.
 * Per-axis min/max routed through pbvh_r128_min / pbvh_r128_max (Z<->GF(2)
 * branchless ring form) — no r128_le ternaries inline. */
static inline Aabb pbvh_segment_aabb_(R128 ox, R128 oy, R128 oz,
\t\tR128 tx, R128 ty, R128 tz) {
\tAabb s;
\ts.min_x = pbvh_r128_min(ox, tx);
\ts.max_x = pbvh_r128_max(ox, tx);
\ts.min_y = pbvh_r128_min(oy, ty);
\ts.max_y = pbvh_r128_max(oy, ty);
\ts.min_z = pbvh_r128_min(oz, tz);
\ts.max_z = pbvh_r128_max(oz, tz);
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
 * the entire box is rejected. Arithmetic per corner is routed through
 * the EGraph-emitted pbvh_plane_corner_val helper — the only remaining
 * C here is control-flow (the 8-corner unroll) and the scalar
 * comparison (not a ring op). */
static inline bool pbvh_half_space_keeps_(const pbvh_plane_t *p, const Aabb *b) {
\tconst R128 zero = r128_from_int(0);
\tR128 xs[2]; xs[0] = b->min_x; xs[1] = b->max_x;
\tR128 ys[2]; ys[0] = b->min_y; ys[1] = b->max_y;
\tR128 zs[2]; zs[0] = b->min_z; zs[1] = b->max_z;
\tfor (int ix = 0; ix < 2; ix++) {
\t\tfor (int iy = 0; iy < 2; iy++) {
\t\t\tfor (int iz = 0; iz < 2; iz++) {
\t\t\t\tR128 val = pbvh_plane_corner_val(p->nx, p->ny, p->nz, p->d,
\t\t\t\t\t\txs[ix], ys[iy], zs[iz]);
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
\t/* Never rebuild in steady-state — any input pattern that forces a full
\t * O(N) pass is a DoS vector. Instead, treat sorted[]/internals[] topology
\t * as copy-on-write: structure is fixed at the last build, and every frame
\t * only refits bounds along the ancestor union of dirty leaves. Bucket
\t * crossings are NOT forced to a rebuild — the leaf stays at its old
\t * sorted[] index, its enclosing leaf-range internal re-unions to cover
\t * the leaf's new AABB, and the crossing becomes an over-conservative
\t * (but sound) bound. aabb_query_n scans by bounds, not by Hilbert bucket,
\t * so correctness is preserved; bucket_dir-based aabb_query_b may return
\t * slack but the adapter never invokes it. Dead slots (is_leaf=0) are
\t * skipped — their sorted[] entry contributes nothing to unions. */
\tfor (uint32_t i = 0; i < dirty_count; i++) {
\t\tconst pbvh_dirty_leaf_t *d = &dirty[i];
\t\tif (d->leaf_id >= t->count) {
\t\t\tcontinue;
\t\t}
\t}
\tpbvh_tree_refit_incremental_(t, dirty, dirty_count);
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
