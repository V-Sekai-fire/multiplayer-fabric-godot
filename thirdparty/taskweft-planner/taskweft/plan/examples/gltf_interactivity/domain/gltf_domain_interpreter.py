#!/usr/bin/env python
"""Homoiconic loader: JSON-LD domain → IPyHOP RECTGTN elements.

Uses JSON Pointer templates (RFC 6901 + KHR_interactivity {param} syntax):

  "/loc/{person}"          pointer/get or pointer/set with template param
  "{person}"               param reference (input value socket)
  {"op": "add", "a": ...}  math expression

Single primitive — state_op(mode, state, var, key, val) — three modes:

  GET   = pointer/get
  CHECK = pointer/get + comparison + flow/branch
  SET   = pointer/set
"""

import json
import operator
import re
from pathlib import Path
from ipyhop import Actions, Methods, MultiGoal, State

_DOMAINS_DIR = Path(__file__).parent.parent / "domains"

GET, CHECK, SET = "get", "check", "set"

_CMP = {
    "eq": operator.eq, "neq": operator.ne,
    "lt": operator.lt, "le": operator.le,
    "gt": operator.gt, "ge": operator.ge,
    "ieq": operator.eq, "ilt": operator.lt, "ile": operator.le,
    "igt": operator.gt, "ige": operator.ge,
}

_MATH = {
    "add": operator.add, "sub": operator.sub,
    "mul": operator.mul, "div": operator.truediv,
    "rem": operator.mod, "neg": operator.neg, "abs": abs,
    "min": min, "max": max,
    "iadd": operator.add, "isub": operator.sub,
    "imul": operator.mul, "idiv": operator.floordiv,
    "irem": operator.mod, "iabs": abs,
    "and": operator.and_, "or": operator.or_,
    "not": operator.not_, "xor": operator.xor,
}

_TMPL_RE = re.compile(r"\{([^}]+)\}")


def load_domain(name):
    path = _DOMAINS_DIR / f"{name}.jsonld"
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


# ── JSON Pointer template resolution ─────────────────────────────────

def resolve_pointer(pointer, bindings):
    """Resolve a JSON Pointer template "/var/{param}" → (var, key).

    Returns (variable_name, resolved_key) for state access.
    """
    parts = pointer.lstrip("/").split("/")
    resolved = []
    for p in parts:
        m = _TMPL_RE.fullmatch(p)
        if m:
            resolved.append(bindings.get(m.group(1), p))
        else:
            resolved.append(p)
    if len(resolved) == 1:
        return resolved[0], None
    return resolved[0], resolved[1]


def resolve_value(expr, state, bindings, enums):
    """Evaluate a value expression.

    String "{name}" → param deref (spec template syntax)
    String literal  → literal or enum lookup
    Number/bool     → literal
    Dict with "op"  → math expression
    Dict with "pointer" → pointer/get
    Dict with "$"   → param deref (legacy)
    """
    if isinstance(expr, str):
        m = _TMPL_RE.fullmatch(expr)
        if m:
            return bindings.get(m.group(1), expr)
        # Try enum lookup
        if enums:
            for em in enums.values():
                if expr in em:
                    return em[expr]
        return expr
    if isinstance(expr, dict):
        if "$" in expr:
            return bindings.get(expr["$"], expr)
        if "pointer" in expr:
            var, key = resolve_pointer(expr["pointer"], bindings)
            if key is not None:
                return getattr(state, var, {}).get(key)
            return getattr(state, var, None)
        op = expr.get("op")
        if op == "get":
            if "pointer" in expr:
                var, key = resolve_pointer(expr["pointer"], bindings)
                return getattr(state, var, {}).get(key)
            var = expr["var"]
            key = resolve_value(expr["key"], state, bindings, enums)
            return getattr(state, var, {}).get(key)
        fn = _MATH.get(op)
        if fn:
            a = resolve_value(expr["a"], state, bindings, enums)
            if "b" in expr:
                return fn(a, resolve_value(expr["b"], state, bindings, enums))
            return fn(a)
    return expr  # number, bool, null


# ── Single primitive ─────────────────────────────────────────────────

def state_op(mode, state, var, key, val=None, cmp="eq"):
    d = getattr(state, var, {})
    if mode == GET:
        return d.get(key), True
    if mode == CHECK:
        return None, _CMP.get(cmp, operator.eq)(d.get(key), val)
    if mode == SET:
        d[key] = val
        return None, True
    return None, False


# ── build_domain ─────────────────────────────────────────────────────

def build_domain(domain_def):
    actions = Actions()
    methods = Methods()
    enums = domain_def.get("enums", {})

    init_state = State(domain_def.get("name", "domain"))
    for v in domain_def.get("variables", []):
        setattr(init_state, v["name"], dict(v.get("init", {})))

    for name, defn in domain_def.get("actions", {}).items():
        _register_action(actions, name, defn, enums)

    for name, defn in domain_def.get("methods", {}).items():
        methods.declare_task_methods(name, _build_alts(defn, enums))

    for name, defn in domain_def.get("goals", {}).items():
        methods.declare_goal_methods(name, _build_alts(defn, enums))

    for name, defn in domain_def.get("multigoals", {}).items():
        methods.declare_multigoal_methods(defn.get("goal_tag"), _mg(name))

    caps = domain_def.get("capabilities", {})
    if caps.get("actions"):
        actions.declare_action_capabilities(caps["actions"])
    entity_caps = None
    if caps.get("entities"):
        from ipyhop.capabilities import EntityCapabilities
        entity_caps = EntityCapabilities()
        for e, cl in caps["entities"].items():
            entity_caps.assign_capabilities(e, cl)

    task_list = []
    for t in domain_def.get("tasks", []):
        if isinstance(t, dict) and "multigoal" in t:
            mg = MultiGoal(domain_def.get("name", "goal"))
            for vn, goals in t["multigoal"].items():
                setattr(mg, vn, goals)
            task_list.append(mg)
        elif isinstance(t, list):
            task_list.append(tuple(resolve_value(x, init_state, {}, enums) for x in t))

    return actions, methods, init_state, task_list, entity_caps


# ── Compile JSON-LD body to state_op calls ───────────────────────────

def _exec_binds(state, bindings, bind_steps, enums):
    for s in bind_steps:
        if "pointer" in s:
            var, key = resolve_pointer(s["pointer"], bindings)
            val, _ = state_op(GET, state, var, key)
        else:
            var = s["from"][0]
            key = resolve_value(s["from"][1], state, bindings, enums)
            val, _ = state_op(GET, state, var, key)
        bindings[s["name"]] = val


def _exec_body(state, bindings, body, enums):
    for step in body:
        # Check step: pointer or [var, key] syntax
        check_target = step.get("check")
        if check_target is not None:
            if isinstance(check_target, str) and check_target.startswith("/"):
                var, key = resolve_pointer(check_target, bindings)
            else:
                var, key = check_target[0], resolve_value(check_target[1], state, bindings, enums)
            for cmp_name in _CMP:
                if cmp_name in step:
                    expected = resolve_value(step[cmp_name], state, bindings, enums)
                    _, ok = state_op(CHECK, state, var, key, expected, cmp_name)
                    if not ok:
                        return False
                    break
        # Set step: pointer or [var, key] syntax
        set_target = step.get("set")
        if set_target is not None:
            if isinstance(set_target, str) and set_target.startswith("/"):
                var, key = resolve_pointer(set_target, bindings)
            else:
                var, key = set_target[0], resolve_value(set_target[1], state, bindings, enums)
            val = resolve_value(step["value"], state, bindings, enums)
            state_op(SET, state, var, key, val)
    return True


def _register_action(actions, name, defn, enums):
    params = defn.get("params", [])
    bind_steps = defn.get("bind", [])
    body = defn.get("body", [])

    def action_fn(state, *args, _p=params, _bs=bind_steps, _body=body, _e=enums):
        b = dict(zip(_p, args))
        _exec_binds(state, b, _bs, _e)
        if not _exec_body(state, b, _body, _e):
            return None
        return state

    action_fn.__name__ = name
    actions.action_dict[name] = action_fn


def _check_all(state, bindings, checks, enums):
    """Evaluate a list of check conditions.  Returns True iff all pass."""
    for chk in checks:
        if "pointer" in chk:
            var, key = resolve_pointer(chk["pointer"], bindings)
        else:
            var = chk["var"][0]
            key = resolve_value(chk["var"][1], state, bindings, enums)
        for cmp_name in _CMP:
            if cmp_name in chk:
                expected = resolve_value(chk[cmp_name], state, bindings, enums)
                _, ok = state_op(CHECK, state, var, key, expected, cmp_name)
                if not ok:
                    return False
                break
    return True


def _build_alts(defn, enums):
    fns = []

    # ── flow/for scan: deterministic O(n) iteration over variable keys ──
    # Maps to KHR_interactivity flow/for + flow/branch.
    # Scans keys of a variable, evaluates priority-ordered branches per key,
    # returns the first matching subtask.  No search / no backtracking.
    scan = defn.get("scan")
    if scan is not None:
        scan_var = scan["over"]           # variable whose keys to iterate
        branches = scan["branches"]       # priority-ordered [{check, subtasks}]
        done_check = scan.get("done", []) # completion condition
        done_subs = scan.get("done_subtasks", [])
        recurse = scan.get("recurse")     # task name to re-invoke (optional)

        def scan_fn(state, *args, _p=defn.get("params", []),
                    _sv=scan_var, _br=branches, _dc=done_check,
                    _ds=done_subs, _rec=recurse, _e=enums):
            b = dict(zip(_p, args))
            keys = list(getattr(state, _sv, {}).keys())
            # Priority-first ordering (matches mgm_move_blocks):
            # For each branch (priority level), scan ALL keys.
            # Return the first (branch, key) that passes all checks.
            for branch in _br:
                for k in keys:
                    bb = dict(b)
                    bb["_key"] = k
                    _exec_binds(state, bb, branch.get("bind", []), _e)
                    if _check_all(state, bb, branch.get("check", []), _e):
                        subs = [tuple(resolve_value(t, state, bb, _e)
                                      for t in s)
                                for s in branch.get("subtasks", [])]
                        if _rec:
                            subs.append((_rec,))
                        return subs
            # All branches × keys exhausted → done
            bd = dict(b)
            if _dc:
                if not _check_all(state, bd, _dc, _e):
                    return None
            return [tuple(resolve_value(t, state, bd, _e) for t in s)
                    for s in _ds] if _ds else []

        scan_fn.__name__ = f"tm_{defn.get('name', 'scan')}"
        fns.append(scan_fn)
        return fns

    # ── Standard alternatives ───────────────────────────────────────────
    for alt in defn.get("alternatives", []):
        params = defn["params"]
        bind_steps = alt.get("bind", [])
        checks = alt.get("check", [])
        subs = alt.get("subtasks", [])

        def method_fn(state, *args, _p=params, _bs=bind_steps,
                      _chks=checks, _subs=subs, _e=enums):
            b = dict(zip(_p, args))
            _exec_binds(state, b, _bs, _e)
            if not _check_all(state, b, _chks, _e):
                return None
            if not _subs:
                return []
            return [tuple(resolve_value(t, state, b, _e) for t in s) for s in _subs]

        method_fn.__name__ = f"tm_{alt.get('name', 'alt')}"
        fns.append(method_fn)
    return fns


def _mg(name):
    """Generate multigoal method alternatives — one per goal index.

    Each alternative picks a different unsatisfied goal.  The RECTGTN
    planner backtracks through them to find a viable ordering, just as
    it backtracks through task-method alternatives.  No domain-specific
    heuristic is needed; the search handles it.
    """
    fns = []
    for idx in range(_MG_MAX_ALTS):
        def mg_method(state, multigoal, _idx=idx):
            unsatisfied = []
            for var in vars(multigoal):
                if var.startswith("_") or var == "goal_tag":
                    continue
                goals = getattr(multigoal, var)
                if isinstance(goals, dict):
                    for arg, desired in goals.items():
                        val, _ = state_op(GET, state, var, arg)
                        if val != desired:
                            unsatisfied.append((var, arg, desired))
            if not unsatisfied:
                return []           # all goals satisfied
            if _idx >= len(unsatisfied):
                return None          # no more alternatives
            var, arg, desired = unsatisfied[_idx]
            return [(var, arg, desired), multigoal]
        mg_method.__name__ = f"mgm_{name}_{idx}"
        fns.append(mg_method)
    return fns


_MG_MAX_ALTS = 20  # max simultaneous unsatisfied goals
