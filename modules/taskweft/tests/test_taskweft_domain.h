/**************************************************************************/
/*  test_taskweft_domain.h                                                */
/**************************************************************************/
// Cycle 4: register a primitive action; has_action reports it
// Cycle 5: register a method; has_task reports it; get_task_methods returns it

#pragma once

#include "../taskweft_domain.h"
#include "tests/test_macros.h"

namespace TestTaskweftDomain {

// Cycle 4
TEST_CASE("[Taskweft][Domain] registered action is findable") {
	TaskweftDomain domain;
	Callable noop; // null callable; registration just needs the name
	domain.declare_action("move", noop);
	CHECK(domain.has_action("move"));
	CHECK_FALSE(domain.has_action("fly"));
}

// Cycle 5
TEST_CASE("[Taskweft][Domain] registered method is findable") {
	TaskweftDomain domain;
	Callable method;
	Array methods_travel;
	methods_travel.push_back(method);
	domain.declare_task_methods("travel", methods_travel);
	CHECK(domain.has_task("travel"));
	CHECK_FALSE(domain.has_task("cook"));
	CHECK(domain.get_task_methods("travel").size() == 1);
}

TEST_CASE("[Taskweft][Domain] multiple methods accumulate") {
	TaskweftDomain domain;
	Callable method1, method2;
	Array methods_task;
	methods_task.push_back(method1);
	methods_task.push_back(method2);
	domain.declare_task_methods("task", methods_task);
	CHECK(domain.get_task_methods("task").size() == 2);
}

} // namespace TestTaskweftDomain
