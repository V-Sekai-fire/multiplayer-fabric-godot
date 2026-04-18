/**************************************************************************/
/*  taskweft_state.cpp                                                    */
/**************************************************************************/
#include "taskweft_state.h"

#include "core/object/class_db.h"

void TaskweftState::set_var(const String &p_key, const Variant &p_value) {
	_vars[p_key] = p_value;
}

Variant TaskweftState::get_var(const String &p_key) const {
	if (!_vars.has(p_key)) {
		return Variant();
	}
	return _vars[p_key];
}

bool TaskweftState::has_var(const String &p_key) const {
	return _vars.has(p_key);
}

Dictionary TaskweftState::get_vars() const {
	return _vars;
}

Ref<TaskweftState> TaskweftState::copy() const {
	Ref<TaskweftState> c;
	c.instantiate();
	c->_vars = _vars.duplicate(true);
	return c;
}

void TaskweftState::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_var", "key", "value"), &TaskweftState::set_var);
	ClassDB::bind_method(D_METHOD("get_var", "key"), &TaskweftState::get_var);
	ClassDB::bind_method(D_METHOD("has_var", "key"), &TaskweftState::has_var);
	ClassDB::bind_method(D_METHOD("get_vars"), &TaskweftState::get_vars);
	ClassDB::bind_method(D_METHOD("copy"), &TaskweftState::copy);
}
