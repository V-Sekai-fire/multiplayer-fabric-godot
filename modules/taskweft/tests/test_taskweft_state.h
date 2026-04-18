/**************************************************************************/
/*  test_taskweft_state.h                                                 */
/**************************************************************************/
// Cycle 1: TaskweftState stores and retrieves a variable
// Cycle 2: copy() produces an independent snapshot
// Cycle 3: has_var() correctly reports presence/absence

#pragma once

#include "../taskweft_state.h"
#include "tests/test_macros.h"

namespace TestTaskweftState {

// Cycle 1
TEST_CASE("[Taskweft][State] set and get a variable") {
	TaskweftState state;
	state.set_var("location", "home");
	CHECK(state.get_var("location") == Variant("home"));
}

TEST_CASE("[Taskweft][State] get missing variable returns null") {
	TaskweftState state;
	CHECK(state.get_var("missing") == Variant());
}

// Cycle 2
TEST_CASE("[Taskweft][State] copy is independent of original") {
	TaskweftState state;
	state.set_var("x", 1);
	Ref<TaskweftState> copy = state.copy();
	copy->set_var("x", 99);
	CHECK(state.get_var("x") == Variant(1));
	CHECK(copy->get_var("x") == Variant(99));
}

// Cycle 3
TEST_CASE("[Taskweft][State] has_var returns true only for set variables") {
	TaskweftState state;
	state.set_var("a", true);
	CHECK(state.has_var("a"));
	CHECK_FALSE(state.has_var("b"));
}

} // namespace TestTaskweftState
