/**************************************************************************/
/*  taskweft_goal.h                                                       */
/**************************************************************************/
#pragma once

#include "taskweft_state.h"

#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Conjunctive goal: a set of {state_variable: desired_value} bindings.
// Satisfied when every binding matches the current TaskweftState.
// Used as a task list item; the planner keeps it in the list until all
// bindings are met, decomposing unmet variables via goal methods.
class TaskweftGoal : public RefCounted {
	GDCLASS(TaskweftGoal, RefCounted);

	Dictionary _bindings;

protected:
	static void _bind_methods();

public:
	void set_goal(const String &p_var, const Variant &p_desired);
	Variant get_goal(const String &p_var) const;
	bool has_goal(const String &p_var) const;

	// True when every binding matches the state.
	bool is_satisfied(const Ref<TaskweftState> &p_state) const;

	// Returns {var: desired_value} for every binding not yet met.
	Dictionary unsatisfied(const Ref<TaskweftState> &p_state) const;

	Ref<TaskweftGoal> copy() const;

	TaskweftGoal() {}
};
