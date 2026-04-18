/**************************************************************************/
/*  taskweft_domain.h                                                     */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/variant/callable.h"
#include "core/variant/variant.h"

// Holds the action and method tables for one planning domain.
// Actions:  name -> Callable(state, ...args) -> Ref<TaskweftState> | null
// Methods:  name -> Array[Callable(state, ...args) -> Array[subtask] | null]
class TaskweftDomain : public RefCounted {
	GDCLASS(TaskweftDomain, RefCounted);

	HashMap<String, Callable>       _actions;
	HashMap<String, Array>          _task_methods;

protected:
	static void _bind_methods();

public:
	void  declare_action(const String &p_name, const Callable &p_callable);
	bool  has_action(const String &p_name) const;
	Callable get_action(const String &p_name) const;

	void  declare_task_methods(const String &p_task, const Array &p_methods);
	bool  has_task(const String &p_task) const;
	Array get_task_methods(const String &p_task) const;

	TaskweftDomain() {}
};
