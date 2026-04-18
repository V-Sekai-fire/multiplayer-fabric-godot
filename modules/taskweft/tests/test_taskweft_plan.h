/**************************************************************************/
/*  test_taskweft_plan.h                                                  */
/**************************************************************************/
// Cycle 6:  empty task list returns empty plan
// Cycle 7:  single primitive action that succeeds returns [action]
// Cycle 8:  primitive action that returns null (failure) → plan returns null
// Cycle 9:  compound task decomposes via method into primitive actions
// Cycle 10: unsolvable task (no applicable method) returns null

#pragma once

#include "../taskweft.h"
#include "../taskweft_domain.h"
#include "../taskweft_state.h"
#include "tests/test_macros.h"

namespace TestTaskweftPlan {

// Cycle 6
TEST_CASE("[Taskweft][Plan] empty task list returns empty array") {
	Ref<TaskweftDomain> domain;
	domain.instantiate();
	Taskweft planner;
	planner.set_domain(domain);

	Ref<TaskweftState> state;
	state.instantiate();
	Variant result = planner.plan(state, Array());
	REQUIRE(result.get_type() == Variant::ARRAY);
	CHECK(Array(result).is_empty());
}

// Cycle 7: action(state, args) returns a modified state on success
TEST_CASE("[Taskweft][Plan] single applicable primitive action produces a 1-step plan") {
	// Action: move(state, dest) — sets state.location = dest, always succeeds
	Ref<TaskweftDomain> domain;
	domain.instantiate();

	// GDScript equivalent: func move(state, dest): state.set_var("location", dest); return state
	// We test via a lambda-backed Callable constructed from a static helper.
	struct Helper {
		static Variant move_action(Ref<TaskweftState> state, String dest) {
			state->set_var("location", dest);
			return state;
		}
	};
	Callable action = callable_mp_static(&Helper::move_action);
	domain->declare_action("move", action);

	Ref<TaskweftState> state;
	state.instantiate();
	state->set_var("location", "home");

	Array tasks;
	Array task;
	task.push_back("move");
	task.push_back("office");
	tasks.push_back(task);

	Taskweft planner;
	planner.set_domain(domain);
	Variant result = planner.plan(state, tasks);
	REQUIRE(result.get_type() == Variant::ARRAY);
	Array plan = result;
	REQUIRE(plan.size() == 1);
	CHECK(Array(plan[0])[0] == Variant("move"));
}

// Cycle 8
TEST_CASE("[Taskweft][Plan] action that returns null causes plan failure") {
	Ref<TaskweftDomain> domain;
	domain.instantiate();
	struct Helper {
		static Variant always_fail(Ref<TaskweftState> state) { return Variant(); }
	};
	domain->declare_action("fail_op", callable_mp_static(&Helper::always_fail));

	Ref<TaskweftState> state;
	state.instantiate();
	Array tasks;
	Array task;
	task.push_back("fail_op");
	tasks.push_back(task);

	Taskweft planner;
	planner.set_domain(domain);
	Variant result = planner.plan(state, tasks);
	CHECK(result.get_type() == Variant::NIL);
}

// Cycle 9: compound task → method decomposes into primitive
TEST_CASE("[Taskweft][Plan] compound task decomposes via method") {
	Ref<TaskweftDomain> domain;
	domain.instantiate();

	// Primitive: move(state, dest)
	struct Helper {
		static Variant move_action(Ref<TaskweftState> state, String dest) {
			state->set_var("location", dest);
			return state;
		}
		// Method: go_home(state) → [["move", "home"]]
		static Variant go_home_method(Ref<TaskweftState> state) {
			Array subtask;
			subtask.push_back("move");
			subtask.push_back("home");
			Array result;
			result.push_back(subtask);
			return result;
		}
	};
	domain->declare_action("move", callable_mp_static(&Helper::move_action));
	Array go_home_methods;
	go_home_methods.push_back(callable_mp_static(&Helper::go_home_method));
	domain->declare_task_methods("go_home", go_home_methods);

	Ref<TaskweftState> state;
	state.instantiate();
	state->set_var("location", "office");

	Array tasks;
	Array task;
	task.push_back("go_home");
	tasks.push_back(task);

	Taskweft planner;
	planner.set_domain(domain);
	Variant result = planner.plan(state, tasks);
	REQUIRE(result.get_type() == Variant::ARRAY);
	Array plan = result;
	REQUIRE(plan.size() == 1);
	CHECK(Array(plan[0])[0] == Variant("move"));
	CHECK(Array(plan[0])[1] == Variant("home"));
}

// Cycle 10
TEST_CASE("[Taskweft][Plan] unknown task returns null") {
	Ref<TaskweftDomain> domain;
	domain.instantiate();
	Ref<TaskweftState> state;
	state.instantiate();

	Array tasks;
	Array task;
	task.push_back("no_such_task");
	tasks.push_back(task);

	Taskweft planner;
	planner.set_domain(domain);
	Variant result = planner.plan(state, tasks);
	CHECK(result.get_type() == Variant::NIL);
}

} // namespace TestTaskweftPlan
