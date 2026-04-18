import Planner.Types

/-!
# ECTGTN Command Dispatcher
Migrated from PlotCoverParcel.Planner.Commands — standalone (no Manifold deps).
-/

namespace Planner.Commands

def manifoldMergeName : String := "manifold-merge"
def plannerSmokeName  : String := "planner-smoke"

def manifoldMergeCmd (params : List Nat) : PlanElement :=
  .command manifoldMergeName params

def plannerSmokeCmd : PlanElement :=
  .command plannerSmokeName []

/-- Stub dispatcher — logs unknown commands. Real implementations are external. -/
def executeECTGTNCommand : PlanElement → IO Unit
  | .command name _params =>
    match name with
    | other => IO.println s!"[Commands] unhandled command: {other}"
  | .action name _ =>
    IO.println s!"[Commands] action '{name}' is not an executable command"

def executePlan (plan : List PlanElement) : IO Unit :=
  plan.forM executeECTGTNCommand

end Planner.Commands
