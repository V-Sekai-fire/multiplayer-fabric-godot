import Planner.Types

/-!
# IPyHOP-Temporal: Temporal Logic
Migrated from PlotCoverParcel.Planner.Temporal — Mathlib-free.
Rat → Int.
-/

def occursBefore (a b : PlanID) (stn : List PlanID) : Bool :=
  let i := stn.findIdx (· == a)
  let j := stn.findIdx (· == b)
  i < j && j < stn.length && i < stn.length

def temporalConstraintValid (stn : List PlanID) (metas : List (PlanID × Int × Int)) (c : TemporalConstraint) : Bool :=
  match c with
  | .after a b => occursBefore b a stn
  | .before a b => occursBefore a b stn
  | .between a b c_id => occursBefore b a stn && occursBefore a c_id stn
  | .within a t =>
    match metas.find? (·.1 == a) with
    | some m => (decide (a ∈ stn)) && (decide (m.2.2 ≤ t))
    | none   => false

def allConstraintsSatisfied (stn : List PlanID) (metas : List (PlanID × Int × Int)) (cs : List TemporalConstraint) : Bool :=
  cs.all (fun c => temporalConstraintValid stn metas c)

def IsConsistent (stn : List PlanID) (metas : List (PlanID × Int × Int)) (cs : List TemporalConstraint) : Prop :=
  ∀ c ∈ cs, temporalConstraintValid stn metas c = true

theorem allConstraintsSatisfiedIffConsistent (stn : List PlanID) (metas : List (PlanID × Int × Int)) (cs : List TemporalConstraint) :
    allConstraintsSatisfied stn metas cs = true ↔ IsConsistent stn metas cs := by
  unfold allConstraintsSatisfied IsConsistent
  rw [List.all_eq_true]
