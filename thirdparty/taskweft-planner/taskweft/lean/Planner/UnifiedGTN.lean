import Planner.Types

/-!
# IPyHOP: Saturated Unified GTN Verification
Migrated from PlotCoverParcel.Planner.UnifiedGTN — Mathlib-free.
-/

def nodeLifecycleStep (n : SolutionNode) : SolutionNode :=
  match n.status with
  | .open   => { n with status := .closed, tag := "new" }
  | .closed => n
  | .na     => n
  | .new    => n
  | .old    => n

theorem planConstructionIsMonotonic (trace : List PlanElement) (e : PlanElement) :
    trace.length ≤ (trace ++ [e]).length := by
  simp [List.length_append]

/-- Allocating a node ID is a pure counter increment; the blacklist is untouched. -/
theorem allocNodeId_preserves_blacklist (st : PlanState) :
    (allocNodeId st).1.current_blacklist = st.current_blacklist := by
  simp [allocNodeId]

/-- An open node transitions to closed and receives the tag "new". -/
theorem nodeLifecycleStep_open (n : SolutionNode) (h : n.status = .open) :
    (nodeLifecycleStep n).status = .closed ∧ (nodeLifecycleStep n).tag = "new" := by
  unfold nodeLifecycleStep; simp [h]

/-- Any non-open node is a fixed point of the lifecycle step. -/
theorem nodeLifecycleStep_stable (n : SolutionNode) (h : n.status ≠ .open) :
    nodeLifecycleStep n = n := by
  unfold nodeLifecycleStep
  rcases hs : n.status with _ | _ | _ | _ | _
  · exact absurd hs h
  all_goals rfl

/-- Extract executable actions: nodes tagged "new" with task content become
    PlanElement actions; goal/verify nodes are dropped. -/
def extractPlan (tree : SolutionTree) : List PlanElement :=
  tree.nodes.filterMap fun n =>
    if n.tag == "new" then
      match n.content with
      | .task name params => some (.action name params)
      | _                 => none
    else none

/-- Every element produced by extractPlan comes from a "new"-tagged node. -/
theorem replanOnlyEmitsNew (tree : SolutionTree) :
    ∀ e ∈ extractPlan tree, ∃ n ∈ tree.nodes, n.tag = "new" := by
  intro e he
  simp only [extractPlan, List.mem_filterMap] at he
  obtain ⟨n, hn_mem, hn_res⟩ := he
  refine ⟨n, hn_mem, ?_⟩
  cases htag : (n.tag == "new") with
  | false => simp [htag] at hn_res
  | true  => exact eq_of_beq htag
