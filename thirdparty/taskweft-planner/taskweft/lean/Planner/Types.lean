/-!
# RECTGTN: Relationship-Enabled Capability-Temporal Goal-Task-Network
## Storage Layer: ECS-inspired Flat Hash Tables (Equality Saturation)

Rat → Int for provability without Mathlib.Data.Rat.Defs.
-/

abbrev Entity := String
abbrev ENodeID := Nat
abbrev EClassID := Nat
abbrev StateVarID := Nat

inductive RelationType where
  | OWNS
  | CONTROLS
  | DELEGATED_TO
  | HAS_CAPABILITY
  | IS_MEMBER_OF
  | SUPERVISOR_OF
  | PARTNER_OF
  | IS_A
  deriving DecidableEq, Repr

inductive RelationExpr where
  | base : RelationType → RelationExpr
  | union : RelationExpr → RelationExpr → RelationExpr
  | intersection : RelationExpr → RelationExpr → RelationExpr
  | difference : RelationExpr → RelationExpr → RelationExpr
  | tupleToUserset : RelationType → RelationExpr → RelationExpr
  deriving DecidableEq, Repr

structure Relationship where
  subject : Entity
  relation : RelationType
  object : Entity
  deriving DecidableEq, Repr

abbrev PlanID := Nat

inductive NodeStatus
  | open
  | closed
  | na
  | new
  | old
  deriving DecidableEq, Repr

structure ActionModel where
  success_prob : Nat   -- probability as a percentage: 0–100
  cost         : Int
  deriving DecidableEq, Repr

structure StateVar where
  id  : StateVarID
  val : Int
  deriving DecidableEq, Repr

structure TimelineEntry where
  action_id  : Nat
  start_time : Int
  end_time   : Int
  deriving DecidableEq, Repr

inductive PlanElement
  | action  : String → List Nat → PlanElement
  | command : String → List Nat → PlanElement
  deriving DecidableEq, Repr

inductive RECTGTNNode
  | task : String → List Nat → RECTGTNNode
  | goal_geq : StateVarID → Int → RECTGTNNode
  | verify_goal : StateVarID → Int → RECTGTNNode
  deriving DecidableEq, Repr

structure EClass where
  parent : EClassID
  nodes  : List ENodeID
  deriving DecidableEq, Repr

structure PlanState where
  executable        : List PlanID
  metadata          : List (PlanID × Int × Int)
  failed            : Option PlanID
  paused_at         : Option PlanID
  prev_tree         : Option Nat
  current_time      : Int
  vars              : List StateVar
  history_timeline  : List TimelineEntry
  current_blacklist : List PlanElement
  next_node_id      : Nat
  e_classes         : Array EClass
  deriving DecidableEq, Repr

inductive TemporalConstraint
  | after  : PlanID → PlanID → TemporalConstraint
  | before : PlanID → PlanID → TemporalConstraint
  | between : PlanID → PlanID → PlanID → TemporalConstraint
  | within : PlanID → Int → TemporalConstraint
  deriving DecidableEq, Repr

inductive PlanTree
  | empty : PlanTree
  | leaf : PlanID → PlanTree
  | node : String → List PlanTree → PlanTree
  | temporal : TemporalConstraint → PlanTree → PlanTree → PlanTree

structure SolutionNode where
  node_id : Nat
  content : RECTGTNNode
  status : NodeStatus
  tag : String
  shadow_state : PlanState
  tried_methods_idx : Nat
  deriving DecidableEq, Repr

structure SolutionTree where
  nodes : List SolutionNode
  edges : List (Nat × Nat)
  is_tree : Prop

def pruneNode (tree : SolutionTree) (target_id : Nat) : SolutionTree :=
  let remaining_nodes := tree.nodes.filter (fun n => n.node_id != target_id)
  let remaining_edges := tree.edges.filter (fun e => e.1 != target_id ∧ e.2 != target_id)
  { tree with
    nodes := remaining_nodes,
    edges := remaining_edges
  }

/-- Allocate a fresh node ID, returning the updated state and the new ID. -/
def allocNodeId (st : PlanState) : PlanState × Nat :=
  ({ st with next_node_id := st.next_node_id + 1 }, st.next_node_id)

/-- A freshly allocated node ID is strictly below the new counter value.
    Ensures unique IDs are issued in increasing order. -/
theorem idMonotonicity (st : PlanState) :
    (allocNodeId st).2 < (allocNodeId st).1.next_node_id := by
  simp [allocNodeId]

theorem pruningDecreasesSize (tree : SolutionTree) (target : Nat) :
  (pruneNode tree target).nodes.length ≤ tree.nodes.length := by
  unfold pruneNode; simp [List.length_filter_le]

/-- Extend the blacklist with a new element. -/
def addToBlacklist (st : PlanState) (e : PlanElement) : PlanState :=
  { st with current_blacklist := e :: st.current_blacklist }

/-- All previously blacklisted elements survive when the blacklist is extended. -/
theorem blacklistPersistence (st : PlanState) (e new_e : PlanElement) :
    e ∈ st.current_blacklist → e ∈ (addToBlacklist st new_e).current_blacklist :=
  fun h => List.mem_cons.mpr (Or.inr h)
