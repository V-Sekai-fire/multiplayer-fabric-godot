/**************************************************************************/
/*  taskweft_goal.cpp                                                     */
/**************************************************************************/
#include "taskweft_goal.h"

#include "core/object/class_db.h"

void TaskweftGoal::set_goal(const String &p_var, const Variant &p_desired) {
	_bindings[p_var] = p_desired;
}

Variant TaskweftGoal::get_goal(const String &p_var) const {
	if (!_bindings.has(p_var)) {
		return Variant();
	}
	return _bindings[p_var];
}

bool TaskweftGoal::has_goal(const String &p_var) const {
	return _bindings.has(p_var);
}

bool TaskweftGoal::is_satisfied(const Ref<TaskweftState> &p_state) const {
	ERR_FAIL_COND_V(p_state.is_null(), false);
	Array keys = _bindings.keys();
	for (int i = 0; i < keys.size(); ++i) {
		String var = keys[i];
		if (p_state->get_var(var) != _bindings[var]) {
			return false;
		}
	}
	return true;
}

Dictionary TaskweftGoal::unsatisfied(const Ref<TaskweftState> &p_state) const {
	Dictionary result;
	ERR_FAIL_COND_V(p_state.is_null(), result);
	Array keys = _bindings.keys();
	for (int i = 0; i < keys.size(); ++i) {
		String var = keys[i];
		if (p_state->get_var(var) != _bindings[var]) {
			result[var] = _bindings[var];
		}
	}
	return result;
}

Ref<TaskweftGoal> TaskweftGoal::copy() const {
	Ref<TaskweftGoal> goal_copy;
	goal_copy.instantiate();
	goal_copy->_bindings = _bindings.duplicate(true);
	return goal_copy;
}

void TaskweftGoal::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_goal", "var", "desired"), &TaskweftGoal::set_goal);
	ClassDB::bind_method(D_METHOD("get_goal", "var"), &TaskweftGoal::get_goal);
	ClassDB::bind_method(D_METHOD("has_goal", "var"), &TaskweftGoal::has_goal);
	ClassDB::bind_method(D_METHOD("is_satisfied", "state"), &TaskweftGoal::is_satisfied);
	ClassDB::bind_method(D_METHOD("unsatisfied", "state"), &TaskweftGoal::unsatisfied);
	ClassDB::bind_method(D_METHOD("copy"), &TaskweftGoal::copy);
}
