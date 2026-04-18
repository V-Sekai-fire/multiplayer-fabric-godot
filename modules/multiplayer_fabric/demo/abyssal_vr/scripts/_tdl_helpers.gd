## Shared helpers for TaskweftDomainLoader — no class_name to avoid circular refs.
extends RefCounted

static func build_params(param_names: Array, raw_args: Array) -> Dictionary:
	var params := {}
	for i in range(param_names.size()):
		params[param_names[i]] = raw_args[i]
	return params


## Parse "/var/{key}" → ["var", resolved_key]. Returns [] on malformed input.
static func parse_pointer(pointer: String, params: Dictionary) -> Array:
	var parts := pointer.split("/")
	var offset := 1 if (parts.size() > 0 and parts[0] == "") else 0
	if parts.size() < offset + 2:
		return []
	var var_name: String = parts[offset]
	var key_raw: String  = parts[offset + 1]
	return [var_name, resolve_param(key_raw, params)]


## Substitute "{name}" references; return anything else as-is.
static func resolve_param(value, params: Dictionary):
	if value is String and value.begins_with("{") and value.ends_with("}"):
		var name: String = value.substr(1, value.length() - 2)
		return params.get(name, value)
	return value


## Evaluate a value expression: literal | "{param}" | {op, a, b} | {op:"get",...}
static func eval_expr(expr, params: Dictionary, state: TaskweftState, enums: Dictionary):
	if expr is Dictionary and expr.has("op"):
		return eval_op(expr, params, state, enums)
	return resolve_param(expr, params)


static func eval_op(expr: Dictionary, params: Dictionary, state: TaskweftState, enums: Dictionary):
	var op: String = expr["op"]
	match op:
		"get":
			var ptr := parse_pointer(expr.get("pointer", ""), params)
			if ptr.size() == 2:
				return state.get_nested(ptr[0], ptr[1])
			return null
		"add":  return eval_expr(expr["a"], params, state, enums) + eval_expr(expr["b"], params, state, enums)
		"sub":  return eval_expr(expr["a"], params, state, enums) - eval_expr(expr["b"], params, state, enums)
		"mul":  return eval_expr(expr["a"], params, state, enums) * eval_expr(expr["b"], params, state, enums)
		"div":  return eval_expr(expr["a"], params, state, enums) / eval_expr(expr["b"], params, state, enums)
		"iadd": return int(eval_expr(expr["a"], params, state, enums)) + int(eval_expr(expr["b"], params, state, enums))
		"isub": return int(eval_expr(expr["a"], params, state, enums)) - int(eval_expr(expr["b"], params, state, enums))
		"imul": return int(eval_expr(expr["a"], params, state, enums)) * int(eval_expr(expr["b"], params, state, enums))
		"idiv": return int(eval_expr(expr["a"], params, state, enums)) / int(eval_expr(expr["b"], params, state, enums))
		"neg":  return -eval_expr(expr["a"], params, state, enums)
		"abs":  return abs(eval_expr(expr["a"], params, state, enums))
		"min":  return min(eval_expr(expr["a"], params, state, enums), eval_expr(expr["b"], params, state, enums))
		"max":  return max(eval_expr(expr["a"], params, state, enums), eval_expr(expr["b"], params, state, enums))
	return null


static func check_op(step: Dictionary) -> String:
	for op: String in ["eq", "neq", "lt", "le", "gt", "ge", "ieq", "ilt", "ile", "igt", "ige"]:
		if step.has(op):
			return op
	return "eq"


static func compare(actual, expected, op: String) -> bool:
	match op:
		"eq", "ieq":  return actual == expected
		"neq":        return actual != expected
		"lt", "ilt":  return actual < expected
		"le", "ile":  return actual <= expected
		"gt", "igt":  return actual > expected
		"ge", "ige":  return actual >= expected
	return false


## Evaluate method/action precondition checks. Returns false to fail the step.
static func run_checks(checks: Array, params: Dictionary, state: TaskweftState) -> bool:
	for check_step in checks:
		var raw_ptr = check_step.get("pointer", check_step.get("var", null))
		if raw_ptr == null:
			return false
		var ptr: Array
		if raw_ptr is String:
			ptr = parse_pointer(raw_ptr, params)
		elif raw_ptr is Array and raw_ptr.size() == 2:
			ptr = [raw_ptr[0], resolve_param(raw_ptr[1], params)]
		else:
			return false
		if ptr.size() != 2:
			return false
		var actual  = state.get_nested(ptr[0], ptr[1])
		var op      := check_op(check_step)
		var expected = resolve_param(check_step[op], params)
		if not compare(actual, expected, op):
			return false
	return true


## Expand subtask templates into concrete subtask arrays.
static func expand_subtasks(subtask_defs: Array, params: Dictionary) -> Array:
	var subtasks: Array = []
	for subtask_def in subtask_defs:
		var subtask: Array = []
		for elem in subtask_def:
			subtask.append(resolve_param(elem, params))
		subtasks.append(subtask)
	return subtasks
