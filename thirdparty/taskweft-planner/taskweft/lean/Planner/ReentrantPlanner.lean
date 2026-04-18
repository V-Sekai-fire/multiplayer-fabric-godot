import Planner.Types

/-!
# Reentrant Planner: Recovery State
Migrated from PlotCoverParcel.Planner.ReentrantPlanner — Mathlib-free.
Set Nat → List Nat (avoids Mathlib.Data.Set.Basic).
-/

structure PlanSolutionTree where
  complete_tree : PlanTree
  failure_node : Option Nat
  recovery_point : Option Nat
  verified : List Nat

/-- Mark a node ID as verified (append to the verified prefix). -/
def markVerified (st : PlanSolutionTree) (node_id : Nat) : PlanSolutionTree :=
  { st with verified := st.verified ++ [node_id] }

/-- Replace the plan tree after a failure, clearing the failure marker. -/
def replan (st : PlanSolutionTree) (new_tree : PlanTree) : PlanSolutionTree :=
  { st with complete_tree := new_tree, failure_node := none }

/-- The verified prefix grows monotonically: marking a node verified
    never shrinks the prefix.  Guarantees that executed history is preserved. -/
theorem verifiedPrefixConsistent (st : PlanSolutionTree) (n : Nat) :
    st.verified.length ≤ (markVerified st n).verified.length := by
  simp [markVerified, List.length_append]

/-- Replanning clears the failure marker so the planner can resume cleanly. -/
theorem replanClearsFailure (st : PlanSolutionTree) (new_tree : PlanTree) :
    (replan st new_tree).failure_node = none := rfl

/-- Replanning does not touch the verified prefix:
    already-executed nodes remain recorded. -/
theorem replanPreservesVerified (st : PlanSolutionTree) (new_tree : PlanTree) :
    (replan st new_tree).verified = st.verified := rfl
