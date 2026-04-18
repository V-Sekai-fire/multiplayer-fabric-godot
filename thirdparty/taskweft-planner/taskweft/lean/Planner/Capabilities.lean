import Planner.Types

/-!
# IPyHOP-Temporal: Transitive Capability Engine + ReBAC
Migrated from PlotCoverParcel.Planner.Capabilities — Mathlib-free.
-/

/-- Transitive capability check with fuel-bounded IS_MEMBER_OF chains. -/
def hasCapability (graph : List Relationship) (subj : Entity) (rel : RelationType) (obj : Entity) (fuel : Nat) : Bool :=
  match fuel with
  | 0 => false
  | n + 1 =>
      graph.any (fun r => r == ⟨subj, rel, obj⟩) ||
      graph.any (fun r =>
        r.subject == subj && r.relation == RelationType.IS_MEMBER_OF && hasCapability graph r.object rel obj n
      ) ||
      graph.any (fun r =>
        r.object == subj && r.relation == RelationType.DELEGATED_TO && r.subject == obj && rel == RelationType.CONTROLS
      )

structure CapabilityState where
  graph : List Relationship
  current_time : Int

def hasCapabilityString (state : CapabilityState) (subj : Entity) (action : String) (obj : Entity) (fuel : Nat := 3) : Bool :=
  match action with
  | "own"        => hasCapability state.graph subj RelationType.OWNS obj fuel
  | "control"    => hasCapability state.graph subj RelationType.CONTROLS obj fuel
  | "delegate"   => hasCapability state.graph subj RelationType.DELEGATED_TO obj fuel
  | "capability" => hasCapability state.graph subj RelationType.HAS_CAPABILITY obj fuel
  | "member"     => hasCapability state.graph subj RelationType.IS_MEMBER_OF obj fuel
  | "supervisor" => hasCapability state.graph subj RelationType.SUPERVISOR_OF obj fuel
  | "partner"    => hasCapability state.graph subj RelationType.PARTNER_OF obj fuel
  | "be"         => hasCapability state.graph subj RelationType.IS_A obj fuel
  | _            => false

-- =====================================================================
-- ReBAC: Computed Relation Expressions
-- =====================================================================

structure ReBACState extends CapabilityState where
  definitions : List (String × RelationExpr)

def checkRelationExpr (graph : List Relationship) (subj : Entity)
    (expr : RelationExpr) (obj : Entity) (fuel : Nat) : Bool :=
  match fuel with
  | 0 => false
  | n + 1 =>
    match expr with
    | .base rel => hasCapability graph subj rel obj n
    | .union a b =>
        checkRelationExpr graph subj a obj n ||
        checkRelationExpr graph subj b obj n
    | .intersection a b =>
        checkRelationExpr graph subj a obj n &&
        checkRelationExpr graph subj b obj n
    | .difference a b =>
        checkRelationExpr graph subj a obj n &&
        !(checkRelationExpr graph subj b obj n)
    | .tupleToUserset pivotRel inner =>
        graph.any (fun r =>
          r.subject == subj && r.relation == pivotRel &&
          checkRelationExpr graph r.object inner obj n)

def expand (graph : List Relationship) (rel : RelationType)
    (obj : Entity) (fuel : Nat) : List Entity :=
  let direct := graph.filterMap (fun r =>
    if r.relation == rel && r.object == obj then some r.subject else none)
  let inherited := graph.filterMap (fun r =>
    if r.relation == RelationType.IS_MEMBER_OF &&
       hasCapability graph r.object rel obj fuel
    then some r.subject else none)
  (direct ++ inherited).eraseDups

def hasCapabilityReBAC (state : ReBACState) (subj : Entity)
    (action : String) (obj : Entity) (fuel : Nat := 3) : Bool :=
  match state.definitions.find? (fun d => d.1 == action) with
  | some (_, expr) => checkRelationExpr state.graph subj expr obj fuel
  | none => hasCapabilityString state.toCapabilityState subj action obj fuel

-- =====================================================================
-- Axioms & Theorems
-- =====================================================================

def OwnershipImpliesControlAxiom (graph : List Relationship) : Prop :=
  ∀ (subj obj : Entity),
    graph.any (fun r => r == ⟨subj, RelationType.OWNS, obj⟩) = true →
    graph.any (fun r => r == ⟨subj, RelationType.CONTROLS, obj⟩) = true

theorem ownershipImpliesControl (graph : List Relationship) (subj obj : Entity) (fuel : Nat) :
  fuel > 0 →
  OwnershipImpliesControlAxiom graph →
  graph.any (fun r => r == ⟨subj, RelationType.OWNS, obj⟩) = true →
  hasCapability graph subj RelationType.CONTROLS obj fuel = true := by
  intro h_fuel h_axiom h_owns
  match fuel with
  | n + 1 =>
    unfold hasCapability
    have h_controls : graph.any (fun r => r == ⟨subj, RelationType.CONTROLS, obj⟩) = true :=
      h_axiom subj obj h_owns
    simp [h_controls]

theorem memberInheritsCapability (graph : List Relationship) (subj group obj : Entity) (rel : RelationType) (fuel : Nat) :
  graph.any (fun r => r == ⟨subj, RelationType.IS_MEMBER_OF, group⟩) = true →
  hasCapability graph group rel obj fuel = true →
  hasCapability graph subj rel obj (fuel + 1) = true := by
  intro h_mem h_cap
  unfold hasCapability
  have h_middle : graph.any (fun r => r.subject == subj && r.relation == RelationType.IS_MEMBER_OF && hasCapability graph r.object rel obj fuel) = true := by
    obtain ⟨r, h_r_in, h_r_beq⟩ := List.any_eq_true.mp h_mem
    apply List.any_eq_true.mpr
    have h_r_eq : r = ⟨subj, RelationType.IS_MEMBER_OF, group⟩ := eq_of_beq h_r_beq
    subst h_r_eq
    exact ⟨⟨subj, RelationType.IS_MEMBER_OF, group⟩, h_r_in, by simp [h_cap]⟩
  simp [h_middle]

-- =====================================================================
-- ReBAC Theorems
-- =====================================================================

theorem unionMonotonicity (graph : List Relationship) (subj obj : Entity)
    (a b : RelationExpr) (n : Nat) :
  checkRelationExpr graph subj a obj n = true →
  checkRelationExpr graph subj (.union a b) obj (n + 1) = true := by
  intro h_a
  unfold checkRelationExpr
  simp [h_a]

theorem intersectionSubsetLeft (graph : List Relationship) (subj obj : Entity)
    (a b : RelationExpr) (n : Nat) :
  checkRelationExpr graph subj (.intersection a b) obj (n + 1) = true →
  checkRelationExpr graph subj a obj n = true := by
  intro h_inter
  unfold checkRelationExpr at h_inter
  simp [Bool.and_eq_true] at h_inter
  exact h_inter.1

theorem tupleToUsersetGeneralizesMembership (graph : List Relationship)
    (subj group obj : Entity) (rel : RelationType) (n : Nat) :
  graph.any (fun r => r == ⟨subj, RelationType.IS_MEMBER_OF, group⟩) = true →
  hasCapability graph group rel obj n = true →
  checkRelationExpr graph subj
    (.tupleToUserset .IS_MEMBER_OF (.base rel)) obj (n + 2) = true := by
  intro h_mem h_cap
  unfold checkRelationExpr
  apply List.any_eq_true.mpr
  obtain ⟨r, h_r_in, h_r_beq⟩ := List.any_eq_true.mp h_mem
  have h_r_eq : r = ⟨subj, RelationType.IS_MEMBER_OF, group⟩ := eq_of_beq h_r_beq
  subst h_r_eq
  exact ⟨⟨subj, RelationType.IS_MEMBER_OF, group⟩, h_r_in, by simp [checkRelationExpr, h_cap]⟩

/-- `expand` returns exactly those entities for which `hasCapability` holds
    at one level of fuel: membership in the direct or inherited list implies
    the corresponding `hasCapability` branch fires. -/
theorem expandSoundness (graph : List Relationship) (rel : RelationType)
    (obj : Entity) (fuel : Nat) (e : Entity) :
    e ∈ expand graph rel obj fuel →
    hasCapability graph e rel obj (fuel + 1) = true := by
  intro h
  simp only [expand, List.mem_eraseDups, List.mem_append, List.mem_filterMap] at h
  rcases h with ⟨r, hr_in, hr_eq⟩ | ⟨r, hr_in, hr_eq⟩
  · -- direct: r.relation = rel, r.object = obj ⟹ first any-clause
    have hcond : (r.relation == rel && r.object == obj) = true := by
      cases h : (r.relation == rel && r.object == obj)
      · simp [h] at hr_eq
      · rfl
    simp [hcond] at hr_eq          -- hr_eq : r.subject = e
    simp only [Bool.and_eq_true] at hcond
    obtain ⟨hrel, hobj⟩ := hcond
    unfold hasCapability
    have step : graph.any (fun r => r == ⟨e, rel, obj⟩) = true := by
      apply List.any_eq_true.mpr
      refine ⟨r, hr_in, ?_⟩
      simp only [beq_iff_eq]; cases r; simp_all [eq_of_beq]
    simp [step]
  · -- inherited: r.relation = IS_MEMBER_OF, hasCapability r.object ⟹ second any-clause
    have hcond : (r.relation == RelationType.IS_MEMBER_OF &&
        hasCapability graph r.object rel obj fuel) = true := by
      cases h : (r.relation == RelationType.IS_MEMBER_OF &&
          hasCapability graph r.object rel obj fuel)
      · simp [h] at hr_eq
      · rfl
    simp [hcond] at hr_eq          -- hr_eq : r.subject = e
    simp only [Bool.and_eq_true] at hcond
    obtain ⟨hmem, hcap⟩ := hcond
    unfold hasCapability
    have step : graph.any (fun r =>
        r.subject == e && r.relation == RelationType.IS_MEMBER_OF &&
        hasCapability graph r.object rel obj fuel) = true := by
      apply List.any_eq_true.mpr
      refine ⟨r, hr_in, ?_⟩
      simp only [Bool.and_eq_true]
      exact ⟨⟨by simp [hr_eq], hmem⟩, hcap⟩
    simp [step]
