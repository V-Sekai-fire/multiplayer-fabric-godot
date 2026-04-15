-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026-present K. S. Ernest (iFire) Lee

import PredictiveBVH.Primitives.Types
import PredictiveBVH.Formulas.LowerBound
import PredictiveBVH.Spatial.HilbertBroadphase

-- ============================================================================
-- PREDICTIVE BVH TREE — Lean codification of predictive_bvh_tree.h
--
-- Mirrors the hand-written C scaffold verbatim in shape. Leaves carry an
-- EClassId (Nat) payload; internal nodes form a nested-set pre-order DFS
-- layout with skip-pointer descent. Queries prune by bounds on internals
-- and by Hilbert prefix on the optional bucket directory.
--
-- Invariants (proved where feasible in this first pass; see theorems below):
--   - liveness: remove/update/build do not resurrect dead leaves
--   - sort:     `sorted` is ascending by leaves[·].hilbert over live leaves
--   - eclass uniqueness: each EClassId appears in at most one live leaf
--   - nested-set: internals[i].skip = i + 1 + subtreeSize(left) + subtreeSize(right)
--   - bound containment: union of live leaf bounds under i ⊆ internals[i].bounds
-- ============================================================================

abbrev LeafId     := Nat
abbrev InternalId := Nat

/-- One leaf in the tree. Tombstoned by flipping `alive` to false so that
    `sorted` can stay stable across removals without a rebuild. -/
structure PbvhLeaf where
  eclass  : EClassId
  bounds  : BoundingBox
  hilbert : Nat            -- 30-bit Hilbert code
  alive   : Bool
  deriving Inhabited, Repr

/-- One internal node. `(offset, span)` is the nested-set range into `sorted`;
    `skip` is the next pre-order DFS index past this subtree. -/
structure PbvhInternal where
  bounds : BoundingBox
  offset : Nat
  span   : Nat
  skip   : InternalId
  left   : Option InternalId
  right  : Option InternalId
  deriving Inhabited, Repr

/-- Purely-functional BVH tree over EClassId leaves. -/
structure PbvhTree where
  leaves       : Array PbvhLeaf
  sorted       : Array LeafId       -- ascending by leaves[·].hilbert
  internals    : Array PbvhInternal -- pre-order DFS
  bucketBits   : Nat                -- 0 disables bucket dir
  bucketDir    : Array (Nat × Nat)  -- (lo, hi) per Hilbert prefix
  internalRoot : Option InternalId
  deriving Inhabited

namespace PbvhTree

/-- The empty tree. -/
def empty : PbvhTree :=
  { leaves := #[], sorted := #[], internals := #[],
    bucketBits := 0, bucketDir := #[], internalRoot := none }

/-- Count of leaves currently live. -/
def liveCount (t : PbvhTree) : Nat :=
  t.leaves.foldl (fun acc l => if l.alive then acc + 1 else acc) 0

-- ── insert / remove / update ─────────────────────────────────────────────────

/-- Append a new live leaf. Returns the new tree and its LeafId. `sorted`,
    `internals`, `bucketDir` go stale until `build` runs. -/
def insert (t : PbvhTree) (eclass : EClassId) (bounds : BoundingBox)
    (hilbert : Nat) : PbvhTree × LeafId :=
  let newLeaf : PbvhLeaf := { eclass, bounds, hilbert, alive := true }
  let id := t.leaves.size
  ({ t with leaves := t.leaves.push newLeaf }, id)

/-- Tombstone a leaf. No-op if out of bounds or already dead. -/
def remove (t : PbvhTree) (id : LeafId) : PbvhTree :=
  if h : id < t.leaves.size then
    let l := t.leaves[id]
    let l' := { l with alive := false }
    { t with leaves := t.leaves.set id l' }
  else t

/-- Update bounds and hilbert of a leaf. No-op if out of bounds. Does not
    touch `alive`. `sorted` is stale until `build` runs. -/
def update (t : PbvhTree) (id : LeafId) (bounds : BoundingBox)
    (hilbert : Nat) : PbvhTree :=
  if h : id < t.leaves.size then
    let l := t.leaves[id]
    let l' := { l with bounds := bounds, hilbert := hilbert }
    { t with leaves := t.leaves.set id l' }
  else t

-- ── build: sort live leaves by hilbert, construct internals ──────────────────

/-- Insertion-sort pass over `sorted` indices by `leaves[·].hilbert`. Stable
    on equal codes. Dead leaves are filtered out before sorting. -/
private def insertionSortByHilbert
    (leaves : Array PbvhLeaf) (ids : Array LeafId) : Array LeafId :=
  let n := ids.size
  Id.run do
    let mut arr := ids
    let mut i := 1
    while i < n do
      let mut j := i
      while j > 0 &&
            (leaves[arr[j]!]?.map (·.hilbert)).getD 0 <
            (leaves[arr[j-1]!]?.map (·.hilbert)).getD 0 do
        let a := arr[j]!
        let b := arr[j-1]!
        arr := arr.set! j b
        arr := arr.set! (j-1) a
        j := j - 1
      i := i + 1
    return arr

/-- Live leaf ids in tombstone-stripped original-index order. -/
private def liveIds (leaves : Array PbvhLeaf) : Array LeafId :=
  Id.run do
    let mut out : Array LeafId := #[]
    for i in [:leaves.size] do
      if leaves[i]!.alive then out := out.push i
    return out

/-- Union of leaf bounds over a window `[lo, hi)` in `sorted`. -/
private def windowBounds
    (leaves : Array PbvhLeaf) (sorted : Array LeafId) (lo hi : Nat) : BoundingBox :=
  if lo ≥ hi then
    { minX := 0, maxX := 0, minY := 0, maxY := 0, minZ := 0, maxZ := 0 }
  else
    let init := (leaves[sorted[lo]!]?.map (·.bounds)).getD
      { minX := 0, maxX := 0, minY := 0, maxY := 0, minZ := 0, maxZ := 0 }
    (List.range (hi - lo - 1)).foldl (fun acc j =>
      let lb := (leaves[sorted[lo + j + 1]!]?.map (·.bounds)).getD acc
      unionBounds acc lb) init

/-- Compute the split point `mid` with `lo < mid < hi`. Prefers the Hilbert
    prefix split; falls back to the window midpoint when the prefix fails to
    partition. The returned subtype carries the `lo < mid ∧ mid < hi` proof
    that `buildSubtree` needs for its termination measure to strictly decrease
    in both recursive calls. -/
private def computeMid
    (leaves : Array PbvhLeaf) (sorted : Array LeafId) (lo hi : Nat)
    (h : lo + 2 ≤ hi) : { m : Nat // lo < m ∧ m < hi } :=
  -- Median fallback: `lo + (hi - lo) / 2`. When `hi - lo ≥ 2`, the midpoint
  -- strictly separates the window — used both as the default and whenever
  -- the Hilbert-prefix split degenerates.
  let median : Nat := lo + (hi - lo) / 2
  have hmed_lo : lo < median := by
    have hdiff : 2 ≤ hi - lo := by omega
    have hhalf : 1 ≤ (hi - lo) / 2 := Nat.le_div_iff_mul_le (by decide) |>.mpr (by omega)
    omega
  have hmed_hi : median < hi := by
    have hdiff : 0 < hi - lo := by omega
    have hhalf : (hi - lo) / 2 < hi - lo := Nat.div_lt_self hdiff (by decide)
    omega
  let hlo := (leaves[sorted[lo]!]?.map (·.hilbert)).getD 0
  let hhi := (leaves[sorted[hi - 1]!]?.map (·.hilbert)).getD 0
  if hlo == hhi then
    ⟨median, hmed_lo, hmed_hi⟩
  else
    let xor := hlo ^^^ hhi
    let depth := clz30 xor
    let mask : Nat := 1 <<< (29 - depth)
    -- First index in (lo, hi) whose hilbert has the split bit set; default hi.
    let m := (List.range (hi - lo - 1)).foldl (fun acc j =>
      let k := lo + 1 + j
      let hk := (leaves[sorted[k]!]?.map (·.hilbert)).getD 0
      if hk &&& mask != 0 && acc == hi then k else acc) hi
    if h1 : lo < m ∧ m < hi then ⟨m, h1⟩
    else ⟨median, hmed_lo, hmed_hi⟩

/-- Recursive builder: returns the updated internals array plus the root
    index for this subtree. Splits on Hilbert prefix when possible, else
    falls back to median. Termination: `hi - lo` strictly decreases in both
    recursive calls because `computeMid` returns `lo < mid < hi`. -/
private def buildSubtree
    (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal)
    (lo hi : Nat) : Array PbvhInternal × InternalId :=
  let bounds := windowBounds leaves sorted lo hi
  if hle : hi - lo ≤ 1 then
    let leaf : PbvhInternal :=
      { bounds, offset := lo, span := hi - lo, skip := internals.size + 1,
        left := none, right := none }
    (internals.push leaf, internals.size)
  else
    have hgt : lo + 2 ≤ hi := by omega
    let myIdx := internals.size
    -- Placeholder; fixed up after children built.
    let placeholder : PbvhInternal :=
      { bounds, offset := lo, span := hi - lo, skip := myIdx + 1,
        left := none, right := none }
    let internals := internals.push placeholder
    let ⟨mid, hmid_lo, hmid_hi⟩ := computeMid leaves sorted lo hi hgt
    have hleft : mid - lo < hi - lo := by omega
    have hright : hi - mid < hi - lo := by omega
    let (internals, leftIdx) := buildSubtree leaves sorted internals lo mid
    let (internals, rightIdx) := buildSubtree leaves sorted internals mid hi
    -- Patch our node with children and correct skip pointer.
    let updated : PbvhInternal :=
      { bounds, offset := lo, span := hi - lo,
        skip := internals.size,
        left := some leftIdx, right := some rightIdx }
    (internals.set! myIdx updated, myIdx)
  termination_by hi - lo

/-- Rebuild the sorted-by-Hilbert view and the internals tree. Leaves remain
    in place; `alive` flags are untouched. Bucket directory is left empty
    in this Lean codification; callers that want O(1)+k prefix queries can
    populate `bucketDir` in the C emission. -/
def build (t : PbvhTree) : PbvhTree :=
  let live := liveIds t.leaves
  let sorted := insertionSortByHilbert t.leaves live
  if sorted.isEmpty then
    { t with sorted := #[], internals := #[], internalRoot := none,
             bucketDir := #[] }
  else
    let (internals, root) := buildSubtree t.leaves sorted #[] 0 sorted.size
    { t with sorted := sorted, internals := internals,
             internalRoot := some root, bucketDir := #[] }

-- ── Queries ──────────────────────────────────────────────────────────────────

/-- Top-level recursive worker for `aabbQueryN`. Extracted from its former
    `let rec` body so that its recursion principle (and thus soundness /
    completeness proofs) is directly accessible at module scope. Terminates
    on `end_ - i`: each step either advances `i` by one or jumps forward via
    the skip pointer. A defensive clamp on `next` guarantees `next > i ∧
    next ≤ end_`, so the measure decreases even before `skip_equals_dfs_next`
    is proved. -/
def aabbQueryNGo (t : PbvhTree) (query : BoundingBox)
    (i : Nat) (acc : List EClassId) : List EClassId :=
  let end_ := t.internals.size
  if hlt : i ≥ end_ then acc.reverse
  else
    let n := t.internals[i]!
    let next : Nat := if h : i < n.skip ∧ n.skip ≤ end_ then n.skip else i + 1
    have hnext_lt : end_ - next < end_ - i := by
      have hi : i < end_ := by omega
      show end_ - (if _ : i < n.skip ∧ n.skip ≤ end_ then n.skip else i + 1) < end_ - i
      split <;> rename_i h <;> omega
    if ¬ aabbOverlapsDec n.bounds query then
      aabbQueryNGo t query next acc
    else if n.left.isNone && n.right.isNone then
      -- Leaf block: scan the (offset, span) window in `sorted`.
      let acc := (List.range n.span).foldl (fun acc j =>
        let lid := t.sorted[n.offset + j]!
        match t.leaves[lid]? with
        | some l =>
          if l.alive && aabbOverlapsDec l.bounds query then
            l.eclass :: acc else acc
        | none => acc) acc
      aabbQueryNGo t query next acc
    else
      have hinc : end_ - (i + 1) < end_ - i := by
        have hi : i < end_ := by omega
        omega
      aabbQueryNGo t query (i + 1) acc
  termination_by t.internals.size - i

/-- Iterative skip-pointer descent. Returns every live leaf eclass whose
    bounds overlap `query`. Emits in pre-order DFS order. -/
def aabbQueryN (t : PbvhTree) (query : BoundingBox) : List EClassId :=
  if t.internals.isEmpty then []
  else aabbQueryNGo t query (t.internalRoot.getD 0) []

/-- Enumerate all overlapping live-leaf pairs as `(a, b)` with `a < b` by
    EClassId. Eclass-style broadphase: no pointers, no per-slot callback. -/
def enumeratePairs (t : PbvhTree) : List (EClassId × EClassId) :=
  let n := t.leaves.size
  (List.range n).foldl (fun acc i =>
    match t.leaves[i]? with
    | some li =>
      if ¬ li.alive then acc
      else
        let peers := aabbQueryN t li.bounds
        peers.foldl (fun acc e =>
          if li.eclass < e then (li.eclass, e) :: acc
          else if e < li.eclass then (e, li.eclass) :: acc
          else acc) acc
    | none => acc) []

end PbvhTree

-- ============================================================================
-- PROOFS
-- ============================================================================

namespace PbvhTree

/-- Generic foldl invariant: if `P` holds on the initial accumulator and is
    preserved by every step, it holds on the final fold result. -/
private theorem foldl_invariant {α β : Type _} (P : β → Prop)
    (f : β → α → β) :
    ∀ (l : List α) (b : β), P b → (∀ b a, P b → P (f b a)) → P (l.foldl f b) := by
  intro l
  induction l with
  | nil => intro b hb _; exact hb
  | cons x xs ih =>
    intro b hb hf
    exact ih (f b x) (hf b x hb) hf

/-- `insert` extends `leaves` at the end; the `alive` flag at any existing
    index is preserved. -/
theorem insert_preserves_alive (t : PbvhTree) (e : EClassId) (b : BoundingBox)
    (h : Nat) (i : LeafId) (hi : i < t.leaves.size) :
    ((t.insert e b h).1.leaves[i]?.map (·.alive)) =
      (t.leaves[i]?.map (·.alive)) := by
  simp only [insert]
  rw [Array.getElem?_push_lt hi]
  simp [Array.getElem?_eq_getElem hi]

/-- `update` does not touch the `alive` flag of any leaf (the write only
    rewrites `bounds` and `hilbert`). -/
theorem update_preserves_alive (t : PbvhTree) (id : LeafId) (b : BoundingBox)
    (h : Nat) (i : LeafId) :
    ((t.update id b h).leaves[i]?.map (·.alive)) =
      (t.leaves[i]?.map (·.alive)) := by
  simp only [update]
  split
  · rename_i hid
    rw [Array.getElem?_set hid]
    by_cases heq : id = i
    · subst heq
      simp [Array.getElem?_eq_getElem hid]
    · simp [heq]
  · rfl

/-- `remove id` only flips `alive := false` at position `id`; every other
    leaf's `alive` flag is unchanged. -/
theorem remove_preserves_other_alive (t : PbvhTree) (id : LeafId) (i : LeafId)
    (hne : i ≠ id) :
    ((t.remove id).leaves[i]?.map (·.alive)) =
      (t.leaves[i]?.map (·.alive)) := by
  simp only [remove]
  split
  · rename_i hid
    rw [Array.getElem?_set_ne hid hne.symm]
  · rfl

/-- Sizes never shrink across `insert` / `update` / `remove`. -/
theorem ops_size_monotone (t : PbvhTree) (e : EClassId) (b : BoundingBox)
    (h : Nat) (id : LeafId) :
    t.leaves.size ≤ (t.insert e b h).1.leaves.size ∧
    t.leaves.size ≤ (t.update id b h).leaves.size ∧
    t.leaves.size ≤ (t.remove id).leaves.size := by
  refine ⟨?_, ?_, ?_⟩
  · simp [insert, Array.size_push]
  · simp [update]; split <;> simp [Array.size_set]
  · simp [remove]; split <;> simp [Array.size_set]

/-- `build` never mutates `leaves`. Everything it touches is in `sorted`,
    `internals`, `internalRoot`, `bucketDir`. -/
theorem build_preserves_leaves (t : PbvhTree) :
    t.build.leaves = t.leaves := by
  simp only [build]
  split <;> rfl

/-- Corollary: `build` preserves every leaf's `alive` flag. -/
theorem build_preserves_alive (t : PbvhTree) (i : LeafId) :
    (t.build.leaves[i]?.map (·.alive)) = (t.leaves[i]?.map (·.alive)) := by
  rw [build_preserves_leaves]

/-- Inner step of `enumeratePairs`: emitting either `(li, e)` or `(e, li)`
    (guarded by `<`) preserves the "every pair strictly ordered" invariant. -/
private theorem enumeratePairs_inner_step
    (li_eclass e : EClassId) (acc : List (EClassId × EClassId))
    (hacc : ∀ q ∈ acc, q.1 < q.2) :
    ∀ q ∈ (if li_eclass < e then (li_eclass, e) :: acc
           else if e < li_eclass then (e, li_eclass) :: acc
           else acc), q.1 < q.2 := by
  intro q hq
  by_cases h1 : li_eclass < e
  · simp [h1] at hq
    rcases hq with hq | hq
    · rw [hq]; exact h1
    · exact hacc q hq
  · by_cases h2 : e < li_eclass
    · simp [h1, h2] at hq
      rcases hq with hq | hq
      · rw [hq]; exact h2
      · exact hacc q hq
    · simp [h1, h2] at hq
      exact hacc q hq

/-- Every pair emitted by `enumeratePairs` is strictly ordered by EClassId. -/
theorem enumeratePairs_strictly_ordered (t : PbvhTree) :
    ∀ p ∈ t.enumeratePairs, p.1 < p.2 := by
  have H := foldl_invariant
    (P := fun (acc : List (EClassId × EClassId)) => ∀ q ∈ acc, q.1 < q.2)
    (f := fun acc i =>
      match t.leaves[i]? with
      | some li =>
        if ¬ li.alive then acc
        else
          (aabbQueryN t li.bounds).foldl (fun acc e =>
            if li.eclass < e then (li.eclass, e) :: acc
            else if e < li.eclass then (e, li.eclass) :: acc
            else acc) acc
      | none => acc)
    (List.range t.leaves.size) []
    (by intro q hq; exact absurd hq List.not_mem_nil)
    (by
      intro acc i hacc
      -- Case split on the outer step.
      cases hl : t.leaves[i]? with
      | none => simpa [hl] using hacc
      | some li =>
        by_cases halive : li.alive
        · simp only [hl, halive, not_true, ite_false]
          -- Inner fold preserves the invariant.
          exact foldl_invariant
            (P := fun (acc : List (EClassId × EClassId)) => ∀ q ∈ acc, q.1 < q.2)
            (f := fun acc e =>
              if li.eclass < e then (li.eclass, e) :: acc
              else if e < li.eclass then (e, li.eclass) :: acc
              else acc)
            (aabbQueryN t li.bounds) acc hacc
            (fun acc' e hacc' => enumeratePairs_inner_step li.eclass e acc' hacc')
        · simpa [hl, halive] using hacc)
  simpa [enumeratePairs] using H

-- ── Tier 1 (structural) ──────────────────────────────────────────────────────

/-- `buildSubtree` always returns, as its second component, the `internals.size`
    it was called with. That value is captured as `myIdx` before any array
    mutation, so it's stable across both the base and recursive cases. -/
theorem buildSubtree_root (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat) :
    (buildSubtree leaves sorted internals lo hi).2 = internals.size := by
  unfold buildSubtree
  split
  · rfl
  · -- `dsimp only` zeta-reduces the `have` chain so the returned pair
    -- literal `(_, internals.size)` is visible; destructuring the `computeMid`
    -- Subtype match then exposes `.snd = internals.size`.
    dsimp only
    obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
    rfl

/-- After `buildSubtree`, the internals array size only grows. Proved by strong
    induction on the termination measure `hi - lo`. -/
theorem buildSubtree_size_ge (leaves : Array PbvhLeaf) (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      internals.size ≤ (buildSubtree leaves sorted internals lo hi).1.size := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro internals lo hi hn
    unfold buildSubtree
    split
    · simp [Array.size_push]
    · dsimp only
      obtain ⟨mid, hmlo, hmhi⟩ := computeMid leaves sorted lo hi (by omega)
      let ph : PbvhInternal :=
        { bounds := windowBounds leaves sorted lo hi, offset := lo,
          span := hi - lo, skip := internals.size + 1,
          left := none, right := none }
      let state0 := internals.push ph
      have hstate0 : internals.size ≤ state0.size := by
        show internals.size ≤ (internals.push ph).size
        simp [Array.size_push]
      have hleft_lt : mid - lo < n := by omega
      have hleft := ih (mid - lo) hleft_lt state0 lo mid rfl
      have hright_lt : hi - mid < n := by omega
      have hright := ih (hi - mid) hright_lt
        (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl
      show internals.size ≤
        ((buildSubtree leaves sorted
            (buildSubtree leaves sorted state0 lo mid).1 mid hi).1.set!
          internals.size _).size
      simp
      omega

/-- Strictly-increasing corollary: the returned root index is a valid slot in
    the final internals array. Lets callers safely `[r]!` the root. -/
theorem buildSubtree_root_lt_size (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat) :
    (buildSubtree leaves sorted internals lo hi).2 <
      (buildSubtree leaves sorted internals lo hi).1.size := by
  -- `.2 = internals.size` and `.1.size ≥ internals.size + 1`, since the base
  -- case pushes a leaf and the recursive case pushes a placeholder first.
  rw [buildSubtree_root]
  unfold buildSubtree
  split
  · simp [Array.size_push]
  · dsimp only
    obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
    let ph : PbvhInternal :=
      { bounds := windowBounds leaves sorted lo hi, offset := lo,
        span := hi - lo, skip := internals.size + 1,
        left := none, right := none }
    let state0 := internals.push ph
    have h0 : internals.size + 1 = state0.size := by
      show internals.size + 1 = (internals.push ph).size
      simp [Array.size_push]
    have h1 := buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
    have h2 := buildSubtree_size_ge leaves sorted _
      (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl
    show internals.size <
      ((buildSubtree leaves sorted
          (buildSubtree leaves sorted state0 lo mid).1 mid hi).1.set!
        internals.size _).size
    simp
    omega

/-- After `buildSubtree`, the root node's `skip` field equals the final
    `internals.size`. This is the load-bearing invariant: it means the subtree
    rooted at `myIdx` occupies exactly the contiguous range `[myIdx, skip)` in
    the final array, so pruning that subtree is a single index assignment. -/
theorem buildSubtree_skip_eq_final_size
    (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat) :
    let r := (buildSubtree leaves sorted internals lo hi).1
    r[(buildSubtree leaves sorted internals lo hi).2]!.skip = r.size := by
  rw [buildSubtree_root]
  unfold buildSubtree
  split
  · -- Base: pushed leaf has skip := internals.size + 1 = (internals.push leaf).size
    dsimp only
    show (internals.push _)[internals.size]!.skip = (internals.push _).size
    rw [Array.getElem!_eq_getD, Array.getD, dif_pos (by simp [Array.size_push])]
    simp [Array.getElem_push_eq]
  · -- Recursive: final `set! myIdx updated` writes updated.skip = inner.size;
    -- since myIdx < inner.size, the readback yields updated.skip = outer.size.
    dsimp only
    obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
    let ph : PbvhInternal :=
      { bounds := windowBounds leaves sorted lo hi, offset := lo,
        span := hi - lo, skip := internals.size + 1,
        left := none, right := none }
    let state0 := internals.push ph
    have h0 : state0.size = internals.size + 1 := by
      show (internals.push ph).size = internals.size + 1
      simp [Array.size_push]
    have h1 := buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
    have h2 := buildSubtree_size_ge leaves sorted _
      (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl
    have hmyIdx : internals.size <
        (buildSubtree leaves sorted
          (buildSubtree leaves sorted state0 lo mid).1 mid hi).1.size := by
      omega
    show ((buildSubtree leaves sorted _ mid hi).1.set! internals.size _)[internals.size]!.skip = _
    rw [Array.getElem!_eq_getD, Array.getD, dif_pos (by simp; exact hmyIdx)]
    simp

/-- Structural subtree size in the internals array: under the invariants
    established by `build` (every internal's `skip` points past its subtree in
    the nested-set pre-order DFS layout), `subtreeSize t i = skip - i`. -/
def subtreeSize (t : PbvhTree) (i : InternalId) : Nat :=
  if h : i < t.internals.size then t.internals[i].skip - i else 0

/-- Positions strictly below `internals.size` are untouched by `buildSubtree`:
    the builder only pushes new slots and the final `set!` writes to `myIdx`
    which equals the input `internals.size`, never below. This is the
    workhorse that lets skip invariants propagate across nested builds. -/
theorem buildSubtree_preserves_prefix (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat) (hj : j < internals.size),
        ∃ (hj' : j < (buildSubtree leaves sorted internals lo hi).1.size),
          (buildSubtree leaves sorted internals lo hi).1[j]'hj' = internals[j] := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro internals lo hi hn j hj
    unfold buildSubtree
    split
    · -- Base: push leaf; j < internals.size < (push).size.
      refine ⟨?_, ?_⟩
      · show j < (internals.push _).size; simp [Array.size_push]; omega
      · show (internals.push _)[j]'_ = internals[j]
        exact Array.getElem_push_lt hj
    · -- Recursive: state0 = push ph; two recursive calls; set! internals.size.
      dsimp only
      obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
      let ph : PbvhInternal :=
        { bounds := windowBounds leaves sorted lo hi, offset := lo,
          span := hi - lo, skip := internals.size + 1,
          left := none, right := none }
      let state0 := internals.push ph
      have hstate0_size : state0.size = internals.size + 1 := by
        show (internals.push ph).size = internals.size + 1
        simp [Array.size_push]
      have hj_state0 : j < state0.size := by omega
      have hstate0_j : ∀ (h : j < state0.size), state0[j]'h = internals[j] := by
        intro h
        show (internals.push ph)[j]'h = internals[j]
        exact Array.getElem_push_lt hj
      -- IH on left call.
      have hleft_lt : mid - lo < n := by omega
      obtain ⟨hj_s1, hleft⟩ := ih (mid - lo) hleft_lt state0 lo mid rfl j hj_state0
      have hleft_j : (buildSubtree leaves sorted state0 lo mid).1[j]'hj_s1 =
          internals[j] := by rw [hleft]; exact hstate0_j hj_state0
      -- IH on right call.
      have hright_lt : hi - mid < n := by omega
      obtain ⟨hj_s2, hright⟩ := ih (hi - mid) hright_lt
        (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl j hj_s1
      have hbridge : (buildSubtree leaves sorted
          (buildSubtree leaves sorted state0 lo mid).1 mid hi).1[j]'hj_s2 =
            internals[j] := by rw [hright]; exact hleft_j
      -- set! at position internals.size doesn't touch j < internals.size.
      have hne : j ≠ internals.size := by omega
      refine ⟨?_, ?_⟩
      · show j < ((buildSubtree leaves sorted _ mid hi).1.set!
          internals.size _).size
        simp; exact hj_s2
      · show ((buildSubtree leaves sorted _ mid hi).1.set!
          internals.size _)[j]'_ = internals[j]
        rw [Array.getElem_set_ne (h := hne)]
        exact hbridge

-- ── Tier 2 helpers (aabbContains algebra) ──────────────────────────────────

/-- `aabbContains` is reflexive. -/
theorem aabbContains_refl (a : BoundingBox) : aabbContains a a := by
  simp [aabbContains]

/-- `aabbContains` is transitive: outer ⊇ mid ⊇ inner ⟹ outer ⊇ inner. -/
theorem aabbContains_trans {a b c : BoundingBox}
    (hab : aabbContains a b) (hbc : aabbContains b c) : aabbContains a c := by
  simp only [aabbContains] at *
  obtain ⟨h1, h2, h3, h4, h5, h6⟩ := hab
  obtain ⟨k1, k2, k3, k4, k5, k6⟩ := hbc
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩ <;> omega

/-- Containment is preserved by unioning more on the outer. Direct from
    reflexivity + `unionBounds_contains_left` + transitivity. -/
theorem aabbContains_unionBounds_mono_left (a b x : BoundingBox)
    (h : aabbContains a x) : aabbContains (unionBounds a b) x :=
  aabbContains_trans (unionBounds_contains_left a b) h

/-- A `foldl` of `unionBounds` contains its initial accumulator. -/
theorem foldl_unionBounds_contains_init (f : Nat → BoundingBox) :
    ∀ (l : List Nat) (init : BoundingBox),
      aabbContains (l.foldl (fun acc j => unionBounds acc (f j)) init) init := by
  intro l
  induction l with
  | nil => intro init; exact aabbContains_refl init
  | cons x xs ih =>
    intro init
    -- step extends init by `unionBounds init (f x)`, which contains init by left,
    -- then IH on the tail.
    have hstep : aabbContains (unionBounds init (f x)) init :=
      unionBounds_contains_left _ _
    have := ih (unionBounds init (f x))
    exact aabbContains_trans this hstep

/-- A `foldl` of `unionBounds` contains every element `f j` for `j ∈ l`. -/
theorem foldl_unionBounds_contains_item (f : Nat → BoundingBox) :
    ∀ (l : List Nat) (init : BoundingBox) (j : Nat), j ∈ l →
      aabbContains (l.foldl (fun acc k => unionBounds acc (f k)) init) (f j) := by
  intro l
  induction l with
  | nil => intro _ _ hj; exact absurd hj List.not_mem_nil
  | cons x xs ih =>
    intro init j hj
    simp only [List.mem_cons] at hj
    rcases hj with heq | htail
    · -- j = x: after one step, acc = unionBounds init (f x) ⊇ f x; foldl preserves.
      subst heq
      have hone : aabbContains (unionBounds init (f j)) (f j) :=
        unionBounds_contains_right _ _
      have hrest := foldl_unionBounds_contains_init f xs (unionBounds init (f j))
      exact aabbContains_trans hrest hone
    · -- j ∈ xs: recurse.
      exact ih (unionBounds init (f x)) j htail

/-- Generalized fold-contains-init: same as `foldl_unionBounds_contains_init`
    but lets the step function depend on the accumulator. Every step is
    `unionBounds acc _`, and `unionBounds_contains_left` works regardless of
    what the right operand is. -/
theorem foldl_unionBounds_dep_contains_init {α : Type _}
    (g : BoundingBox → α → BoundingBox) :
    ∀ (l : List α) (init : BoundingBox),
      aabbContains (l.foldl (fun acc a => unionBounds acc (g acc a)) init) init := by
  intro l
  induction l with
  | nil => intro init; exact aabbContains_refl init
  | cons x xs ih =>
    intro init
    have hstep : aabbContains (unionBounds init (g init x)) init :=
      unionBounds_contains_left _ _
    have := ih (unionBounds init (g init x))
    exact aabbContains_trans this hstep

/-- If `a ∈ l` and at position `a` the step produces a value whose union with
    the accumulator contains `x`, then the final fold result contains `x`. -/
theorem foldl_dep_contains_item {α : Type _}
    (g : BoundingBox → α → BoundingBox) (x : BoundingBox) :
    ∀ (l : List α) (a : α), a ∈ l →
      (∀ acc : BoundingBox, aabbContains (unionBounds acc (g acc a)) x) →
      ∀ init : BoundingBox,
        aabbContains (l.foldl (fun acc a' => unionBounds acc (g acc a')) init) x := by
  intro l
  induction l with
  | nil => intro _ ha _ _; exact absurd ha List.not_mem_nil
  | cons hd tl ih =>
    intro a ha hg init
    simp only [List.mem_cons] at ha
    rcases ha with heq | htail
    · subst heq
      have hhit : aabbContains (unionBounds init (g init a)) x := hg init
      have hrest := foldl_unionBounds_dep_contains_init g tl
        (unionBounds init (g init a))
      exact aabbContains_trans hrest hhit
    · exact ih a htail hg (unionBounds init (g init hd))

/-- Containment at the `init` slot of `windowBounds`: when `lo < hi` and
    the leaf at `sorted[lo]` resolves, its bounds are contained in the
    window union. -/
theorem windowBounds_contains_init_slot
    (leaves : Array PbvhLeaf) (sorted : Array LeafId) (lo hi : Nat)
    (hlo : lo < hi) (l : PbvhLeaf)
    (hl : leaves[sorted[lo]!]? = some l) :
    aabbContains (windowBounds leaves sorted lo hi) l.bounds := by
  unfold windowBounds
  rw [if_neg (by omega : ¬ lo ≥ hi)]
  dsimp only
  have hinit_eq : (leaves[sorted[lo]!]?.map (·.bounds)).getD
      { minX := 0, maxX := 0, minY := 0, maxY := 0, minZ := 0, maxZ := 0 } =
      l.bounds := by
    rw [hl]; simp
  rw [hinit_eq]
  exact foldl_unionBounds_dep_contains_init
    (fun acc j => (leaves[sorted[lo + j + 1]!]?.map (·.bounds)).getD acc)
    _ l.bounds

/-- Containment at a non-init slot `k = lo + j + 1` of `windowBounds`. -/
theorem windowBounds_contains_step_slot
    (leaves : Array PbvhLeaf) (sorted : Array LeafId) (lo hi : Nat)
    (hlo : lo < hi) (j : Nat) (hj : j < hi - lo - 1)
    (l : PbvhLeaf) (hl : leaves[sorted[lo + j + 1]!]? = some l) :
    aabbContains (windowBounds leaves sorted lo hi) l.bounds := by
  unfold windowBounds
  rw [if_neg (by omega : ¬ lo ≥ hi)]
  dsimp only
  apply foldl_dep_contains_item
    (g := fun acc j' => (leaves[sorted[lo + j' + 1]!]?.map (·.bounds)).getD acc)
    (x := l.bounds) (a := j)
  · exact List.mem_range.mpr hj
  · intro acc
    have hgj : (leaves[sorted[lo + j + 1]!]?.map (·.bounds)).getD acc = l.bounds := by
      rw [hl]; simp
    rw [hgj]
    exact unionBounds_contains_right _ _

/-- After `buildSubtree`, the root node's `bounds` field equals the window
    union over `[lo, hi)`. Both builder branches (leaf push, recursive set!)
    write `bounds := windowBounds leaves sorted lo hi`; this theorem reads
    that write back. Load-bearing for lifting `windowBounds_contains_*` into
    tree-level bound containment. -/
theorem buildSubtree_root_bounds
    (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat) :
    let r := (buildSubtree leaves sorted internals lo hi).1
    r[(buildSubtree leaves sorted internals lo hi).2]!.bounds =
      windowBounds leaves sorted lo hi ∧
    r[(buildSubtree leaves sorted internals lo hi).2]!.offset = lo ∧
    r[(buildSubtree leaves sorted internals lo hi).2]!.span = hi - lo := by
  rw [buildSubtree_root]
  unfold buildSubtree
  split
  · -- Base: the pushed leaf has bounds := windowBounds, offset := lo, span := hi - lo.
    dsimp only
    rw [Array.getElem!_eq_getD, Array.getD, dif_pos (by simp [Array.size_push])]
    simp [Array.getElem_push_eq]
  · -- Recursive: final `set!` at internals.size writes `updated` with the same fields.
    dsimp only
    obtain ⟨mid, _, _⟩ := computeMid leaves sorted lo hi (by omega)
    let ph : PbvhInternal :=
      { bounds := windowBounds leaves sorted lo hi, offset := lo,
        span := hi - lo, skip := internals.size + 1,
        left := none, right := none }
    let state0 := internals.push ph
    have h0 : state0.size = internals.size + 1 := by
      show (internals.push ph).size = internals.size + 1
      simp [Array.size_push]
    have h1 := buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
    have h2 := buildSubtree_size_ge leaves sorted _
      (buildSubtree leaves sorted state0 lo mid).1 mid hi rfl
    have hmyIdx : internals.size <
        (buildSubtree leaves sorted
          (buildSubtree leaves sorted state0 lo mid).1 mid hi).1.size := by
      omega
    show ((buildSubtree leaves sorted _ mid hi).1.set! internals.size _)[internals.size]!.bounds = _ ∧ _ ∧ _
    rw [Array.getElem!_eq_getD, Array.getD, dif_pos (by simp; exact hmyIdx)]
    refine ⟨?_, ?_, ?_⟩ <;> simp

/-- Root-level bound containment: for every live leaf in the window
    `sorted[lo, hi)`, the root node's bounds contain that leaf's bounds.
    Direct composition of `buildSubtree_root_bounds` with the
    `windowBounds_contains_*` lemmas. -/
theorem buildSubtree_root_contains_leaf
    (leaves : Array PbvhLeaf) (sorted : Array LeafId)
    (internals : Array PbvhInternal) (lo hi : Nat)
    (k : Nat) (hk_lo : lo ≤ k) (hk_hi : k < hi)
    (l : PbvhLeaf) (hl : leaves[sorted[k]!]? = some l) :
    let res := buildSubtree leaves sorted internals lo hi
    aabbContains res.1[res.2]!.bounds l.bounds := by
  obtain ⟨hb, _, _⟩ := buildSubtree_root_bounds leaves sorted internals lo hi
  dsimp only at hb ⊢
  rw [hb]
  have hlo : lo < hi := by omega
  by_cases heq : k = lo
  · subst heq
    exact windowBounds_contains_init_slot leaves sorted k hi hlo l hl
  · -- k = lo + (k - lo - 1) + 1, and k - lo - 1 < hi - lo - 1.
    have hk_gt : lo < k := by omega
    set j := k - lo - 1 with hj_def
    have hj_rewrite : lo + j + 1 = k := by omega
    have hj_lt : j < hi - lo - 1 := by omega
    rw [← hj_rewrite] at hl
    exact windowBounds_contains_step_slot leaves sorted lo hi hlo j hj_lt l hl

/-- **Per-node bounds shape.** Every newly-built internal node `j ≥
    internals.size` has `bounds = windowBounds sorted offset (offset + span)`.
    Proved by strong induction on `hi - lo`. The root slot (base case leaf,
    recursive case final `set!`) has its fields written directly. All
    sub-internals inherit via IH on the two recursive calls and are carried
    through `buildSubtree_preserves_prefix` across the subsequent sibling call
    and across the final `set!` (which only touches index `internals.size`). -/
theorem buildSubtree_new_node_bounds (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat), internals.size ≤ j →
        ∀ (hj : j < (buildSubtree leaves sorted internals lo hi).1.size),
          let node := (buildSubtree leaves sorted internals lo hi).1[j]'hj
          node.bounds = windowBounds leaves sorted node.offset
            (node.offset + node.span) := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro internals lo hi hn j hj_ge hj
    unfold buildSubtree
    split
    · -- Base: only the pushed leaf exists at index internals.size.
      rename_i hle
      dsimp only at hj ⊢
      have hpsize : (internals.push _).size = internals.size + 1 := by
        simp [Array.size_push]
      have hj_eq : j = internals.size := by
        have hlt : j < internals.size + 1 := by rw [← hpsize]; exact hj
        omega
      subst hj_eq
      rw [Array.getElem_push_eq]
      -- Pushed leaf: bounds = windowBounds lo hi, offset = lo, span = hi - lo.
      -- Need: windowBounds lo hi = windowBounds lo (lo + (hi - lo)).
      by_cases hlo : lo ≥ hi
      · -- lo ≥ hi: windowBounds lo hi returns the zero box; so does windowBounds lo lo.
        unfold windowBounds
        have h1 : (lo ≥ hi) = True := by simp [hlo]
        have h2 : (lo ≥ lo + (hi - lo)) = True := by simp; omega
        simp [h1, h2]
      · -- lo < hi: lo + (hi - lo) = hi.
        have : lo + (hi - lo) = hi := by omega
        rw [this]
    · -- Recursive: work through state0 → s1 → s2 → set!.
      rename_i hgt
      dsimp only at hj ⊢
      obtain ⟨mid, hmlo, hmhi⟩ := computeMid leaves sorted lo hi (by omega)
      let ph : PbvhInternal :=
        { bounds := windowBounds leaves sorted lo hi, offset := lo,
          span := hi - lo, skip := internals.size + 1,
          left := none, right := none }
      let state0 := internals.push ph
      have hstate0_size : state0.size = internals.size + 1 := by
        show (internals.push ph).size = internals.size + 1
        simp [Array.size_push]
      have hleft_lt : mid - lo < n := by omega
      have hright_lt : hi - mid < n := by omega
      set s1 := (buildSubtree leaves sorted state0 lo mid).1 with hs1
      set s2 := (buildSubtree leaves sorted s1 mid hi).1 with hs2
      have hs1_ge : state0.size ≤ s1.size :=
        buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
      have hs2_ge : s1.size ≤ s2.size :=
        buildSubtree_size_ge leaves sorted _ s1 mid hi rfl
      have hmyIdx_lt : internals.size < s2.size := by omega
      -- Goal shape after unfold: s2.set! internals.size updated_record
      show let node := (s2.set! internals.size _)[j]'(by simp; exact hj)
        node.bounds = windowBounds leaves sorted node.offset
          (node.offset + node.span)
      dsimp only
      by_cases hj_eq : j = internals.size
      · -- j is the root slot: set! writes updated with bounds=windowBounds lo hi.
        subst hj_eq
        rw [Array.getElem_set_eq (by simp; omega)]
        by_cases hlo : lo ≥ hi
        · unfold windowBounds
          have h1 : (lo ≥ hi) = True := by simp [hlo]
          have h2 : (lo ≥ lo + (hi - lo)) = True := by simp; omega
          simp [h1, h2]
        · have : lo + (hi - lo) = hi := by omega
          rw [this]
      · -- j > internals.size: set! doesn't touch j; reduce to s2[j].
        rw [Array.getElem_set_ne (h := hj_eq)]
        have hj_s2 : j < s2.size := by
          have hj' : j < (s2.set! internals.size _).size := hj
          simp at hj'; exact hj'
        by_cases hj_s1 : j < s1.size
        · -- j < s1.size: preserves_prefix on subcall2 carries s1[j] to s2[j].
          obtain ⟨_, hpresv⟩ := buildSubtree_preserves_prefix leaves sorted
            (hi - mid) s1 mid hi rfl j hj_s1
          have hs2_j : s2[j]'hj_s2 = s1[j]'hj_s1 := by
            change (buildSubtree leaves sorted s1 mid hi).1[j]'_ = _
            exact hpresv
          rw [hs2_j]
          -- j in [state0.size, s1.size): IH on subcall1.
          have hj_state0 : state0.size ≤ j := by omega
          have ih1 := ih (mid - lo) hleft_lt state0 lo mid rfl j hj_state0 hj_s1
          exact ih1
        · -- j ≥ s1.size: IH on subcall2 directly gives the claim on s2[j].
          push_neg at hj_s1
          have ih2 := ih (hi - mid) hright_lt s1 mid hi rfl j hj_s1 hj_s2
          exact ih2

/-- **Per-node bound containment.** For every newly-built internal node
    `j ≥ internals.size` and every leaf position `k` in its window
    `[offset, offset + span)`, the node's bounds contain the leaf's bounds.
    Direct composition of `buildSubtree_new_node_bounds` with the
    `windowBounds_contains_*_slot` lemmas. -/
theorem buildSubtree_new_node_contains_leaf (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) (internals : Array PbvhInternal) (lo hi : Nat)
    (j : Nat) (hj_ge : internals.size ≤ j)
    (hj : j < (buildSubtree leaves sorted internals lo hi).1.size)
    (l : PbvhLeaf) (k : Nat)
    (node_offset_le : ((buildSubtree leaves sorted internals lo hi).1[j]'hj).offset ≤ k)
    (k_lt_node_end :
      k < ((buildSubtree leaves sorted internals lo hi).1[j]'hj).offset +
          ((buildSubtree leaves sorted internals lo hi).1[j]'hj).span)
    (hl : leaves[sorted[k]!]? = some l) :
    aabbContains ((buildSubtree leaves sorted internals lo hi).1[j]'hj).bounds
      l.bounds := by
  set r := (buildSubtree leaves sorted internals lo hi).1 with hr
  have hb := buildSubtree_new_node_bounds leaves sorted (hi - lo) internals lo hi
    rfl j hj_ge hj
  dsimp only at hb
  rw [hb]
  set o := (r[j]'hj).offset
  set s := (r[j]'hj).span
  have hlo : o < o + s := by omega
  by_cases hk_eq : k = o
  · subst hk_eq
    exact windowBounds_contains_init_slot leaves sorted k (o + s) hlo l hl
  · have hk_gt : o < k := by omega
    set j' := k - o - 1 with hj'_def
    have hj'_rewrite : o + j' + 1 = k := by omega
    have hj'_lt : j' < (o + s) - o - 1 := by omega
    rw [← hj'_rewrite] at hl
    exact windowBounds_contains_step_slot leaves sorted o (o + s) hlo j' hj'_lt l hl

/-- **Per-node skip monotonicity.** Every newly-built internal node `j ≥
    internals.size` has `j < skip[j] ≤ result.size`. Strong induction on
    `hi - lo`, threaded through `state0 → s1 → s2 → set!`. The root slot
    after the final `set!` carries `skip = result.size` directly; sub-internals
    inherit via IH on both recursive calls, with `preserves_prefix` bridging
    across the sibling call and the final `set!`. This subsumes
    `buildSubtree_root_skip_monotone` and is the structural invariant that
    lets the Tier 3 completeness contrapositive reason about DFS children. -/
theorem buildSubtree_new_node_skip_monotone (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat), internals.size ≤ j →
        ∀ (hj : j < (buildSubtree leaves sorted internals lo hi).1.size),
          j < ((buildSubtree leaves sorted internals lo hi).1[j]'hj).skip ∧
          ((buildSubtree leaves sorted internals lo hi).1[j]'hj).skip ≤
            (buildSubtree leaves sorted internals lo hi).1.size := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro internals lo hi hn j hj_ge hj
    unfold buildSubtree
    split
    · -- Base: pushed leaf has skip = internals.size + 1 = (push).size.
      rename_i hle
      dsimp only at hj ⊢
      have hpsize : (internals.push _).size = internals.size + 1 := by
        simp [Array.size_push]
      have hj_eq : j = internals.size := by
        have hlt : j < internals.size + 1 := by rw [← hpsize]; exact hj
        omega
      subst hj_eq
      rw [Array.getElem_push_eq]
      refine ⟨?_, ?_⟩
      · show internals.size < internals.size + 1; omega
      · show internals.size + 1 ≤ (internals.push _).size
        simp [Array.size_push]
    · -- Recursive: s2.set! internals.size updated; updated.skip = s2.size.
      rename_i hgt
      dsimp only at hj ⊢
      obtain ⟨mid, hmlo, hmhi⟩ := computeMid leaves sorted lo hi (by omega)
      let ph : PbvhInternal :=
        { bounds := windowBounds leaves sorted lo hi, offset := lo,
          span := hi - lo, skip := internals.size + 1,
          left := none, right := none }
      let state0 := internals.push ph
      have hstate0_size : state0.size = internals.size + 1 := by
        show (internals.push ph).size = internals.size + 1
        simp [Array.size_push]
      have hleft_lt : mid - lo < n := by omega
      have hright_lt : hi - mid < n := by omega
      set s1 := (buildSubtree leaves sorted state0 lo mid).1 with hs1
      set s2 := (buildSubtree leaves sorted s1 mid hi).1 with hs2
      have hs1_ge : state0.size ≤ s1.size :=
        buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
      have hs2_ge : s1.size ≤ s2.size :=
        buildSubtree_size_ge leaves sorted _ s1 mid hi rfl
      have hmyIdx_lt : internals.size < s2.size := by omega
      show let node := (s2.set! internals.size _)[j]'(by simp; exact hj)
        j < node.skip ∧ node.skip ≤ (s2.set! internals.size _).size
      dsimp only
      by_cases hj_eq : j = internals.size
      · -- Root slot: set! writes updated with skip = s2.size = (set!).size.
        subst hj_eq
        rw [Array.getElem_set_eq (by simp; omega)]
        refine ⟨?_, ?_⟩
        · show internals.size < s2.size; omega
        · show s2.size ≤ (s2.set! internals.size _).size; simp
      · -- j > internals.size: set! doesn't touch j; reduce to s2[j].
        rw [Array.getElem_set_ne (h := hj_eq)]
        have hj_s2 : j < s2.size := by
          have hj' : j < (s2.set! internals.size _).size := hj
          simp at hj'; exact hj'
        have hend : (s2.set! internals.size _).size = s2.size := by simp
        rw [hend]
        by_cases hj_s1 : j < s1.size
        · -- j ∈ (internals.size, s1.size): preserves_prefix on subcall2.
          obtain ⟨_, hpresv⟩ := buildSubtree_preserves_prefix leaves sorted
            (hi - mid) s1 mid hi rfl j hj_s1
          have hs2_j : s2[j]'hj_s2 = s1[j]'hj_s1 := by
            change (buildSubtree leaves sorted s1 mid hi).1[j]'_ = _
            exact hpresv
          rw [hs2_j]
          -- IH on subcall1 gives skip bounds relative to s1.size.
          have hj_state0 : state0.size ≤ j := by omega
          have ih1 := ih (mid - lo) hleft_lt state0 lo mid rfl j hj_state0 hj_s1
          refine ⟨ih1.1, ?_⟩
          exact Nat.le_trans ih1.2 hs2_ge
        · -- j ∈ [s1.size, s2.size): IH on subcall2 directly.
          push_neg at hj_s1
          exact ih (hi - mid) hright_lt s1 mid hi rfl j hj_s1 hj_s2

/-- **Leaf-block skip equals next DFS index.** For every newly-built
    internal `j ≥ internals.size`, if both children are `none` then
    `skip[j] = j + 1`. Strong induction on `hi - lo`:
    base case pushes a leaf with this exact shape; recursive case shows
    the root (at `internals.size`) *always* has children `= some _`
    (vacuous antecedent), and propagates to descendants via
    `preserves_prefix` across the final `set!` + sibling subcall.

    This is one half of `skip_equals_dfs_next`: leaf-block nodes have
    `skip = i + 1`, so the DFS advance after a leaf-block via the skip
    pointer is the same as the advance via `i + 1`. -/
theorem buildSubtree_new_node_leaf_block_skip (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat), internals.size ≤ j →
        ∀ (hj : j < (buildSubtree leaves sorted internals lo hi).1.size),
          let node := (buildSubtree leaves sorted internals lo hi).1[j]'hj
          node.left = none → node.right = none → node.skip = j + 1 := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro internals lo hi hn j hj_ge hj
    unfold buildSubtree
    split
    · -- Base: pushed leaf with skip = internals.size + 1 and left/right = none.
      rename_i hle
      dsimp only at hj ⊢
      have hpsize : (internals.push _).size = internals.size + 1 := by
        simp [Array.size_push]
      have hj_eq : j = internals.size := by
        have hlt : j < internals.size + 1 := by rw [← hpsize]; exact hj
        omega
      subst hj_eq
      rw [Array.getElem_push_eq]
      intro _ _; rfl
    · -- Recursive: root at internals.size has children = some (vacuous).
      rename_i hgt
      dsimp only at hj ⊢
      obtain ⟨mid, hmlo, hmhi⟩ := computeMid leaves sorted lo hi (by omega)
      let ph : PbvhInternal :=
        { bounds := windowBounds leaves sorted lo hi, offset := lo,
          span := hi - lo, skip := internals.size + 1,
          left := none, right := none }
      let state0 := internals.push ph
      have hstate0_size : state0.size = internals.size + 1 := by
        show (internals.push ph).size = internals.size + 1
        simp [Array.size_push]
      have hleft_lt : mid - lo < n := by omega
      have hright_lt : hi - mid < n := by omega
      set s1 := (buildSubtree leaves sorted state0 lo mid).1 with hs1
      set s2 := (buildSubtree leaves sorted s1 mid hi).1 with hs2
      have hs1_ge : state0.size ≤ s1.size :=
        buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
      have hs2_ge : s1.size ≤ s2.size :=
        buildSubtree_size_ge leaves sorted _ s1 mid hi rfl
      show let node := (s2.set! internals.size _)[j]'(by simp; exact hj)
        node.left = none → node.right = none → node.skip = j + 1
      dsimp only
      by_cases hj_eq : j = internals.size
      · -- Root slot: updated record has left = some _, so hleft is false.
        subst hj_eq
        rw [Array.getElem_set_eq (by simp; omega)]
        intro hleft _
        -- `updated.left = some leftIdx`; reduces the antecedent to False.
        exact absurd hleft (by simp)
      · -- j > internals.size: set! doesn't touch j; reduce to s2[j].
        rw [Array.getElem_set_ne (h := hj_eq)]
        have hj_s2 : j < s2.size := by
          have hj' : j < (s2.set! internals.size _).size := hj
          simp at hj'; exact hj'
        by_cases hj_s1 : j < s1.size
        · -- Preserves_prefix across subcall2, then IH on subcall1.
          obtain ⟨_, hpresv⟩ := buildSubtree_preserves_prefix leaves sorted
            (hi - mid) s1 mid hi rfl j hj_s1
          have hs2_j : s2[j]'hj_s2 = s1[j]'hj_s1 := by
            change (buildSubtree leaves sorted s1 mid hi).1[j]'_ = _
            exact hpresv
          rw [hs2_j]
          have hj_state0 : state0.size ≤ j := by omega
          exact ih (mid - lo) hleft_lt state0 lo mid rfl j hj_state0 hj_s1
        · -- j ≥ s1.size: IH on subcall2 directly.
          push_neg at hj_s1
          exact ih (hi - mid) hright_lt s1 mid hi rfl j hj_s1 hj_s2

/-- **Non-leaf DFS skip chain.** For every newly-built internal node `j`
    with both children `some`, the left child sits at `j + 1`, and the
    right child's index equals `skip[left_child]`. Combined with
    `buildSubtree_skip_eq_final_size` (at each subcall) this says the
    right sibling starts exactly where the left subtree ends — the
    defining property of a pre-order DFS layout.

    Strong induction on `hi - lo`. Root slot uses the fact that
    `updated.left = some state0.size` and `updated.right = some s1.size`,
    and the left child (at `state0.size`) is the root of subcall1 so its
    `skip` equals `s1.size` by the root-skip-eq-final-size anchor
    (read through preserves_prefix across subcall2 and the final set!). -/
theorem buildSubtree_new_node_right_is_left_skip (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) :
    ∀ (n : Nat) (internals : Array PbvhInternal) (lo hi : Nat), hi - lo = n →
      ∀ (j : Nat), internals.size ≤ j →
        ∀ (hj : j < (buildSubtree leaves sorted internals lo hi).1.size),
          let r := (buildSubtree leaves sorted internals lo hi).1
          ∀ (L R : Nat),
            (r[j]'hj).left = some L → (r[j]'hj).right = some R →
            ∃ (hL : L < r.size), L = j + 1 ∧ (r[L]'hL).skip = R := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro internals lo hi hn j hj_ge hj
    unfold buildSubtree
    split
    · -- Base: pushed leaf has left = none; vacuous antecedent.
      rename_i hle
      dsimp only at hj ⊢
      have hpsize : (internals.push _).size = internals.size + 1 := by
        simp [Array.size_push]
      have hj_eq : j = internals.size := by
        have hlt : j < internals.size + 1 := by rw [← hpsize]; exact hj
        omega
      subst hj_eq
      rw [Array.getElem_push_eq]
      intro L R hL _; exact absurd hL (by simp)
    · -- Recursive case.
      rename_i hgt
      dsimp only at hj ⊢
      obtain ⟨mid, hmlo, hmhi⟩ := computeMid leaves sorted lo hi (by omega)
      let ph : PbvhInternal :=
        { bounds := windowBounds leaves sorted lo hi, offset := lo,
          span := hi - lo, skip := internals.size + 1,
          left := none, right := none }
      let state0 := internals.push ph
      have hstate0_size : state0.size = internals.size + 1 := by
        show (internals.push ph).size = internals.size + 1
        simp [Array.size_push]
      have hleft_lt : mid - lo < n := by omega
      have hright_lt : hi - mid < n := by omega
      set s1 := (buildSubtree leaves sorted state0 lo mid).1 with hs1
      set s2 := (buildSubtree leaves sorted s1 mid hi).1 with hs2
      have hs1_ge : state0.size ≤ s1.size :=
        buildSubtree_size_ge leaves sorted _ state0 lo mid rfl
      have hs2_ge : s1.size ≤ s2.size :=
        buildSubtree_size_ge leaves sorted _ s1 mid hi rfl
      -- `buildSubtree_root` says subcall1's returned index is state0.size.
      have hroot1 := buildSubtree_root leaves sorted state0 lo mid
      have hroot2 := buildSubtree_root leaves sorted s1 mid hi
      -- skip-eq-final anchors.
      have hskip1 := buildSubtree_skip_eq_final_size leaves sorted state0 lo mid
      have hskip2 := buildSubtree_skip_eq_final_size leaves sorted s1 mid hi
      show let node := (s2.set! internals.size _)[j]'(by simp; exact hj)
        ∀ (L R : Nat),
          node.left = some L → node.right = some R →
          ∃ (hL : L < (s2.set! internals.size _).size),
            L = j + 1 ∧ ((s2.set! internals.size _)[L]'hL).skip = R
      dsimp only
      by_cases hj_eq : j = internals.size
      · -- Root slot: `updated` has left = some state0.size, right = some s1.size.
        subst hj_eq
        rw [Array.getElem_set_eq (by simp; omega)]
        intro L R hL hR
        -- From the literal `updated`, L = state0.size = internals.size + 1.
        have hL_eq : L = state0.size := by
          have : some L = some state0.size := by
            simpa using hL
          exact Option.some.inj this |>.symm
        have hR_eq : R = s1.size := by
          have : some R = some s1.size := by
            simpa using hR
          exact Option.some.inj this |>.symm
        have hL_lt : L < s2.size := by rw [hL_eq]; omega
        refine ⟨by simp; exact hL_lt, ?_, ?_⟩
        · rw [hL_eq]; omega
        · -- After set! at internals.size, reading L ≠ internals.size (since
          -- L = state0.size > internals.size) yields s2[L].
          have hne : L ≠ internals.size := by rw [hL_eq]; omega
          rw [Array.getElem_set_ne (h := hne)]
          -- s2[L] = s1[L] by preserves_prefix (since L < s1.size: L = state0.size ≤ s1.size via hs1_ge).
          have hL_s1 : L < s1.size := by rw [hL_eq]; omega
          obtain ⟨_, hpresv⟩ := buildSubtree_preserves_prefix leaves sorted
            (hi - mid) s1 mid hi rfl L hL_s1
          have hs2_L : s2[L]'(by omega) = s1[L]'hL_s1 := by
            change (buildSubtree leaves sorted s1 mid hi).1[L]'_ = _
            exact hpresv
          rw [hs2_L]
          -- s1[L] is the root returned by subcall1 (since L = state0.size and
          -- subcall1's returned root index = state0.size).
          rw [hL_eq]
          -- Use skip-eq-final on subcall1: s1[state0.size].skip = s1.size.
          have hroot1_idx : (buildSubtree leaves sorted state0 lo mid).2 =
              state0.size := hroot1
          -- hskip1 reads: s1[subcall1.2]!.skip = s1.size.
          have : s1[state0.size]'hL_s1 = s1[state0.size]! := by
            rw [Array.getElem!_eq_getD, Array.getD, dif_pos hL_s1]
          rw [this, ← hroot1_idx]
          exact hskip1.trans hR_eq.symm
      · -- j > internals.size.
        rw [Array.getElem_set_ne (h := hj_eq)]
        have hj_s2 : j < s2.size := by
          have hj' : j < (s2.set! internals.size _).size := hj
          simp at hj'; exact hj'
        intro L R hL hR
        by_cases hj_s1 : j < s1.size
        · -- j < s1.size: s2[j] = s1[j] by preserves_prefix subcall2; IH on subcall1.
          obtain ⟨_, hpresv⟩ := buildSubtree_preserves_prefix leaves sorted
            (hi - mid) s1 mid hi rfl j hj_s1
          have hs2_j : s2[j]'hj_s2 = s1[j]'hj_s1 := by
            change (buildSubtree leaves sorted s1 mid hi).1[j]'_ = _
            exact hpresv
          rw [hs2_j] at hL hR
          have hj_state0 : state0.size ≤ j := by omega
          obtain ⟨hL_s1, hL_eq, hL_skip⟩ := ih (mid - lo) hleft_lt state0 lo mid
            rfl j hj_state0 hj_s1 L R hL hR
          have hL_s2 : L < s2.size := Nat.lt_of_lt_of_le hL_s1 hs2_ge
          have hL_ne : L ≠ internals.size := by omega
          refine ⟨by simp; exact hL_s2, hL_eq, ?_⟩
          rw [Array.getElem_set_ne (h := hL_ne)]
          -- s2[L] = s1[L] by preserves_prefix subcall2.
          obtain ⟨_, hpresvL⟩ := buildSubtree_preserves_prefix leaves sorted
            (hi - mid) s1 mid hi rfl L hL_s1
          have hs2_L : s2[L]'hL_s2 = s1[L]'hL_s1 := by
            change (buildSubtree leaves sorted s1 mid hi).1[L]'_ = _
            exact hpresvL
          rw [hs2_L]; exact hL_skip
        · -- j ≥ s1.size: IH on subcall2 directly.
          push_neg at hj_s1
          obtain ⟨hL_s2, hL_eq, hL_skip⟩ := ih (hi - mid) hright_lt s1 mid hi
            rfl j hj_s1 hj_s2 L R hL hR
          have hL_ne : L ≠ internals.size := by omega
          refine ⟨by simp; exact hL_s2, hL_eq, ?_⟩
          rw [Array.getElem_set_ne (h := hL_ne)]
          exact hL_skip

-- ── Tier 3 preparatory lemmas (query soundness predicate is stable) ─────────

/-- The soundness witness for one eclass `e`: a live leaf whose bounds
    overlap the query and whose eclass equals `e`. -/
def querySoundOf (t : PbvhTree) (q : BoundingBox) (e : EClassId) : Prop :=
  ∃ (idx : LeafId) (h : idx < t.leaves.size),
    t.leaves[idx].alive = true ∧
    t.leaves[idx].eclass = e ∧
    aabbOverlapsDec t.leaves[idx].bounds q = true

/-- The leaf-block fold inside `aabbQueryN.go` preserves the "every emitted
    eclass has a sound witness" invariant. The fold's body is the ONLY site
    where eclasses are emitted into the accumulator, and it emits `l.eclass`
    only under `l.alive ∧ aabbOverlapsDec l.bounds q` — exactly the witness. -/
theorem aabbQueryN_leaf_fold_preserves_sound (t : PbvhTree) (q : BoundingBox)
    (offset span : Nat) (acc : List EClassId)
    (hacc : ∀ e ∈ acc, querySoundOf t q e) :
    ∀ e ∈ (List.range span).foldl (fun acc j =>
            let lid := t.sorted[offset + j]!
            match t.leaves[lid]? with
            | some l =>
              if l.alive && aabbOverlapsDec l.bounds q then
                l.eclass :: acc else acc
            | none => acc) acc,
      querySoundOf t q e := by
  apply foldl_invariant
    (P := fun (acc : List EClassId) => ∀ e ∈ acc, querySoundOf t q e)
    (f := fun acc j =>
      let lid := t.sorted[offset + j]!
      match t.leaves[lid]? with
      | some l =>
        if l.alive && aabbOverlapsDec l.bounds q then
          l.eclass :: acc else acc
      | none => acc)
    (List.range span) acc hacc
  intro acc' j hacc'
  -- Case split on the leaf lookup and the emission guard.
  set lid := t.sorted[offset + j]!
  cases hlk : t.leaves[lid]? with
  | none => simpa [hlk] using hacc'
  | some l =>
    by_cases hg : l.alive ∧ aabbOverlapsDec l.bounds q = true
    · -- Guarded emission: new head is `l.eclass`, witness is `lid`.
      obtain ⟨halive, hov⟩ := hg
      have hlid_lt : lid < t.leaves.size := by
        rcases Array.getElem?_eq_some_iff.mp hlk with ⟨h, _⟩
        exact h
      have hleq : t.leaves[lid]'hlid_lt = l := by
        rw [← Array.getElem?_eq_getElem hlid_lt] at hlk
        exact Option.some.inj hlk
      simp only [hlk, halive, hov, Bool.and_self, and_self, if_true]
      intro e he
      simp only [List.mem_cons] at he
      rcases he with heq | htail
      · refine ⟨lid, hlid_lt, ?_, ?_, ?_⟩
        · rw [hleq]; exact halive
        · rw [hleq]; exact heq.symm
        · rw [hleq]; exact hov
      · exact hacc' e htail
    · -- Guard fails: no emission.
      push_neg at hg
      by_cases halive : l.alive
      · have hov : aabbOverlapsDec l.bounds q = false := by
          have := hg halive
          cases hov' : aabbOverlapsDec l.bounds q
          · rfl
          · rw [hov'] at this; exact absurd rfl this
        simp only [hlk, halive, hov, Bool.and_false, if_false]
        exact hacc'
      · simp only [hlk, halive, Bool.false_and, if_false]
        exact hacc'

/-- Extension lemma: a cons-only foldl preserves every element already in
    the initial accumulator. The step function `f` is constrained to only
    *extend* the accumulator — never drop elements. -/
private theorem foldl_cons_preserves {α β : Type _}
    (f : List β → α → List β)
    (hmono : ∀ (acc : List β) (a : α) (x : β), x ∈ acc → x ∈ f acc a) :
    ∀ (l : List α) (init : List β) (x : β), x ∈ init →
      x ∈ l.foldl f init := by
  intro l
  induction l with
  | nil => intro _ _ hx; exact hx
  | cons hd tl ih =>
    intro init x hx
    simp only [List.foldl_cons]
    exact ih (f init hd) x (hmono init hd x hx)

/-- **Leaf-fold completeness.** If position `j < span` resolves to a live
    leaf whose bounds overlap the query, then the leaf's eclass appears in
    the fold result. Induction on `span`: at the target step the guard fires
    so the emission is cons'd in; later steps only extend the list. -/
theorem aabbQueryN_leaf_fold_emits (t : PbvhTree) (q : BoundingBox)
    (offset span : Nat) (acc : List EClassId)
    (j : Nat) (hj : j < span)
    (l : PbvhLeaf)
    (hl : t.leaves[t.sorted[offset + j]!]? = some l)
    (halive : l.alive = true)
    (hov : aabbOverlapsDec l.bounds q = true) :
    l.eclass ∈ (List.range span).foldl (fun acc j =>
      let lid := t.sorted[offset + j]!
      match t.leaves[lid]? with
      | some l =>
        if l.alive && aabbOverlapsDec l.bounds q then
          l.eclass :: acc else acc
      | none => acc) acc := by
  -- Step function is monotone (extension-only).
  set f : List EClassId → Nat → List EClassId := fun acc j =>
    let lid := t.sorted[offset + j]!
    match t.leaves[lid]? with
    | some l =>
      if l.alive && aabbOverlapsDec l.bounds q then
        l.eclass :: acc else acc
    | none => acc with hf_def
  have hmono : ∀ (acc : List EClassId) (k : Nat) (x : EClassId),
      x ∈ acc → x ∈ f acc k := by
    intro acc k x hx
    simp only [hf_def]
    cases hlk : t.leaves[t.sorted[offset + k]!]? with
    | none => simpa [hlk] using hx
    | some l' =>
      by_cases hg : l'.alive && aabbOverlapsDec l'.bounds q
      · simp only [hlk, hg, if_true]; exact List.mem_cons_of_mem _ hx
      · simp only [hlk, hg, if_false]; exact hx
  -- Induct on span.
  induction span with
  | zero => exact absurd hj (by omega)
  | succ n ih =>
    rw [List.range_succ, List.foldl_append]
    simp only [List.foldl_cons, List.foldl_nil]
    by_cases hjn : j = n
    · -- Target step is the last one: guard fires, emission cons'd.
      subst hjn
      have hemit :
          f ((List.range j).foldl f acc) j =
          l.eclass :: (List.range j).foldl f acc := by
        simp only [hf_def, hl, halive, hov, Bool.and_self, if_true]
      rw [hemit]; exact List.mem_cons_self
    · -- Target step earlier than last: IH places eclass in acc', then
      -- the final step preserves it via `hmono`.
      have hj' : j < n := by omega
      have hin : l.eclass ∈ (List.range n).foldl f acc := ih hj'
      exact hmono _ n _ hin

/-- Soundness invariant for `aabbQueryNGo`: if every eclass already in `acc`
    has a sound witness, so does every eclass in the result. Proved by strong
    induction on the termination measure `t.internals.size - i`. At each
    step the only accumulator extension is the leaf-block fold, whose
    preservation is handled by `aabbQueryN_leaf_fold_preserves_sound`. -/
theorem aabbQueryNGo_preserves_sound (t : PbvhTree) (q : BoundingBox) :
    ∀ (m : Nat) (i : Nat) (acc : List EClassId),
      t.internals.size - i = m →
      (∀ e ∈ acc, querySoundOf t q e) →
      ∀ e ∈ aabbQueryNGo t q i acc, querySoundOf t q e := by
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
    intro i acc hm hacc e he
    rw [aabbQueryNGo] at he
    dsimp only at he
    split at he
    · -- i ≥ end_: result = acc.reverse.
      rw [List.mem_reverse] at he
      exact hacc e he
    · -- i < end_: three sub-cases (prune, leaf block, descend).
      rename_i hlt
      have hi_lt : i < t.internals.size := by omega
      set n := t.internals[i]! with hn_def
      set next : Nat :=
        if _ : i < n.skip ∧ n.skip ≤ t.internals.size then n.skip else i + 1
        with hnext_def
      have hnext_gt : next > i := by
        rw [hnext_def]; split <;> rename_i h <;> omega
      have hnext_le : next ≤ t.internals.size := by
        rw [hnext_def]; split <;> rename_i h <;> omega
      have hnext_measure : t.internals.size - next < m := by omega
      split at he
      · -- Prune: recurse with `next acc`.
        exact ih _ hnext_measure next acc rfl hacc e he
      · split at he
        · -- Leaf block: fold then recurse with `next acc'`.
          have hfold := aabbQueryN_leaf_fold_preserves_sound t q n.offset n.span acc hacc
          exact ih _ hnext_measure next _ rfl hfold e he
        · -- Descend: recurse with `(i+1) acc`.
          have hi1_measure : t.internals.size - (i + 1) < m := by omega
          exact ih _ hi1_measure (i + 1) acc rfl hacc e he

/-- **Tier 3 — aabbQueryN_sound.** Every eclass returned by `aabbQueryN`
    has a live leaf in the tree whose bounds overlap the query and whose
    eclass equals the returned value. Directly composes
    `aabbQueryNGo_preserves_sound` starting from `acc = []`. -/
theorem aabbQueryN_sound (t : PbvhTree) (q : BoundingBox) :
    ∀ e ∈ aabbQueryN t q, querySoundOf t q e := by
  intro e he
  unfold aabbQueryN at he
  split at he
  · exact absurd he List.not_mem_nil
  · exact aabbQueryNGo_preserves_sound t q _ _ [] rfl
      (fun _ h => absurd h List.not_mem_nil) e he

/-- **Accumulator membership is preserved** through `aabbQueryNGo`. If
    `e ∈ acc`, then `e` is in the result. Strong induction on the termination
    measure. The leaf-block fold only extends `acc` (via `foldl_cons_preserves`
    reasoning), and the base case `acc.reverse` preserves membership via
    `List.mem_reverse`. This is the compositional piece that combines with
    `aabbQueryN_leaf_fold_emits` to give local completeness at any reached
    leaf-block. -/
theorem aabbQueryNGo_preserves_membership (t : PbvhTree) (q : BoundingBox) :
    ∀ (m : Nat) (i : Nat) (acc : List EClassId) (e : EClassId),
      t.internals.size - i = m →
      e ∈ acc →
      e ∈ aabbQueryNGo t q i acc := by
  intro m
  induction m using Nat.strongRecOn with
  | _ m ih =>
    intro i acc e hm he
    rw [aabbQueryNGo]
    dsimp only
    split
    · -- Base: result = acc.reverse; membership via mem_reverse.
      rw [List.mem_reverse]; exact he
    · rename_i hlt
      have hi_lt : i < t.internals.size := by omega
      set n := t.internals[i]! with hn_def
      set next : Nat :=
        if _ : i < n.skip ∧ n.skip ≤ t.internals.size then n.skip else i + 1
        with hnext_def
      have hnext_gt : next > i := by
        rw [hnext_def]; split <;> rename_i h <;> omega
      have hnext_le : next ≤ t.internals.size := by
        rw [hnext_def]; split <;> rename_i h <;> omega
      have hnext_measure : t.internals.size - next < m := by omega
      split
      · exact ih _ hnext_measure next acc e rfl he
      · split
        · -- Leaf block: fold extends acc; fold membership gives e ∈ acc'.
          have hfold : e ∈ (List.range n.span).foldl (fun acc j =>
              let lid := t.sorted[n.offset + j]!
              match t.leaves[lid]? with
              | some l =>
                if l.alive && aabbOverlapsDec l.bounds q then
                  l.eclass :: acc else acc
              | none => acc) acc := by
            -- Direct use of foldl_cons_preserves with the extend-only shape.
            have hmono : ∀ (acc : List EClassId) (k : Nat) (x : EClassId),
                x ∈ acc →
                x ∈ (fun acc j =>
                  let lid := t.sorted[n.offset + j]!
                  match t.leaves[lid]? with
                  | some l =>
                    if l.alive && aabbOverlapsDec l.bounds q then
                      l.eclass :: acc else acc
                  | none => acc) acc k := by
              intro acc' k x hx
              dsimp only
              cases hlk : t.leaves[t.sorted[n.offset + k]!]? with
              | none => simpa [hlk] using hx
              | some l' =>
                by_cases hg : l'.alive && aabbOverlapsDec l'.bounds q
                · simp only [hlk, hg, if_true]; exact List.mem_cons_of_mem _ hx
                · simp only [hlk, hg, if_false]; exact hx
            exact foldl_cons_preserves _ hmono (List.range n.span) acc e he
          exact ih _ hnext_measure next _ e rfl hfold
        · have hi1_measure : t.internals.size - (i + 1) < m := by omega
          exact ih _ hi1_measure (i + 1) acc e rfl he

/-- **Local completeness at a reached leaf-block.** If `aabbQueryNGo` is
    called at an index `i` whose node is a leaf-block (no children) with
    overlapping bounds, and a live leaf in the window overlaps the query,
    then the leaf's eclass is in the result.

    This is *local* — the "aabbQueryNGo called at i" assumption is load-bearing.
    Full tree-level completeness upgrades this by showing that the DFS
    *does* visit the correct leaf-block, which in turn needs
    `skip_equals_dfs_next` for non-root nodes (deferred to Phase 1c). -/
theorem aabbQueryNGo_leaf_block_complete (t : PbvhTree) (q : BoundingBox)
    (i : Nat) (hi : i < t.internals.size)
    (hleaf : (t.internals[i]!).left.isNone ∧ (t.internals[i]!).right.isNone)
    (hov : aabbOverlapsDec (t.internals[i]!).bounds q = true)
    (j : Nat) (hj : j < (t.internals[i]!).span)
    (l : PbvhLeaf)
    (hl : t.leaves[t.sorted[(t.internals[i]!).offset + j]!]? = some l)
    (halive : l.alive = true)
    (hl_ov : aabbOverlapsDec l.bounds q = true)
    (acc : List EClassId) :
    l.eclass ∈ aabbQueryNGo t q i acc := by
  rw [aabbQueryNGo]
  dsimp only
  split
  · rename_i h; omega
  · rename_i hlt
    set n := t.internals[i]! with hn_def
    set next : Nat :=
      if _ : i < n.skip ∧ n.skip ≤ t.internals.size then n.skip else i + 1
      with hnext_def
    have hnext_gt : next > i := by
      rw [hnext_def]; split <;> rename_i h <;> omega
    have hnext_le : next ≤ t.internals.size := by
      rw [hnext_def]; split <;> rename_i h <;> omega
    have hnext_measure : t.internals.size - next < t.internals.size - i := by omega
    split
    · rename_i hnov
      exact absurd hov (by rw [Bool.not_eq_true] at hnov; rw [hnov]; decide)
    · split
      · rename_i _
        -- Leaf block: fold emits l.eclass, then membership preserved by tail.
        have hemit := aabbQueryN_leaf_fold_emits t q n.offset n.span acc
          j hj l hl halive hl_ov
        exact aabbQueryNGo_preserves_membership t q _ next _ l.eclass rfl hemit
      · rename_i hchild
        -- Contradiction: hleaf says both children are none, but hchild denies it.
        exact absurd (by simp [hleaf.1, hleaf.2]) hchild

/-- Root-level skip monotonicity: the root node returned by `buildSubtree`
    has `root < skip[root] ≤ result.size`. Direct composition of
    `buildSubtree_root`, `buildSubtree_root_lt_size`, and
    `buildSubtree_skip_eq_final_size`. This is the form `aabbQueryN.go`'s
    termination argument consumes at the entry into the root. -/
theorem buildSubtree_root_skip_monotone (leaves : Array PbvhLeaf)
    (sorted : Array LeafId) (internals : Array PbvhInternal) (lo hi : Nat) :
    let res := buildSubtree leaves sorted internals lo hi
    res.2 < res.1[res.2]!.skip ∧ res.1[res.2]!.skip ≤ res.1.size := by
  have hroot := buildSubtree_root_lt_size leaves sorted internals lo hi
  have hskip := buildSubtree_skip_eq_final_size leaves sorted internals lo hi
  dsimp only at hskip ⊢
  refine ⟨?_, ?_⟩
  · rw [hskip]; exact hroot
  · rw [hskip]; exact Nat.le_refl _

end PbvhTree
