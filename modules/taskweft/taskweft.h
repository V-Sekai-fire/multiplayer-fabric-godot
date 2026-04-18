/**************************************************************************/
/*  taskweft.h                                                            */
/**************************************************************************/
#pragma once

#include "taskweft_domain.h"
#include "taskweft_state.h"

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Re-entrant GTN planner (IPyHOP port).
//
// plan(state, tasks) -> Array of action tuples | null
//
// A task is an Array: [name, arg1, arg2, ...]
// An action callable:  fn(state: TaskweftState, ...args) -> TaskweftState | null
// A method callable:   fn(state: TaskweftState, ...args) -> Array[subtask] | null
//
// The planner does depth-first search over method decompositions,
// backtracking when an action fails or no method applies.
class Taskweft : public RefCounted {
	GDCLASS(Taskweft, RefCounted);

	Ref<TaskweftDomain> _domain;

	// Core DFS — returns Array (plan) or null (failure).
	Variant _seek_plan(Ref<TaskweftState> p_state, const Array &p_tasks, int p_depth) const;

protected:
	static void _bind_methods();

public:
	void set_domain(const Ref<TaskweftDomain> &p_domain);
	Ref<TaskweftDomain> get_domain() const;

	// Returns Array of action tuples on success, null on failure.
	Variant plan(const Ref<TaskweftState> &p_state, const Array &p_tasks) const;

	Taskweft() {}
};
