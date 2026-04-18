"""Homoiconic RECTGTN planner: plan, simulate, replan via JSON-LD.

Input and output share the same structure.  A plan IS a domain where
tasks are the resolved action sequence and variables reflect final
state.  The output can be fed back as input for replan, simulate,
or further composition.
"""

from typing import Any
import json

from ._common import (
    _add_paths, _remove_paths, _apply_problem, _build_state,
    _plan_to_json, _serialize_state,
    PLAN_DIR, EXAMPLES,
)

_PRESETS = {
    "simple_travel", "blocks_world", "rescue", "robosub",
    "healthcare", "temporal_travel", "entity_capabilities",
    "job_shop_scheduling", "meta_loader",
}


def _lazy_imports():
    from examples.gltf_interactivity.domain.gltf_domain_interpreter import (
        load_domain, build_domain,
    )
    from ipyhop import IPyHOP
    return load_domain, build_domain, IPyHOP


def handle_taskweft(params: dict[str, Any], **kwargs: Any) -> str:
    mode = params.get("mode", "plan")
    if mode not in ("plan", "simulate", "replan"):
        return json.dumps({"error": "mode must be 'plan', 'simulate', or 'replan'"})

    added = _add_paths(PLAN_DIR, EXAMPLES)
    try:
        if mode == "plan":
            return _do_plan(params)
        elif mode == "simulate":
            return _do_simulate(params)
        elif mode == "replan":
            return _do_replan(params)
    except Exception as exc:
        return json.dumps({"error": str(exc)})
    finally:
        _remove_paths(added)


# ── Plan ────────────────────────────────────────────────────────────

def _do_plan(params: dict) -> str:
    load_domain, build_domain, IPyHOP = _lazy_imports()

    domain_def = _load_domain_def(params)
    if isinstance(domain_def, str):
        return domain_def  # error JSON

    actions, methods, init_state, task_list, entity_caps = build_domain(domain_def)

    if params.get("tasks"):
        task_list = [tuple(t) if isinstance(t, list) else t
                     for t in params["tasks"]]

    planner = IPyHOP(methods, actions, entity_capabilities=entity_caps)
    plan = planner.plan(init_state, task_list, verbose=0)

    plan_jsonld = _plan_to_jsonld(domain_def, plan or [], planner.state)

    return json.dumps({
        "mode": "plan",
        "plan": _plan_to_json(plan or []),
        "steps": len(plan or []),
        "iterations": planner.iterations,
        "plan_jsonld": plan_jsonld,
        "state": _serialize_state(planner.state),
    }, ensure_ascii=False)


# ── Simulate ────────────────────────────────────────────────────────

def _do_simulate(params: dict) -> str:
    load_domain, build_domain, IPyHOP = _lazy_imports()

    # Reconstruct from plan_jsonld or from domain + plan
    plan_jld = params.get("plan_jsonld")
    if not plan_jld:
        return json.dumps({"error": "simulate requires plan_jsonld from a previous plan call"})

    domain_def = _load_domain_def(params, fallback_plan_jsonld=plan_jld)
    if isinstance(domain_def, str):
        return domain_def

    actions, methods, init_state, task_list, entity_caps = build_domain(domain_def)

    # The plan_jsonld tasks are the concrete action sequence
    plan_actions = plan_jld.get("tasks", [])

    # Simulate: apply each action to state, collect transitions
    states = [_serialize_state(init_state)]
    current_state = init_state
    for i, action in enumerate(plan_actions):
        action_name = action[0]
        action_args = action[1:]
        fn = actions.action_dict.get(action_name)
        if fn is None:
            return json.dumps({
                "error": f"unknown action '{action_name}' at step {i}",
                "completed_steps": i,
                "states": states,
            })
        result = fn(current_state, *action_args)
        if result is None:
            return json.dumps({
                "error": f"action '{action_name}' precondition failed at step {i}",
                "fail_step": i,
                "completed_steps": i,
                "states": states,
                "state_at_failure": _serialize_state(current_state),
            })
        current_state = result
        states.append(_serialize_state(current_state))

    return json.dumps({
        "mode": "simulate",
        "steps": len(plan_actions),
        "completed_steps": len(plan_actions),
        "states": states,
        "final_state": states[-1],
    }, ensure_ascii=False)


# ── Replan ──────────────────────────────────────────────────────────

def _do_replan(params: dict) -> str:
    load_domain, build_domain, IPyHOP = _lazy_imports()

    plan_jld = params.get("plan_jsonld")
    if not plan_jld:
        return json.dumps({"error": "replan requires plan_jsonld from a previous plan call"})

    fail_step = params.get("fail_step")
    if fail_step is None:
        return json.dumps({"error": "replan requires fail_step (0-based action index)"})

    # Load the ORIGINAL domain (not the plan — plan has resolved tasks)
    source_name = plan_jld.get("source")
    domain_def = _load_domain_def(params, fallback_preset=source_name)
    if isinstance(domain_def, str):
        return domain_def

    actions, methods, init_state, task_list, entity_caps = build_domain(domain_def)

    # Build planner and run initial plan
    planner = IPyHOP(methods, actions, entity_capabilities=entity_caps)
    original_plan = planner.plan(init_state, task_list, verbose=0)
    if not original_plan:
        return json.dumps({"error": "could not reproduce original plan"})

    # Apply observed state if provided
    observed_state = params.get("state")
    if observed_state:
        replan_state = _build_state(observed_state, name="replan_state")
    else:
        # Simulate up to fail_step to get state at failure
        replan_state = init_state.copy()
        for action in original_plan[:fail_step]:
            fn = actions.action_dict.get(action[0])
            if fn:
                result = fn(replan_state, *action[1:])
                if result is not None:
                    replan_state = result

    # Find the solution tree node corresponding to fail_step
    # The solution tree action nodes are indexed in DFS order
    from ipyhop.graph_utils import dfs_preorder_nodes
    action_nodes = []
    for nid in dfs_preorder_nodes(planner.sol_tree, source=0):
        if planner.sol_tree.nodes[nid]["type"] == "A":
            action_nodes.append(nid)
    if fail_step >= len(action_nodes):
        return json.dumps({"error": f"fail_step {fail_step} out of range (plan has {len(action_nodes)} actions)"})

    fail_node_id = action_nodes[fail_step]

    # Replan from failure
    new_plan = planner.replan(replan_state, fail_node_id, verbose=0)

    plan_jsonld = _plan_to_jsonld(domain_def, new_plan or [], planner.state)

    return json.dumps({
        "mode": "replan",
        "fail_step": fail_step,
        "original_steps": len(original_plan),
        "plan": _plan_to_json(new_plan or []),
        "steps": len(new_plan or []),
        "iterations": planner.iterations,
        "plan_jsonld": plan_jsonld,
        "state": _serialize_state(planner.state),
    }, ensure_ascii=False)


# ── Shared helpers ──────────────────────────────────────────────────

def _load_domain_def(params: dict, fallback_preset: str = None,
                     fallback_plan_jsonld: dict = None) -> dict | str:
    """Load domain definition from params.  Returns dict or error JSON string."""
    load_domain, _, _ = _lazy_imports()
    from pathlib import Path

    # 1. Inline domain takes priority
    if params.get("domain"):
        domain_def = dict(params["domain"])
    # 2. Preset
    elif params.get("preset"):
        preset = params["preset"]
        if preset not in _PRESETS:
            return json.dumps({"error": f"preset must be one of: {', '.join(sorted(_PRESETS))}"})
        domain_def = load_domain(preset)
        if domain_def is None:
            return json.dumps({"error": f"domain file not found: {preset}.jsonld"})
    # 3. Fallback preset (e.g. from plan_jsonld.source)
    elif fallback_preset and fallback_preset in _PRESETS:
        domain_def = load_domain(fallback_preset)
        if domain_def is None:
            return json.dumps({"error": f"domain file not found: {fallback_preset}.jsonld"})
    # 4. Reconstruct from plan_jsonld
    elif fallback_plan_jsonld:
        domain_def = dict(fallback_plan_jsonld)
    else:
        return json.dumps({"error": "provide 'preset', 'domain', or 'plan_jsonld'"})

    # Apply problem overrides
    problem_name = params.get("problem")
    if problem_name:
        problems_dir = Path(__file__).parent.parent / "examples" / "gltf_interactivity" / "problems"
        problem_path = problems_dir / f"{problem_name}.jsonld"
        if problem_path.exists():
            with open(problem_path) as f:
                problem_def = json.load(f)
            _apply_problem(domain_def, problem_def)

    # Apply inline overrides
    if params.get("variables"):
        domain_def["variables"] = params["variables"]
    if params.get("tasks"):
        domain_def["tasks"] = params["tasks"]
    if params.get("methods"):
        domain_def.setdefault("methods", {}).update(params["methods"])

    return domain_def


def _plan_to_jsonld(domain_def: dict, plan: list, final_state) -> dict:
    """Homoiconic output: emit the plan as a JSON-LD domain document."""
    variables = []
    for v in domain_def.get("variables", []):
        name = v["name"]
        final = getattr(final_state, name, {})
        entry = {"name": name}
        if isinstance(final, dict):
            entry["init"] = {str(k): val for k, val in final.items()}
        variables.append(entry)

    tasks = [list(a) for a in plan] if plan else []

    result = {
        "@context": domain_def.get("@context", {}),
        "@type": "domain:Plan",
        "name": f"{domain_def.get('name', 'plan')}_plan",
        "source": domain_def.get("name"),
        "variables": variables,
        "actions": domain_def.get("actions", {}),
        "methods": domain_def.get("methods", {}),
        "tasks": tasks,
    }

    for key in ("capabilities", "enums"):
        if key in domain_def:
            result[key] = domain_def[key]

    return result
