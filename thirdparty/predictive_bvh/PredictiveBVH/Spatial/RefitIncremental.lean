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
-- FOLLOW-UP WORK (tracked for the next Lean-codegen session)
--
-- (A) `refitOne_preserves_local_cover_elsewhere`:
--     refitting at `i` does not disturb `localCoverAt` at `j ≠ i`, EXCEPT
--     when `j`'s children include `i` — in that case, `j`'s bounds may no
--     longer cover its children's new bounds. The global refit must
--     re-refit such parents *after* the child.
--
-- (B) `refitFull (t : PbvhTree) : PbvhTree` — post-order iteration via
--     `(List.range t.internals.size).foldr refitOne t`. Since pre-order
--     DFS places parent < child, foldr with ascending range processes
--     children (high index) before parents (low index) — exactly the
--     bottom-up order required.
--
-- (C) `refitFull_establishes_cover : ∀ t, coverInvariant (refitFull t)`.
--     The induction hypothesis: "after processing indices [k, size), every
--     internal at index ≥ k satisfies localCoverAt". Proven by downward
--     induction on k, using (A) and `refitOne_establishes_local_cover_at_i`.
--
-- (D) Mark-based spec `refitIncrementalSpec`: mark every ancestor of every
--     dirty leaf (NO dedup-break), refit only marked nodes in post-order.
--     Soundness reduces to (C) plus an equivalence theorem:
--     `refitIncrementalSpec t dirty = refitFull t'` where `t'` has
--     unmarked internals' bounds *already* covering their (possibly new)
--     subtree. This is where the current C's dedup-break + containment
--     early-out combination fails — the proof obligation is undischargeable
--     without walking past the marked node.
--
-- (E) Emit refitIncrementalSpec from a small imperative IR in
--     PredictiveBVH.Codegen.IR, with TranslationValidation against the
--     AmoLean.EGraph.Verified pipeline. Replaces the TreeC.lean string
--     template for this function.
-- ============================================================================

end PbvhTree
