/**************************************************************************/
/*  test_taskweft_goal.h                                                  */
/**************************************************************************/
// Cycle 11: TaskweftGoal stores bindings and checks satisfaction
// Cycle 12: unsatisfied() returns only unmet bindings
// Cycle 13: planner skips a goal that is already met
// Cycle 14: planner applies a goal method to achieve an unmet goal
// Cycle 15: planner leaves goal in list until fully satisfied

#pragma once

#include "../taskweft.h"
#include "../taskweft_domain.h"
#include "../taskweft_goal.h"
#include "../taskweft_state.h"
#include "tests/test_macros.h"

namespace TestTaskweftGoal {

// Cycle 11
TEST_CASE("[Taskweft][Goal] satisfied when state matches all bindings") {
	Ref<TaskweftGoal> goal;
	goal.instantiate();
	goal->set_goal("location", "home");

	Ref<TaskweftState> state;
	state.instantiate();
	state->set_var("location", "home");

	CHECK(goal->is_satisfied(state));
}

TEST_CASE("[Taskweft][Goal] not satisfied when state differs") {
	Ref<TaskweftGoal> goal;
	goal.instantiate();
	goal->set_goal("location", "home");

	Ref<TaskweftState> state;
	state.instantiate();
	state->set_var("location", "office");

	CHECK_FALSE(goal->is_satisfied(state));
}

// Cycle 12
TEST_CASE("[Taskweft][Goal] unsatisfied returns only unmet bindings") {
	Ref<TaskweftGoal> goal;
	goal.instantiate();
	goal->set_goal("location", "home");
	goal->set_goal("energy", "high");

	Ref<TaskweftState> state;
	state.instantiate();
	state->set_var("location", "home");
	state->set_var("energy", "low");

	Dictionary unmet = goal->unsatisfied(state);
	CHECK(unmet.size() == 1);
	CHECK(unmet.has("energy"));
	CHECK(unmet["energy"] == Variant("high"));
}

// Cycle 13: planner skips a goal already satisfied
TEST_CASE("[Taskweft][Plan] already-satisfied goal produces empty plan") {
	Ref<TaskweftDomain> domain;
	domain.instantiate();
	Taskweft planner;
	planner.set_domain(domain);

	Ref<TaskweftState> state;
	state.instantiate();
	state->set_var("location", "home");

	Ref<TaskweftGoal> goal;
	goal.instantiate();
	goal->set_goal("location", "home");

	Array tasks;
	tasks.push_back(goal);

	Variant result = planner.plan(state, tasks);
	REQUIRE(result.get_type() == Variant::ARRAY);
	CHECK(Array(result).is_empty());
}

// Cycle 14: planner applies a goal method to achieve an unmet variable
TEST_CASE("[Taskweft][Plan] goal method decomposes unmet goal into actions") {
	Ref<TaskweftDomain> domain;
	domain.instantiate();

	struct Helper {
		static Variant move_action(Ref<TaskweftState> state, String dest) {
			state->set_var("location", dest);
			return state;
		}
		// Goal method: achieve location = desired by issuing ["move", desired]
		static Variant goto_method(Ref<TaskweftState> state, String desired) {
			Array subtask;
			subtask.push_back("move");
			subtask.push_back(desired);
			Array result;
			result.push_back(subtask);
			return result;
		}
	};

	domain->declare_action("move", callable_mp_static(&Helper::move_action));
	Array goto_methods;
	goto_methods.push_back(callable_mp_static(&Helper::goto_method));
	domain->declare_goal_methods("location", goto_methods);

	Ref<TaskweftState> state;
	state.instantiate();
	state->set_var("location", "office");

	Ref<TaskweftGoal> goal;
	goal.instantiate();
	goal->set_goal("location", "home");

	Array tasks;
	tasks.push_back(goal);

	Taskweft planner;
	planner.set_domain(domain);
	Variant result = planner.plan(state, tasks);

	REQUIRE(result.get_type() == Variant::ARRAY);
	Array plan = result;
	REQUIRE(plan.size() == 1);
	CHECK(Array(plan[0])[0] == Variant("move"));
	CHECK(Array(plan[0])[1] == Variant("home"));
}

// Cycle 15: no goal method for unmet variable returns null
TEST_CASE("[Taskweft][Plan] unmet goal with no method returns null") {
	Ref<TaskweftDomain> domain;
	domain.instantiate();
	Taskweft planner;
	planner.set_domain(domain);

	Ref<TaskweftState> state;
	state.instantiate();
	state->set_var("location", "office");

	Ref<TaskweftGoal> goal;
	goal.instantiate();
	goal->set_goal("location", "home");

	Array tasks;
	tasks.push_back(goal);

	Variant result = planner.plan(state, tasks);
	CHECK(result.get_type() == Variant::NIL);
}

} // namespace TestTaskweftGoal
