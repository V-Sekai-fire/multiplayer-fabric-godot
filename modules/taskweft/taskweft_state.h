/**************************************************************************/
/*  taskweft_state.h                                                      */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Planning state: a named bag of variables. Callables read and write via
// set_var/get_var. copy() produces a deep-copied snapshot for backtracking.
class TaskweftState : public RefCounted {
	GDCLASS(TaskweftState, RefCounted);

	Dictionary _vars;

protected:
	static void _bind_methods();

public:
	void      set_var(const String &p_key, const Variant &p_value);
	Variant   get_var(const String &p_key) const;
	bool      has_var(const String &p_key) const;
	Dictionary get_vars() const;

	// Nested dict-of-dict access: state[var][key] = value
	void    set_nested(const String &p_var, const Variant &p_key, const Variant &p_value);
	Variant get_nested(const String &p_var, const Variant &p_key) const;
	bool    has_nested(const String &p_var, const Variant &p_key) const;

	Ref<TaskweftState> copy() const;

	TaskweftState() {}
};
