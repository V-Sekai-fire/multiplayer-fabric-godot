/**************************************************************************/
/*  taskweft.cpp                                                          */
/**************************************************************************/
#include "taskweft.h"

#include "core/object/class_db.h"

static constexpr int MAX_DEPTH = 256;

void Taskweft::set_domain(const Ref<TaskweftDomain> &p_domain) {
	_domain = p_domain;
}

Ref<TaskweftDomain> Taskweft::get_domain() const {
	return _domain;
}

Variant Taskweft::_seek_plan(Ref<TaskweftState> p_state, const Array &p_tasks, int p_depth) const {
	if (p_depth > MAX_DEPTH) {
		return Variant(); // null — depth limit
	}

	// Base case: no tasks left → success with empty plan.
	if (p_tasks.is_empty()) {
		return Array();
	}

	ERR_FAIL_COND_V(_domain.is_null(), Variant());

	Array task = p_tasks[0];
	ERR_FAIL_COND_V(task.is_empty(), Variant());

	String task_name = task[0];

	// Build remaining tasks (everything after the first).
	Array remaining_tasks;
	for (int i = 1; i < p_tasks.size(); ++i) {
		remaining_tasks.push_back(p_tasks[i]);
	}

	// Build task arguments (task[1..]).
	Array task_args;
	for (int i = 1; i < task.size(); ++i) {
		task_args.push_back(task[i]);
	}

	// --- Primitive action ---
	if (_domain->has_action(task_name)) {
		Callable action = _domain->get_action(task_name);

		// Call: action(state_copy, arg1, arg2, ...)
		Array call_args;
		Ref<TaskweftState> state_copy = p_state->copy();
		call_args.push_back(state_copy);
		for (int i = 0; i < task_args.size(); ++i) {
			call_args.push_back(task_args[i]);
		}

		Variant new_state_variant = action.callv(call_args);

		// Action returns null → precondition failed, backtrack.
		if (new_state_variant.get_type() == Variant::NIL) {
			return Variant();
		}

		Ref<TaskweftState> new_state = new_state_variant;
		ERR_FAIL_COND_V(new_state.is_null(), Variant());

		Variant sub_plan = _seek_plan(new_state, remaining_tasks, p_depth + 1);
		if (sub_plan.get_type() == Variant::NIL) {
			return Variant();
		}

		// Prepend this action to the sub-plan.
		Array plan;
		plan.push_back(task);
		Array sub_plan_array = sub_plan;
		for (int i = 0; i < sub_plan_array.size(); ++i) {
			plan.push_back(sub_plan_array[i]);
		}
		return plan;
	}

	// --- Compound task: try each method in order ---
	if (_domain->has_task(task_name)) {
		Array methods = _domain->get_task_methods(task_name);

		for (int method_index = 0; method_index < methods.size(); ++method_index) {
			Callable method = methods[method_index];

			Array call_args;
			call_args.push_back(p_state);
			for (int i = 0; i < task_args.size(); ++i) {
				call_args.push_back(task_args[i]);
			}

			Variant subtasks_variant = method.callv(call_args);

			// Method returns null → not applicable, try next.
			if (subtasks_variant.get_type() == Variant::NIL) {
				continue;
			}

			Array subtasks = subtasks_variant;

			// Prepend subtasks to the remaining tasks.
			Array new_tasks;
			for (int i = 0; i < subtasks.size(); ++i) {
				new_tasks.push_back(subtasks[i]);
			}
			for (int i = 0; i < remaining_tasks.size(); ++i) {
				new_tasks.push_back(remaining_tasks[i]);
			}

			Variant result = _seek_plan(p_state, new_tasks, p_depth + 1);
			if (result.get_type() != Variant::NIL) {
				return result;
			}
			// This method failed — try the next one.
		}

		return Variant(); // All methods failed.
	}

	// Unknown task name.
	return Variant();
}

Variant Taskweft::plan(const Ref<TaskweftState> &p_state, const Array &p_tasks) const {
	ERR_FAIL_COND_V(p_state.is_null(), Variant());
	return _seek_plan(p_state, p_tasks, 0);
}

void Taskweft::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_domain", "domain"), &Taskweft::set_domain);
	ClassDB::bind_method(D_METHOD("get_domain"), &Taskweft::get_domain);
	ClassDB::bind_method(D_METHOD("plan", "state", "tasks"), &Taskweft::plan);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "domain",
				PROPERTY_HINT_RESOURCE_TYPE, "TaskweftDomain"),
			"set_domain", "get_domain");
}
