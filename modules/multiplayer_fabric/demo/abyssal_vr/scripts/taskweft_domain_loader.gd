## Loads JSON-LD planning domain definitions into TaskweftDomain + TaskweftState.
##
## Usage:
##   var result = TaskweftDomainLoader.load_file("res://taskweft_domains/simple_travel.jsonld")
##   var domain: TaskweftDomain = result.domain
##   var state:  TaskweftState  = result.state
##   var tasks:  Array          = result.tasks
##   var plan = Taskweft.new().set_domain(domain) ... planner.plan(state, tasks)
##
## Action callables:   fn(state, p0?, p1?, p2?, p3?) -> TaskweftState | null
## Method callables:   fn(state, p0?, p1?, p2?, p3?) -> Array[subtask] | null
class_name TaskweftDomainLoader
extends RefCounted

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func load_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("TaskweftDomainLoader: cannot read " + path)
		return {}
	return load_string(text)


static func load_string(json_text: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("TaskweftDomainLoader: JSON parse error: " + json.get_error_message())
		return {}
	return load_dict(json.data)


static func load_dict(data: Dictionary) -> Dictionary:
	var enums: Dictionary = data.get("enums", {})
	var domain := TaskweftDomain.new()
	var state  := TaskweftState.new()

	# Initialise state variables.
	for var_def in data.get("variables", []):
		var var_name: String = var_def["name"]
		var init = var_def.get("init", {})
		if init is Dictionary:
			for key in init:
				state.set_nested(var_name, key, init[key])
		# Scalar init (rare) stored directly.
		elif init != null:
			state.set_var(var_name, init)

	# Build actions.
	for action_name in data.get("actions", {}):
		var action_def: Dictionary = data["actions"][action_name]
		var param_names: Array = action_def.get("params", [])
		var bind_defs: Array  = action_def.get("bind", [])
		var body: Array       = action_def.get("body", [])
		domain.declare_action(
			action_name,
			_exec_action.bind(param_names, bind_defs, body, enums)
		)

	# Build task methods.
	for task_name in data.get("methods", {}):
		var group: Dictionary = data["methods"][task_name]
		var param_names: Array = group.get("params", [])
		var callables: Array = []
		for alt in group.get("alternatives", []):
			callables.append(_exec_method_alt.bind(param_names, alt, enums))
		domain.declare_task_methods(task_name, callables)

	# Build goal methods (keyed by state variable name).
	for goal_var in data.get("goals", {}):
		var group: Dictionary = data["goals"][goal_var]
		var param_names: Array = group.get("params", [])
		var callables: Array = []
		for alt in group.get("alternatives", []):
			callables.append(_exec_goal_method_alt.bind(param_names, alt, enums))
		domain.declare_goal_methods(goal_var, callables)

	# Build initial task list.
	var tasks: Array = _build_tasks(data.get("tasks", []))

	return {"domain": domain, "state": state, "tasks": tasks, "enums": enums}

# ---------------------------------------------------------------------------
# Action executor — pre-bound as Callable(param_names, bind_defs, body, enums)
# ---------------------------------------------------------------------------

static func _exec_action(
		param_names: Array, bind_defs: Array, body: Array, enums: Dictionary,
		state: TaskweftState,
		p0 = null, p1 = null, p2 = null, p3 = null) -> Variant:
	var params := _build_params(param_names, [p0, p1, p2, p3])

	# Bind steps: read state values into params before executing the body.
	for bind_step in bind_defs:
		var ptr := _parse_pointer(bind_step["pointer"], params)
		if ptr.size() == 2:
			params[bind_step["name"]] = state.get_nested(ptr[0], ptr[1])

	var new_state: TaskweftState = state.copy()

	for step in body:
		if step.has("check"):
			var ptr := _parse_pointer(step["check"], params)
			if ptr.size() != 2:
				return null
			var actual  = new_state.get_nested(ptr[0], ptr[1])
			var op      := _check_op(step)
			var expected = _eval_expr(step[op], params, new_state, enums)
			if not _compare(actual, expected, op):
				return null
		elif step.has("set"):
			var ptr := _parse_pointer(step["set"], params)
			if ptr.size() != 2:
				return null
			var value = _eval_expr(step["value"], params, new_state, enums)
			new_state.set_nested(ptr[0], ptr[1], value)

	return new_state

# ---------------------------------------------------------------------------
# Method alternative executor
# ---------------------------------------------------------------------------

static func _exec_method_alt(
		param_names: Array, alt_def: Dictionary, enums: Dictionary,
		state: TaskweftState,
		p0 = null, p1 = null, p2 = null, p3 = null) -> Variant:
	var params := _build_params(param_names, [p0, p1, p2, p3])

	# Bind steps.
	for bind_step in alt_def.get("bind", []):
		var ptr := _parse_pointer(bind_step["pointer"], params)
		if ptr.size() == 2:
			params[bind_step["name"]] = state.get_nested(ptr[0], ptr[1])

	# Precondition checks.
	for check_step in alt_def.get("check", []):
		var ptr_key := "pointer" if check_step.has("pointer") else "var"
		var raw_ptr = check_step[ptr_key]
		var ptr: Array
		if raw_ptr is String:
			ptr = _parse_pointer(raw_ptr, params)
		elif raw_ptr is Array and raw_ptr.size() == 2:
			ptr = [raw_ptr[0], _resolve_param(raw_ptr[1], params)]
		else:
			return null
		if ptr.size() != 2:
			return null
		var actual  = state.get_nested(ptr[0], ptr[1])
		var op      := _check_op(check_step)
		var expected = _resolve_param(check_step[op], params)
		if not _compare(actual, expected, op):
			return null

	# Build subtasks, substituting params.
	var subtasks: Array = []
	for subtask_def in alt_def.get("subtasks", []):
		var subtask: Array = []
		for elem in subtask_def:
			subtask.append(_resolve_param(elem, params))
		subtasks.append(subtask)

	return subtasks

# ---------------------------------------------------------------------------
# Goal method alternative executor
# signature: fn(state, desired_value) -> Array[subtask] | null
# ---------------------------------------------------------------------------

static func _exec_goal_method_alt(
		param_names: Array, alt_def: Dictionary, enums: Dictionary,
		state: TaskweftState,
		desired = null) -> Variant:
	# Goal methods receive the desired value as the single extra arg.
	var params := {}
	if param_names.size() >= 1:
		params[param_names[0]] = desired

	# Bind and check same as method alt.
	for bind_step in alt_def.get("bind", []):
		var ptr := _parse_pointer(bind_step["pointer"], params)
		if ptr.size() == 2:
			params[bind_step["name"]] = state.get_nested(ptr[0], ptr[1])

	for check_step in alt_def.get("check", []):
		var raw_ptr = check_step.get("pointer", check_step.get("var", null))
		if raw_ptr == null:
			return null
		var ptr: Array
		if raw_ptr is String:
			ptr = _parse_pointer(raw_ptr, params)
		elif raw_ptr is Array and raw_ptr.size() == 2:
			ptr = [raw_ptr[0], _resolve_param(raw_ptr[1], params)]
		else:
			return null
		var actual   = state.get_nested(ptr[0], ptr[1])
		var op       := _check_op(check_step)
		var expected  = _resolve_param(check_step[op], params)
		if not _compare(actual, expected, op):
			return null

	var subtasks: Array = []
	for subtask_def in alt_def.get("subtasks", []):
		var subtask: Array = []
		for elem in subtask_def:
			subtask.append(_resolve_param(elem, params))
		subtasks.append(subtask)

	return subtasks

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _build_params(param_names: Array, raw_args: Array) -> Dictionary:
	var params := {}
	for i in range(param_names.size()):
		params[param_names[i]] = raw_args[i]
	return params


## Parse "/var/{key}" into ["var", resolved_key].
static func _parse_pointer(pointer: String, params: Dictionary) -> Array:
	var parts := pointer.split("/")
	# Leading "/" produces an empty first element; skip it.
	var offset := 1 if parts.size() > 0 and parts[0] == "" else 0
	if parts.size() < offset + 2:
		return []
	var var_name: String = parts[offset]
	var key_raw: String  = parts[offset + 1]
	return [var_name, _resolve_param(key_raw, params)]


## Substitute "{name}" references; return anything else as-is.
static func _resolve_param(value, params: Dictionary):
	if value is String and value.begins_with("{") and value.ends_with("}"):
		var name := value.substr(1, value.length() - 2)
		return params.get(name, value)
	return value


## Evaluate a value expression: literal | "{param}" | {op, a, b} | {op:"get",...}
static func _eval_expr(expr, params: Dictionary, state: TaskweftState, enums: Dictionary):
	if expr is Dictionary and expr.has("op"):
		return _eval_op(expr, params, state, enums)
	return _resolve_param(expr, params)


static func _eval_op(expr: Dictionary, params: Dictionary, state: TaskweftState, enums: Dictionary):
	var op: String = expr["op"]
	match op:
		"get":
			var ptr := _parse_pointer(expr.get("pointer", ""), params)
			if ptr.size() == 2:
				return state.get_nested(ptr[0], ptr[1])
			return null
		"add":  return _eval_expr(expr["a"], params, state, enums) + _eval_expr(expr["b"], params, state, enums)
		"sub":  return _eval_expr(expr["a"], params, state, enums) - _eval_expr(expr["b"], params, state, enums)
		"mul":  return _eval_expr(expr["a"], params, state, enums) * _eval_expr(expr["b"], params, state, enums)
		"div":  return _eval_expr(expr["a"], params, state, enums) / _eval_expr(expr["b"], params, state, enums)
		"iadd": return int(_eval_expr(expr["a"], params, state, enums)) + int(_eval_expr(expr["b"], params, state, enums))
		"isub": return int(_eval_expr(expr["a"], params, state, enums)) - int(_eval_expr(expr["b"], params, state, enums))
		"imul": return int(_eval_expr(expr["a"], params, state, enums)) * int(_eval_expr(expr["b"], params, state, enums))
		"idiv": return int(_eval_expr(expr["a"], params, state, enums)) / int(_eval_expr(expr["b"], params, state, enums))
		"neg":  return -_eval_expr(expr["a"], params, state, enums)
		"abs":  return abs(_eval_expr(expr["a"], params, state, enums))
		"min":  return min(_eval_expr(expr["a"], params, state, enums), _eval_expr(expr["b"], params, state, enums))
		"max":  return max(_eval_expr(expr["a"], params, state, enums), _eval_expr(expr["b"], params, state, enums))
	return null


## Find which comparison operator key is present in a check/alt-check step.
static func _check_op(step: Dictionary) -> String:
	for op in ["eq", "neq", "lt", "le", "gt", "ge", "ieq", "ilt", "ile", "igt", "ige"]:
		if step.has(op):
			return op
	return "eq"


static func _compare(actual, expected, op: String) -> bool:
	match op:
		"eq", "ieq":  return actual == expected
		"neq":        return actual != expected
		"lt", "ilt":  return actual < expected
		"le", "ile":  return actual <= expected
		"gt", "igt":  return actual > expected
		"ge", "ige":  return actual >= expected
	return false


static func _build_tasks(task_defs: Array) -> Array:
	var tasks: Array = []
	for entry in task_defs:
		if entry is Array:
			tasks.append(entry)
		elif entry is Dictionary and entry.has("multigoal"):
			# Multigoal not yet ported — skip silently.
			pass
	return tasks
