## Loads JSON-LD planning domain definitions into TaskweftDomain + TaskweftState.
##
## Usage:
##   var result = TaskweftDomainLoader.load_file("res://taskweft_domains/simple_travel.jsonld")
##   var domain: TaskweftDomain = result.domain
##   var state:  TaskweftState  = result.state
##   var tasks:  Array          = result.tasks
##   var planner = Taskweft.new(); planner.set_domain(domain)
##   var plan = planner.plan(state, tasks)
class_name TaskweftDomainLoader
extends RefCounted

# ---------------------------------------------------------------------------
# Inner runner classes — hold metadata, expose run() as a Callable.
# Godot 4's Callable.bind() appends args, so we store metadata in the object
# and let callv supply only (state, p0, p1, p2, p3).
# ---------------------------------------------------------------------------

class _ActionRunner:
	extends RefCounted
	var param_names: Array
	var bind_defs: Array
	var body: Array
	var enums: Dictionary

	func run(state: TaskweftState, p0 = null, p1 = null, p2 = null, p3 = null) -> Variant:
		var params := TaskweftDomainLoader._build_params(param_names, [p0, p1, p2, p3])

		# Bind steps: read state values into params before the body.
		for bind_step in bind_defs:
			var ptr := TaskweftDomainLoader._parse_pointer(bind_step["pointer"], params)
			if ptr.size() == 2:
				params[bind_step["name"]] = state.get_nested(ptr[0], ptr[1])

		var new_state: TaskweftState = state.copy()

		for step in body:
			if step.has("check"):
				var ptr := TaskweftDomainLoader._parse_pointer(step["check"], params)
				if ptr.size() != 2:
					return null
				var actual  = new_state.get_nested(ptr[0], ptr[1])
				var op      := TaskweftDomainLoader._check_op(step)
				var expected = TaskweftDomainLoader._eval_expr(step[op], params, new_state, enums)
				if not TaskweftDomainLoader._compare(actual, expected, op):
					return null
			elif step.has("set"):
				var ptr := TaskweftDomainLoader._parse_pointer(step["set"], params)
				if ptr.size() != 2:
					return null
				var value = TaskweftDomainLoader._eval_expr(step["value"], params, new_state, enums)
				new_state.set_nested(ptr[0], ptr[1], value)

		return new_state


class _MethodAltRunner:
	extends RefCounted
	var param_names: Array
	var alt_def: Dictionary
	var enums: Dictionary

	func run(state: TaskweftState, p0 = null, p1 = null, p2 = null, p3 = null) -> Variant:
		var params := TaskweftDomainLoader._build_params(param_names, [p0, p1, p2, p3])

		for bind_step in alt_def.get("bind", []):
			var ptr := TaskweftDomainLoader._parse_pointer(bind_step["pointer"], params)
			if ptr.size() == 2:
				params[bind_step["name"]] = state.get_nested(ptr[0], ptr[1])

		for check_step in alt_def.get("check", []):
			var raw_ptr = check_step.get("pointer", check_step.get("var", null))
			if raw_ptr == null:
				return null
			var ptr: Array
			if raw_ptr is String:
				ptr = TaskweftDomainLoader._parse_pointer(raw_ptr, params)
			elif raw_ptr is Array and raw_ptr.size() == 2:
				ptr = [raw_ptr[0], TaskweftDomainLoader._resolve_param(raw_ptr[1], params)]
			else:
				return null
			if ptr.size() != 2:
				return null
			var actual  = state.get_nested(ptr[0], ptr[1])
			var op      := TaskweftDomainLoader._check_op(check_step)
			var expected = TaskweftDomainLoader._resolve_param(check_step[op], params)
			if not TaskweftDomainLoader._compare(actual, expected, op):
				return null

		var subtasks: Array = []
		for subtask_def in alt_def.get("subtasks", []):
			var subtask: Array = []
			for elem in subtask_def:
				subtask.append(TaskweftDomainLoader._resolve_param(elem, params))
			subtasks.append(subtask)

		return subtasks


class _GoalMethodRunner:
	extends RefCounted
	var goal_param_names: Array
	var alt_def: Dictionary
	var enums: Dictionary

	func run(state: TaskweftState, desired = null) -> Variant:
		var params := {}
		if goal_param_names.size() >= 1:
			params[goal_param_names[0]] = desired

		for bind_step in alt_def.get("bind", []):
			var ptr := TaskweftDomainLoader._parse_pointer(bind_step["pointer"], params)
			if ptr.size() == 2:
				params[bind_step["name"]] = state.get_nested(ptr[0], ptr[1])

		for check_step in alt_def.get("check", []):
			var raw_ptr = check_step.get("pointer", check_step.get("var", null))
			if raw_ptr == null:
				return null
			var ptr: Array
			if raw_ptr is String:
				ptr = TaskweftDomainLoader._parse_pointer(raw_ptr, params)
			elif raw_ptr is Array and raw_ptr.size() == 2:
				ptr = [raw_ptr[0], TaskweftDomainLoader._resolve_param(raw_ptr[1], params)]
			else:
				return null
			var actual   = state.get_nested(ptr[0], ptr[1])
			var op       := TaskweftDomainLoader._check_op(check_step)
			var expected  = TaskweftDomainLoader._resolve_param(check_step[op], params)
			if not TaskweftDomainLoader._compare(actual, expected, op):
				return null

		var subtasks: Array = []
		for subtask_def in alt_def.get("subtasks", []):
			var subtask: Array = []
			for elem in subtask_def:
				subtask.append(TaskweftDomainLoader._resolve_param(elem, params))
			subtasks.append(subtask)

		return subtasks

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
		elif init != null:
			state.set_var(var_name, init)

	# Build actions.
	for action_name in data.get("actions", {}):
		var action_def: Dictionary = data["actions"][action_name]
		var runner := _ActionRunner.new()
		runner.param_names = action_def.get("params", [])
		runner.bind_defs   = action_def.get("bind", [])
		runner.body        = action_def.get("body", [])
		runner.enums       = enums
		domain.declare_action(action_name, Callable(runner, "run"))

	# Build task methods.
	for task_name in data.get("methods", {}):
		var group: Dictionary = data["methods"][task_name]
		var param_names: Array = group.get("params", [])
		var callables: Array = []
		for alt in group.get("alternatives", []):
			var runner := _MethodAltRunner.new()
			runner.param_names = param_names
			runner.alt_def     = alt
			runner.enums       = enums
			callables.append(Callable(runner, "run"))
		domain.declare_task_methods(task_name, callables)

	# Build goal methods (keyed by state variable name).
	for goal_var in data.get("goals", {}):
		var group: Dictionary = data["goals"][goal_var]
		var callables: Array = []
		for alt in group.get("alternatives", []):
			var runner := _GoalMethodRunner.new()
			runner.goal_param_names = group.get("params", [])
			runner.alt_def          = alt
			runner.enums            = enums
			callables.append(Callable(runner, "run"))
		domain.declare_goal_methods(goal_var, callables)

	var tasks: Array = _build_tasks(data.get("tasks", []))

	return {"domain": domain, "state": state, "tasks": tasks, "enums": enums}

# ---------------------------------------------------------------------------
# Helpers (static — callable by inner classes via TaskweftDomainLoader.xxx)
# ---------------------------------------------------------------------------

static func _build_params(param_names: Array, raw_args: Array) -> Dictionary:
	var params := {}
	for i in range(param_names.size()):
		params[param_names[i]] = raw_args[i]
	return params


## Parse "/var/{key}" into ["var", resolved_key].
static func _parse_pointer(pointer: String, params: Dictionary) -> Array:
	var parts := pointer.split("/")
	var offset := 1 if (parts.size() > 0 and parts[0] == "") else 0
	if parts.size() < offset + 2:
		return []
	var var_name: String = parts[offset]
	var key_raw: String  = parts[offset + 1]
	return [var_name, _resolve_param(key_raw, params)]


## Substitute "{name}" references; return anything else as-is.
static func _resolve_param(value, params: Dictionary):
	if value is String and value.begins_with("{") and value.ends_with("}"):
		var name: String = value.substr(1, value.length() - 2)
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


static func _check_op(step: Dictionary) -> String:
	for op: String in ["eq", "neq", "lt", "le", "gt", "ge", "ieq", "ilt", "ile", "igt", "ige"]:
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
	return tasks
