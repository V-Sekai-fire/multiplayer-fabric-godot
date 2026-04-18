/**************************************************************************/
/*  taskweft_domain.cpp                                                   */
/**************************************************************************/
#include "taskweft_domain.h"

#include "core/object/class_db.h"

void TaskweftDomain::declare_action(const String &p_name, const Callable &p_callable) {
	_actions[p_name] = p_callable;
}

bool TaskweftDomain::has_action(const String &p_name) const {
	return _actions.has(p_name);
}

Callable TaskweftDomain::get_action(const String &p_name) const {
	if (!_actions.has(p_name)) {
		return Callable();
	}
	return _actions[p_name];
}

void TaskweftDomain::declare_task_methods(const String &p_task, const Array &p_methods) {
	_task_methods[p_task] = p_methods;
}

bool TaskweftDomain::has_task(const String &p_task) const {
	return _task_methods.has(p_task);
}

Array TaskweftDomain::get_task_methods(const String &p_task) const {
	if (!_task_methods.has(p_task)) {
		return Array();
	}
	return _task_methods[p_task];
}

void TaskweftDomain::declare_goal_methods(const String &p_var, const Array &p_methods) {
	_goal_methods[p_var] = p_methods;
}

bool TaskweftDomain::has_goal_methods(const String &p_var) const {
	return _goal_methods.has(p_var);
}

Array TaskweftDomain::get_goal_methods(const String &p_var) const {
	if (!_goal_methods.has(p_var)) {
		return Array();
	}
	return _goal_methods[p_var];
}

void TaskweftDomain::_bind_methods() {
	ClassDB::bind_method(D_METHOD("declare_action", "name", "callable"), &TaskweftDomain::declare_action);
	ClassDB::bind_method(D_METHOD("has_action", "name"), &TaskweftDomain::has_action);
	ClassDB::bind_method(D_METHOD("declare_task_methods", "task", "methods"), &TaskweftDomain::declare_task_methods);
	ClassDB::bind_method(D_METHOD("has_task", "task"), &TaskweftDomain::has_task);
	ClassDB::bind_method(D_METHOD("get_task_methods", "task"), &TaskweftDomain::get_task_methods);
	ClassDB::bind_method(D_METHOD("declare_goal_methods", "var", "methods"), &TaskweftDomain::declare_goal_methods);
	ClassDB::bind_method(D_METHOD("has_goal_methods", "var"), &TaskweftDomain::has_goal_methods);
	ClassDB::bind_method(D_METHOD("get_goal_methods", "var"), &TaskweftDomain::get_goal_methods);
}
