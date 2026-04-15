-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee

import PredictiveBVH.Primitives.Types
import PredictiveBVH.Formulas.LowerBound
import PredictiveBVH.Spatial.Tree

-- ============================================================================
-- REFIT (INCREMENTAL) — Lean spec for pbvh_tree_refit_incremental_
--
-- This module is the load-bearing soundness bridge between:
--   * the high-level query-completeness theorem
--     `aabbQueryN_complete_from_invariants` (Tree.lean:2160), which assumes
--     every internal's bounds cover its subtree's leaves, and
--   * the emitted C function `pbvh_tree_refit_incremental_`
--     (Codegen/TreeC.lean:297), whose job is to *re-establish* that
--     invariant after dirty leaves move.
--
-- Before this module, `pbvh_tree_refit_incremental_` was a hand-templated C
-- string in TreeC.lean with a README-grade soundness argument. A stress
-- bench at 20% dirty / metre-scale motion surfaced a soundness gap (the
-- dedup-break inside the ancestor mark walk silently drops ancestors whose
-- bounds need to grow). This file introduces the Lean spec the C must match;
-- future work wires TreeC.lean to emit FROM this spec rather than freeform.
--
-- Structure:
--   (1) `coverInvariant` — per-internal cover condition.
--   (2) `refitOne`       — refit a single internal from its children's
--                          current bounds.
--   (3) `refitFull`      — post-order refit of every internal.
--   (4) Soundness theorems for (2) and (3).
-- ============================================================================

namespace PbvhTree

open Array

/-- The union of leaf bounds referenced by a leaf-block internal, i.e. the
    slots `sorted[offset .. offset+span)`. `none` for an empty block (span=0);
    otherwise the fold of `unionBounds` over the block. -/
def leafBlockUnion (t : PbvhTree) (offset span : Nat) : Option BoundingBox :=
  (List.range span).foldl (fun (acc : Option BoundingBox) (k : Nat) =>
    match t.leaves[t.sorted[offset + k]!]? with
    | some l =>
      match acc with
      | none   => some l.bounds
      | some a => some (unionBounds a l.bounds)
    | none => acc) none

/-- Pointwise cover condition at a single internal.

    A leaf-block internal (`left = right = none`) must cover the union of its
    leaves' bounds. A full internal (both children present) must cover the
    union of its children's bounds. A half-degenerate internal (exactly one
    child) must cover that child's bounds.

    This is the predicate `pbvh_tree_refit_incremental_` is supposed to
    establish for every ancestor of every dirty leaf, and the precondition
    that `aabbQueryN_complete_from_invariants` consumes when rejecting leaves
    that don't overlap the query at an ancestor. -/
def localCoverAt (t : PbvhTree) (i : InternalId) : Prop :=
  if h : i < t.internals.size then
    let n := t.internals[i]
    match n.left, n.right with
    | none, none =>
      -- Leaf-block: bounds ⊇ leafBlockUnion.
      match leafBlockUnion t n.offset n.span with
      | none    => True
      | some u  => aabbContains n.bounds u
    | some l, none =>
      if hl : l < t.internals.size then
        aabbContains n.bounds t.internals[l].bounds
      else True
    | none, some r =>
      if hr : r < t.internals.size then
        aabbContains n.bounds t.internals[r].bounds
      else True
    | some l, some r =>
      if hl : l < t.internals.size then
        if hr : r < t.internals.size then
          aabbContains n.bounds
            (unionBounds t.internals[l].bounds t.internals[r].bounds)
        else True
      else True
  else True

/-- Global cover invariant: every internal satisfies `localCoverAt`. This is
    the precondition `aabbQueryN_complete_from_invariants` lifts into the
    `h_path_from_root` overlap premise (via `aabbOverlapsDec_lift_through_contains`
    on Tree.lean:2217). -/
def coverInvariant (t : PbvhTree) : Prop :=
  ∀ i, i < t.internals.size → localCoverAt t i

/-- Refit a single internal: overwrite its `bounds` with the union of its
    current children's bounds (or the leaf-block union for leaf-range nodes).
    All other fields — `offset`, `span`, `skip`, `left`, `right` — are
    preserved verbatim. -/
def refitOne (t : PbvhTree) (i : InternalId) : PbvhTree :=
  if h : i < t.internals.size then
    let n := t.internals[i]
    let newBounds : BoundingBox :=
      match n.left, n.right with
      | none, none =>
        match leafBlockUnion t n.offset n.span with
        | some u => u
        | none   => n.bounds  -- empty block: keep old bounds
      | some l, none =>
        if hl : l < t.internals.size then t.internals[l].bounds else n.bounds
      | none, some r =>
        if hr : r < t.internals.size then t.internals[r].bounds else n.bounds
      | some l, some r =>
        if hl : l < t.internals.size then
          if hr : r < t.internals.size then
            unionBounds t.internals[l].bounds t.internals[r].bounds
          else t.internals[l].bounds
        else if hr : r < t.internals.size then t.internals[r].bounds
        else n.bounds
    { t with
      internals := t.internals.set i { n with bounds := newBounds } h }
  else t

/-- `refitOne` touches only `bounds` of node `i`; every other internal's
    entire record is byte-identical before and after. This is the lowered
    counterpart to `refitBucket_preserves_topology` (Tree.lean:660) — topology
    (children/skip/offset/span) is frozen by the build and must not drift
    during per-frame refit. -/
theorem refitOne_preserves_other_internals (t : PbvhTree) (i : InternalId)
    (j : InternalId) (hj : j < t.internals.size) (hij : i ≠ j) :
    (refitOne t i).internals[j]? = t.internals[j]? := by
  unfold refitOne
  by_cases hi : i < t.internals.size
  · simp [hi]
    rw [Array.getElem?_set_ne]
    exact fun hji => hij hji.symm
  · simp [hi]

/-- `refitOne` preserves the *size* of the internals array. Follows from
    `Array.set` being size-preserving; used as a structural precondition by
    every subsequent theorem (so later lemmas can quantify over `i <
    (refitOne t k).internals.size` without extra bookkeeping). -/
theorem refitOne_preserves_size (t : PbvhTree) (i : InternalId) :
    (refitOne t i).internals.size = t.internals.size := by
  unfold refitOne
  by_cases hi : i < t.internals.size
  · simp [hi]
  · simp [hi]

/-- The local cover bound produced by `refitOne` at node `i` is, by
    construction, a container for the relevant union:
      * leaf-block  : `bounds = leafBlockUnion` (exact equality, hence ⊇ reflexively)
      * both kids   : `bounds = unionBounds left right` (⊇ each)
      * one kid     : `bounds = that child's bounds` (⊇ reflexively)
    This is the "refit establishes the local cover" micro-lemma, which the
    global `refitFull_establishes_cover` below bootstraps via induction on
    internal index. -/
theorem refitOne_establishes_local_cover_at_i (t : PbvhTree) (i : InternalId)
    (hi : i < t.internals.size) :
    localCoverAt (refitOne t i) i := by
  unfold localCoverAt
  -- After refitOne, the size is unchanged, so `i <` still holds.
  have hsz : (refitOne t i).internals.size = t.internals.size :=
    refitOne_preserves_size t i
  have hi' : i < (refitOne t i).internals.size := hsz ▸ hi
  simp only [hi', dif_pos]
  -- Unfold refitOne to read off the new node at i.
  unfold refitOne
  simp only [hi, dif_pos]
  -- The set-at-i slot reads back the freshly-built record.
  rw [Array.getElem_set_self]
  -- The children fields are COPIED from the original node (via { n with bounds := ... }),
  -- so match on the original's children partitions the new node identically.
  set n := t.internals[i] with hn_def
  -- Split by children shape; each branch reduces to an obvious containment.
  rcases hl_cases : n.left with _ | l
  · rcases hr_cases : n.right with _ | r
    · -- Leaf block: newBounds = (leafBlockUnion ...).getD n.bounds. Either
      -- branch of the getD satisfies the block invariant trivially.
      simp only [hl_cases, hr_cases]
      rcases hblock : leafBlockUnion t n.offset n.span with _ | u
      · simp [hblock]
      · simp only [hblock]
        -- bounds = u; localCoverAt for leaf block requires bounds ⊇ u.
        exact aabbContains_refl u
    · -- only right child
      simp only [hl_cases, hr_cases]
      by_cases hr : r < t.internals.size
      · simp [hr]
        exact aabbContains_refl _
      · simp [hr]
  · rcases hr_cases : n.right with _ | r
    · -- only left child
      simp only [hl_cases, hr_cases]
      by_cases hl : l < t.internals.size
      · simp [hl]
        exact aabbContains_refl _
      · simp [hl]
    · -- both children
      simp only [hl_cases, hr_cases]
      by_cases hl : l < t.internals.size
      · by_cases hr : r < t.internals.size
        · simp [hl, hr]
          exact aabbContains_refl _
        · simp [hl, hr]
          exact aabbContains_refl _
      · by_cases hr : r < t.internals.size
        · simp [hl, hr]
          exact aabbContains_refl _
        · simp [hl, hr]

-- ============================================================================
-- Part II — refitFull: post-order full refit
-- ============================================================================

/-- Post-order refit of every internal.
    `List.range n` = [0, 1, …, n-1]; `foldr` processes right-to-left, so
    the effective application order is n-1, n-2, …, 0 — children (higher
    index in pre-order DFS) before parents (lower index). -/
def refitFull (t : PbvhTree) : PbvhTree :=
  (List.range t.internals.size).foldr refitOne t

/-- `refitFull` preserves the internals array size. -/
theorem refitFull_preserves_size (t : PbvhTree) :
    (refitFull t).internals.size = t.internals.size := by
  unfold refitFull
  induction List.range t.internals.size with
  | nil => simp
  | cons k ks ih =>
    simp only [List.foldr_cons]
    rw [refitOne_preserves_size]
    exact ih

/-- `refitFull` establishes the global cover invariant.
    PROOF SKETCH (for future mechanisation):
    Let n = t.internals.size.  Define:
      step k t₀ := (List.range k).foldr refitOne t₀   (processes k-1 … 0)
    We prove by induction on k (downward from n to 0):
      ∀ j < k, localCoverAt (step k t₀) j.
    Base (k = 0): vacuous.
    Step (k → k+1):
      step (k+1) t₀ = refitOne k (step k t₀).
      (a) j = k: refitOne_establishes_local_cover_at_i gives localCoverAt. ✓
      (b) j < k (IH): refitOne at k only modifies node k's bounds.
          Node j's children have index > j.  Two sub-cases:
          • child index > k: those bounds are unchanged by refitOne k
            (by refitOne_preserves_other_internals), so j's localCoverAt
            is preserved from the IH directly.
          • child index ≤ k (= k itself, since j < k ≤ child): child k was
            just refit; j's bounds may now be too tight.  But j is
            processed at step j < k, so step j+1 … refitOne j … reads
            the correct, already-updated child bounds at that later point.
            Because step (k+1) = refitOne k ∘ step k, and j < k, j's
            refitOne fires *after* k's.  At the time refitOne j fires it
            reads k's final (correct) bounds.  After that, no refitOne at
            any index ≠ j changes j's bounds.  So j's final bounds are
            correct.
    The argument for the full fold is: at the very end, every node i had
    refitOne i applied *after* all its children's refitOne applications,
    and no later refitOne changes i's bounds. -/
theorem refitFull_establishes_cover (t : PbvhTree) :
    coverInvariant (refitFull t) := by
  sorry

-- ============================================================================
-- Part III — markAncestors / refitIncrementalSpec
-- ============================================================================

/-- Walk the parent chain from internal `i`, marking each visited node in
    `marked`. `fuel` bounds the recursion; any positive value ≥ tree height
    (which is ≤ internals.size) is sufficient for completeness.
    NO dedup-break: every ancestor is marked unconditionally, even if it was
    already set by a previous leaf's walk.  The soundness obligation (D in
    the original plan) requires marking ALL ancestors; a dedup-break that
    stops early when an ancestor is already marked is unsound when combined
    with a containment early-out, because it can silently skip ancestors
    whose bounds need to grow. -/
private def walkAndMark
    (parentOf : InternalId → Option InternalId)
    (fuel : Nat) (marked : Array Bool) (i : InternalId) : Array Bool :=
  match fuel with
  | 0 => marked
  | fuel + 1 =>
    let marked' := if h : i < marked.size then marked.set i true h else marked
    match parentOf i with
    | none   => marked'
    | some p => walkAndMark parentOf fuel marked' p

/-- Mark every ancestor of every dirty leaf.
    `leafToInternal leaf_id` = the enclosing leaf-range internal for that
    leaf (the bottom of its ancestor chain).
    `parentOf i` = the parent internal of `i` (`none` at the root).
    Returns a `Bool` array of length `t.internals.size`; entry `i` is `true`
    iff internal `i` is an ancestor of at least one dirty leaf. -/
def markAncestors
    (t : PbvhTree) (dirtyLeafIds : List LeafId)
    (leafToInternal : LeafId → Option InternalId)
    (parentOf : InternalId → Option InternalId) : Array Bool :=
  dirtyLeafIds.foldl (fun marked leafId =>
    match leafToInternal leafId with
    | none       => marked
    | some start => walkAndMark parentOf t.internals.size marked start
  ) (Array.mkArray t.internals.size false)

/-- Incremental refit: apply `refitOne` only to marked internals, in
    descending index order (children before parents, same as `refitFull`). -/
def refitIncrementalSpec
    (t : PbvhTree) (marked : Array Bool) : PbvhTree :=
  (List.range t.internals.size).foldr (fun i t' =>
    if marked.getD i false then refitOne t' i else t'
  ) t

-- ============================================================================
-- Part IV — soundness of refitIncrementalSpec
-- ============================================================================

/-- Every ancestor of every dirty leaf is marked by `markAncestors`.
    PROOF SKETCH: by induction on the dirty leaf list and fuel-induction on
    `walkAndMark`: each call sets entry `i` to `true` then recurses to the
    parent, so every node on the path from `start` to the root is marked
    after `walkAndMark` completes (provided fuel ≥ path length, which is
    guaranteed by fuel = internals.size ≥ tree height). -/
theorem markAncestors_covers_all_ancestors
    (t : PbvhTree) (dirtyLeafIds : List LeafId)
    (leafToInternal : LeafId → Option InternalId)
    (parentOf : InternalId → Option InternalId)
    (leaf : LeafId) (h_leaf : leaf ∈ dirtyLeafIds)
    (i : InternalId) (hi : i < t.internals.size)
    (h_anc : ∃ start, leafToInternal leaf = some start ∧
        ∃ fuel, walkAndMark parentOf fuel (Array.mkArray t.internals.size false) start
                  |>.getD i false = true) :
    (markAncestors t dirtyLeafIds leafToInternal parentOf).getD i false = true := by
  sorry

/-- `refitIncrementalSpec` with a fully-marked array equals `refitFull`.
    When every internal is marked, the `if` guard is always `true` and the
    two folds are definitionally equal. -/
theorem refitIncrementalSpec_allMarked_eq_refitFull (t : PbvhTree) :
    let allMarked := Array.mkArray t.internals.size true
    refitIncrementalSpec t allMarked = refitFull t := by
  simp only [refitIncrementalSpec, refitFull]
  congr 1
  funext i
  simp [Array.getD, Array.mkArray]

/-- Main soundness theorem: when `marked` covers all ancestors of all dirty
    leaves AND the unmarked internals' existing bounds already satisfy
    `localCoverAt` in `t` (i.e., they were untouched by the dirty leaves),
    `refitIncrementalSpec t marked` satisfies `coverInvariant`.
    PROOF SKETCH: The marked nodes are a superset of all ancestors of dirty
    leaves.  By `markAncestors_covers_all_ancestors`, all such ancestors are
    refit.  For the unmarked nodes: their children bounds are unchanged
    (dirty leaves only moved bounds within marked subtrees; unmarked nodes
    have no dirty-leaf descendants by the marking invariant), so their
    pre-existing `localCoverAt` is preserved by
    `refitOne_preserves_other_internals`.  The argument for the marked nodes
    is analogous to `refitFull_establishes_cover` restricted to the marked
    subgraph. -/
theorem refitIncrementalSpec_establishes_cover
    (t : PbvhTree) (marked : Array Bool)
    (h_marked_covers : ∀ i, i < t.internals.size →
        ¬ marked.getD i false →
        localCoverAt t i) :
    coverInvariant (refitIncrementalSpec t marked) := by
  sorry

-- ============================================================================
-- REMAINING WORK
--
-- (E) Prove refitFull_establishes_cover mechanically (removes sorry above).
--     The sketch in the docstring gives the induction; the key lemma is
--     `refitOne_preserves_localCover_at_lower`:
--       ∀ j < k, localCoverAt t j → localCoverAt (refitOne t k) j
--     which follows because j's children have indices > j, and if those
--     indices are also > k then they are unmodified by refitOne k
--     (refitOne_preserves_other_internals).  The case child_index = k is the
--     subtle one: j's bounds may now be stale w.r.t. k's new bounds, but j
--     is re-refit at step j (which comes after k in the descending fold),
--     so the invariant only needs to hold AT THE END of the full fold.
--
-- (F) Prove markAncestors_covers_all_ancestors mechanically.
--     The walkAndMark induction is on fuel; the key step shows that
--     walkAndMark sets entry i and recurses to the parent.
--
-- (G) Emit refitIncrementalSpec from a small imperative IR in
--     PredictiveBVH.Codegen.IR, with TranslationValidation against the
--     AmoLean.EGraph.Verified pipeline. Replaces the TreeC.lean string
--     template for this function.
-- ============================================================================

end PbvhTree
