import Planner.Types
import Planner.UnifiedGTN

/-!
# IPyHOP Example: Blocks World Formalization
Migrated from PlotCoverParcel.Planner.BlocksWorld — Mathlib-free.
-/

abbrev Block := Nat

inductive BlocksVar
  | pos   : Block → BlocksVar
  | clear : Block → BlocksVar
  | hand  : BlocksVar
  deriving DecidableEq

def BlocksVar.to_id : BlocksVar → Nat
  | .pos b   => 2 * b + 1
  | .clear b => 2 * b + 2
  | .hand    => 0

inductive Position
  | table
  | hand
  | on_block : Block → Position
  deriving DecidableEq

/-- Minimal GTN state for blocks world actions. -/
structure GTNState where
  variables : List StateVar
  executable_trace : List PlanElement
  deriving DecidableEq, Repr

def actionPickup (st : GTNState) (b : Block) : Option GTNState :=
  let pos_b   := st.variables.find? (·.id == (BlocksVar.pos b).to_id)
  let clear_b := st.variables.find? (·.id == (BlocksVar.clear b).to_id)
  let hand    := st.variables.find? (·.id == BlocksVar.hand.to_id)
  if pos_b == some ⟨(BlocksVar.pos b).to_id, 0⟩ ∧
     clear_b == some ⟨(BlocksVar.clear b).to_id, 1⟩ ∧
     hand == some ⟨BlocksVar.hand.to_id, 0⟩
  then
    let new_vars := [
      StateVar.mk (BlocksVar.pos b).to_id 1,
      StateVar.mk (BlocksVar.clear b).to_id 0,
      StateVar.mk BlocksVar.hand.to_id (↑b + 1)
    ]
    some { st with variables := new_vars }
  else none

theorem pickupChangesHandState (st : GTNState) (b : Block) (st' : GTNState) :
  actionPickup st b = some st' →
  st'.variables.find? (·.id == BlocksVar.hand.to_id) ≠ some ⟨BlocksVar.hand.to_id, 0⟩ := by
  intro h
  unfold actionPickup at h
  simp only at h
  split at h
  · simp at h; subst h; simp [List.find?, BlocksVar.to_id]; omega
  · simp at h

/-- Check whether a GTN node is satisfied by the current state.
    Task nodes are never self-satisfied; goal/verify nodes check the state variable. -/
def is_node_satisfied (st : GTNState) (n : RECTGTNNode) : Bool :=
  match n with
  | .goal_geq var_id threshold =>
    match st.variables.find? (·.id == var_id) with
    | some sv => decide (threshold ≤ sv.val)
    | none    => false
  | .verify_goal var_id val =>
    match st.variables.find? (·.id == var_id) with
    | some sv => decide (sv.val == val)
    | none    => false
  | .task _ _ => false

/-- Task nodes are never satisfied — they must be executed first. -/
theorem task_not_satisfied (st : GTNState) (name : String) (params : List Nat) :
    is_node_satisfied st (.task name params) = false := by
  simp [is_node_satisfied]

/-- A goal_geq node is unsatisfied when the variable is absent from state. -/
theorem is_node_satisfied_missing_var (st : GTNState) (var_id : StateVarID) (thr : Int) :
    st.variables.find? (·.id == var_id) = none →
    is_node_satisfied st (.goal_geq var_id thr) = false := by
  intro h; simp [is_node_satisfied, h]

/-- A goal_geq node is satisfied when the variable meets or exceeds the threshold. -/
theorem is_node_satisfied_goal_met (st : GTNState) (sv : StateVar) (thr : Int)
    (h_find : st.variables.find? (·.id == sv.id) = some sv)
    (h_val  : thr ≤ sv.val) :
    is_node_satisfied st (.goal_geq sv.id thr) = true := by
  simp only [is_node_satisfied, h_find, decide_eq_true_eq]; exact h_val

theorem blacklistedPickupIsInvalid (st : GTNState) (b : Block) :
  (.action "pickup" [b]) ∈ st.executable_trace →
  is_node_satisfied st (.task "pickup" [b]) = false :=
  fun _ => task_not_satisfied st "pickup" [b]
