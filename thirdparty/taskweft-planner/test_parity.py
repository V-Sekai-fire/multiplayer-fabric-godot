#!/usr/bin/env python3
"""C++ / Python plan parity test.

For every problem in the gltf_interactivity/problems/ directory:
1. Run the Python gltf_domain_interpreter (same logic as C++ loader).
2. Run the C++ taskweft CLI.
3. Compare plan length and action sequence.

Exit 0 if all match, 1 if any differ.
"""
import json
import pathlib
import subprocess
import sys

REPO_ROOT  = pathlib.Path(__file__).parent
EXAMPLES   = REPO_ROOT / "taskweft/plan/examples/gltf_interactivity"
DOMAINS    = EXAMPLES / "domains"
PROBLEMS   = EXAMPLES / "problems"
IPYHOP_DIR = REPO_ROOT / "taskweft/plan"
CLI        = REPO_ROOT / "../../thirdparty/taskweft/cli/.build_native/taskweft"


# ── Minimal domain+problem merger (mirrors load_file_pair in tw_loader.hpp) ──

def merge_domain_problem(dom_def: dict, prob_def: dict) -> dict:
    """Return a merged domain dict ready for build_domain()."""
    merged = json.loads(json.dumps(dom_def))  # deep copy

    # Override variables from problem.
    if "variables" in prob_def:
        merged["variables"] = prob_def["variables"]

    # Merge methods from problem (problem definitions override domain ones).
    for name, defn in prob_def.get("methods", {}).items():
        merged.setdefault("methods", {})[name] = defn

    # Merge goal methods (dict form).
    for name, defn in prob_def.get("goals", {}).items() if isinstance(prob_def.get("goals"), dict) else []:
        merged.setdefault("goals", {})[name] = defn

    # Override task list from problem.
    if "tasks" in prob_def:
        merged["tasks"] = prob_def["tasks"]

    return merged


def run_python(dom_def: dict, prob_def: dict) -> list:
    """Run the Python planner and return the plan as a list of tuples."""
    import importlib.util, sys as _sys
    # Ensure ipyhop is importable from local source.
    if str(IPYHOP_DIR) not in _sys.path:
        _sys.path.insert(0, str(IPYHOP_DIR))

    from ipyhop import IPyHOP
    from taskweft.plan.examples.gltf_interactivity.domain.gltf_domain_interpreter import (
        build_domain,
    )

    merged = merge_domain_problem(dom_def, prob_def)

    # Problem-level "goals" array → individual (var, key, desired) goal tuples,
    # which IPyHOP processes by calling goal_methods[var](state, key, desired).
    # Already-satisfied bindings are skipped by the planner automatically.
    goals_array = prob_def.get("goals") if isinstance(prob_def.get("goals"), list) else None
    if goals_array:
        goal_tasks = []
        for entry in goals_array:
            ptr = entry.get("pointer", "")
            desired = entry.get("eq")
            parts = ptr.lstrip("/").split("/")
            if len(parts) >= 2:
                goal_tasks.append([parts[0], parts[1], desired])
        if goal_tasks:
            merged["tasks"] = goal_tasks

    actions, methods, state, task_list, entity_caps = build_domain(merged)
    # Pass entity_caps so the planner enforces capability-based action filtering
    # (mirrors IPyHOP-temporal EntityCapabilities / ReBAC filtering).
    planner = IPyHOP(methods, actions, entity_capabilities=entity_caps)
    return planner.plan(state, task_list, verbose=0)


def run_cpp(domain_path: pathlib.Path, problem_path: pathlib.Path) -> list:
    """Run the C++ CLI and return the plan as a list of tuples."""
    if not CLI.exists():
        raise FileNotFoundError(f"CLI not found: {CLI}")
    cmd = [str(CLI), "--problem", str(domain_path), str(problem_path)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not result.stdout.strip().startswith("["):
        raise RuntimeError(result.stdout.strip() + result.stderr.strip())
    return [tuple(x) for x in json.loads(result.stdout.strip())]


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    passed = 0
    failed = 0
    errors = []

    for pfile in sorted(PROBLEMS.glob("*.jsonld")):
        name = pfile.stem
        prob_def = json.loads(pfile.read_text())
        src = prob_def.get("source", "")
        domain_path = DOMAINS / f"{src or name}.jsonld"
        if not domain_path.exists():
            print(f"SKIP  {name} (no domain)")
            continue

        dom_def = json.loads(domain_path.read_text())

        try:
            py_plan = run_python(dom_def, prob_def)
        except Exception as exc:
            print(f"FAIL  {name}: Python error — {exc}")
            failed += 1
            errors.append(name)
            continue

        try:
            cpp_plan = run_cpp(domain_path, pfile)
        except Exception as exc:
            print(f"FAIL  {name}: C++ error — {exc}")
            failed += 1
            errors.append(name)
            continue

        py_actions  = [t[0] for t in py_plan]
        cpp_actions = [t[0] for t in cpp_plan]

        if len(py_plan) != len(cpp_plan):
            print(f"FAIL  {name}: length mismatch — Python {len(py_plan)} vs C++ {len(cpp_plan)}")
            print(f"       Python:  {py_actions}")
            print(f"       C++:     {cpp_actions}")
            failed += 1
            errors.append(name)
        elif py_actions != cpp_actions:
            print(f"FAIL  {name}: action mismatch")
            print(f"       Python:  {py_actions}")
            print(f"       C++:     {cpp_actions}")
            failed += 1
            errors.append(name)
        else:
            print(f"PASS  {name}: {len(py_plan)} steps — {py_actions}")
            passed += 1

    print()
    print(f"{'='*60}")
    print(f"Parity: {passed} passed, {failed} failed")
    if errors:
        print(f"Failed: {', '.join(errors)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
