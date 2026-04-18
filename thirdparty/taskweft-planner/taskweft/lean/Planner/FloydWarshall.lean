/-!
# Floyd-Warshall: All-Pairs Shortest Path + Negative Cycle Detection
Migrated from PlotCoverParcel.Planner.FloydWarshall — Mathlib-free.
-/

namespace FloydWarshall

structure Result where
  dist : Nat → Nat → Int
  has_negative_cycle : Bool
  negative_cycle_nodes : List (Nat × Nat)

def fwStep (k : Nat) (d : Nat → Nat → Int) : Nat → Nat → Int :=
  fun i j => min (d i j) (d i k + d k j)

def run (n : Nat) (g : Nat → Nat → Int) : Result :=
  let d := (List.range n).foldl (fun acc k => fwStep k acc) g
  let hasCycle := (List.range n).any (fun i => decide (d i i < 0))
  let cycleNodes := ((List.range n).filter (fun i => decide (d i i < 0))).map (fun i => (i, i))
  { dist := d, has_negative_cycle := hasCycle, negative_cycle_nodes := cycleNodes }

end FloydWarshall

/-- The negative-cycle flag is set iff there exists an index in [0,n) whose
    diagonal distance is negative after the full relaxation. Both sides of the
    iff reduce to the same `List.any` call, so the proof is definitional. -/
theorem negCycleIff (n : Nat) (g : Nat → Nat → Int) :
    (FloydWarshall.run n g).has_negative_cycle = true ↔
    ∃ i ∈ List.range n, (FloydWarshall.run n g).dist i i < 0 := by
  constructor
  · intro h
    simp only [FloydWarshall.run, List.any_eq_true, decide_eq_true_eq] at h
    obtain ⟨i, hi, hd⟩ := h
    exact ⟨i, hi, hd⟩
  · rintro ⟨i, hi, hd⟩
    simp only [FloydWarshall.run, List.any_eq_true, decide_eq_true_eq]
    exact ⟨i, hi, hd⟩

/-- Every pair in `negative_cycle_nodes` has a negative diagonal in `dist`.
    Pairs are of the form (i, i) with dist i i < 0 by construction. -/
theorem cycleNodesSound (n : Nat) (g : Nat → Nat → Int) :
    ∀ p ∈ (FloydWarshall.run n g).negative_cycle_nodes,
      (FloydWarshall.run n g).dist p.1 p.2 < 0 := by
  intro ⟨i, j⟩ h
  simp only [FloydWarshall.run, List.mem_map, List.mem_filter,
             List.mem_range, decide_eq_true_eq] at h
  obtain ⟨k, ⟨_, hk⟩, heq⟩ := h
  obtain ⟨rfl, rfl⟩ := Prod.mk.inj heq
  exact hk

theorem testNegativeCycleDetected :
  (FloydWarshall.run 1 (fun _ _ => -1)).has_negative_cycle = true := by
  decide

theorem testNegativeCycleNodesCaptured :
  (FloydWarshall.run 1 (fun _ _ => -1)).negative_cycle_nodes = [(0, 0)] := by
  decide

/-- One relaxation step never increases any distance: result is ≤ the direct edge. -/
theorem fwStep_le_direct (k : Nat) (d : Nat → Nat → Int) (i j : Nat) :
    FloydWarshall.fwStep k d i j ≤ d i j := by
  simp only [FloydWarshall.fwStep]; omega

/-- After one step, the two-hop path through k bounds the stored distance. -/
theorem fwStep_le_two_hop (k : Nat) (d : Nat → Nat → Int) (i j : Nat) :
    FloydWarshall.fwStep k d i j ≤ d i k + d k j := by
  simp only [FloydWarshall.fwStep]; omega

theorem foldl_fwStep_le (ks : List Nat) (g : Nat → Nat → Int) (i j : Nat) :
    (ks.foldl (fun acc k => FloydWarshall.fwStep k acc) g) i j ≤ g i j := by
  induction ks generalizing g with
  | nil  => simp
  | cons k ks ih =>
    simp only [List.foldl_cons]
    calc (ks.foldl (fun acc k => FloydWarshall.fwStep k acc) (FloydWarshall.fwStep k g)) i j
        ≤ (FloydWarshall.fwStep k g) i j := ih _
      _ ≤ g i j := fwStep_le_direct k g i j

/-- Full relaxation only decreases distances: every entry ≤ the original edge.
    Monotonicity invariant: Floyd-Warshall finds shorter paths, never longer. -/
theorem run_le_direct (n : Nat) (g : Nat → Nat → Int) (i j : Nat) :
    (FloydWarshall.run n g).dist i j ≤ g i j := by
  simp only [FloydWarshall.run]
  exact foldl_fwStep_le (List.range n) g i j
