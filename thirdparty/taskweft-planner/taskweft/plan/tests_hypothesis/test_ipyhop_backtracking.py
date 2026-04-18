#!/usr/bin/env python
"""
Property-based tests for IPyHOP backtracking using Hypothesis.
Tests correct backtracking behavior with flag-setting and flag-checking actions.

Migrated from ipyhop_tests/backtracking_test.py.
"""

import hypothesis.strategies as st
import pytest
from hypothesis import HealthCheck, given, settings

from ipyhop import Actions, IPyHOP, Methods, State

# ============================================================================
# Shared Setup
# ============================================================================


def make_backtracking_planner():
    """Create the backtracking test planner with put/get actions and methods."""

    def a_putv(state, flag_val):
        state.flag = flag_val
        return state

    def a_getv(state, flag_val):
        if state.flag == flag_val:
            return state

    actions = Actions()
    actions.declare_actions([a_putv, a_getv])

    def m_err(state):
        return [("a_putv", 0), ("a_getv", 1)]

    def m0(state):
        return [("a_putv", 0), ("a_getv", 0)]

    def m1(state):
        return [("a_putv", 1), ("a_getv", 1)]

    methods = Methods()
    methods.declare_task_methods("put_it", [m_err, m0, m1])

    def m_need0(state):
        return [("a_getv", 0)]

    def m_need1(state):
        return [("a_getv", 1)]

    methods.declare_task_methods("need0", [m_need0])
    methods.declare_task_methods("need1", [m_need1])
    methods.declare_task_methods("need01", [m_need0, m_need1])
    methods.declare_task_methods("need10", [m_need1, m_need0])

    planner = IPyHOP(methods, actions)
    return planner


def make_init_state(flag_val=-1):
    """Create the initial state for backtracking tests."""
    init_state = State("init_state")
    init_state.flag = flag_val
    return init_state


# ============================================================================
# Strategies
# ============================================================================


@st.composite
def initial_flag_values(draw):
    """Generate initial flag values (should not affect outcome since put_it overwrites)."""
    return draw(st.integers(-100, 100).filter(lambda x: x not in (0, 1)))


# ============================================================================
# Core Backtracking Tests
# ============================================================================


@given(initial_flag_values())
@settings(max_examples=50)
def test_backtrack_put_then_need0(init_flag):
    """
    Property: put_it + need0 should backtrack past m_err to m0, producing put(0), get(0), get(0).
    The initial flag value should not matter since put_it overwrites it.
    """
    planner = make_backtracking_planner()
    init_state = make_init_state(init_flag)

    plan = planner.plan(init_state, [("put_it",), ("need0",)])

    expected = [("a_putv", 0), ("a_getv", 0), ("a_getv", 0)]
    assert plan == expected


@given(initial_flag_values())
@settings(max_examples=50)
def test_backtrack_put_then_need01(init_flag):
    """
    Property: put_it + need01 should behave like put_it + need0.
    need01 tries need0 first, which succeeds after backtracking.
    """
    planner = make_backtracking_planner()
    init_state = make_init_state(init_flag)

    plan = planner.plan(init_state, [("put_it",), ("need01",)])

    expected = [("a_putv", 0), ("a_getv", 0), ("a_getv", 0)]
    assert plan == expected


@given(initial_flag_values())
@settings(max_examples=50)
def test_backtrack_put_then_need10(init_flag):
    """
    Property: put_it + need10 backtracks put_it to m0, then need10 backtracks
    from m_need1 to m_need0. Result is put(0), get(0), get(0).
    """
    planner = make_backtracking_planner()
    init_state = make_init_state(init_flag)

    plan = planner.plan(init_state, [("put_it",), ("need10",)])

    expected = [("a_putv", 0), ("a_getv", 0), ("a_getv", 0)]
    assert plan == expected


@given(initial_flag_values())
@settings(max_examples=50)
def test_backtrack_put_then_need1(init_flag):
    """
    Property: put_it + need1 should backtrack past m_err and m0 to m1,
    producing put(1), get(1), get(1).
    """
    planner = make_backtracking_planner()
    init_state = make_init_state(init_flag)

    plan = planner.plan(init_state, [("put_it",), ("need1",)])

    expected = [("a_putv", 1), ("a_getv", 1), ("a_getv", 1)]
    assert plan == expected


# ============================================================================
# Generalized Backtracking Properties
# ============================================================================


@given(initial_flag_values())
@settings(max_examples=50)
def test_plan_actions_only_contain_declared(init_flag):
    """Property: All actions in any plan should be declared actions."""
    planner = make_backtracking_planner()
    init_state = make_init_state(init_flag)

    for tasks in [
        [("put_it",), ("need0",)],
        [("put_it",), ("need1",)],
        [("put_it",), ("need01",)],
        [("put_it",), ("need10",)],
    ]:
        plan = planner.plan(init_state, tasks)
        for step in plan:
            assert step[0] in ("a_putv", "a_getv")


@given(initial_flag_values())
@settings(max_examples=50)
def test_plan_ends_with_consistent_get(init_flag):
    """
    Property: The last action should be a_getv, and the value it checks
    should match the value set by a_putv earlier in the plan.
    """
    planner = make_backtracking_planner()
    init_state = make_init_state(init_flag)

    for tasks in [
        [("put_it",), ("need0",)],
        [("put_it",), ("need1",)],
        [("put_it",), ("need01",)],
        [("put_it",), ("need10",)],
    ]:
        plan = planner.plan(init_state, tasks)
        assert len(plan) > 0

        # Find last putv value
        put_val = None
        for step in plan:
            if step[0] == "a_putv":
                put_val = step[1]

        # Last action should check the same value
        last = plan[-1]
        assert last[0] == "a_getv"
        assert last[1] == put_val


@given(initial_flag_values())
@settings(max_examples=50)
def test_all_plans_have_length_three(init_flag):
    """
    Property: For all put_it + need* combinations, the plan should always
    have exactly 3 steps: putv, getv (from put_it), getv (from need*).
    """
    planner = make_backtracking_planner()
    init_state = make_init_state(init_flag)

    for tasks in [
        [("put_it",), ("need0",)],
        [("put_it",), ("need1",)],
        [("put_it",), ("need01",)],
        [("put_it",), ("need10",)],
    ]:
        plan = planner.plan(init_state, tasks)
        assert len(plan) == 3


# ============================================================================
# Dynamic Method Generation
# ============================================================================


@given(st.integers(min_value=0, max_value=10))
@settings(max_examples=30)
def test_backtrack_across_n_failing_methods(n_failing):
    """
    Property: With N failing methods before a correct one, the planner
    should backtrack through all N and find the correct plan.
    """

    def a_putv(state, flag_val):
        state.flag = flag_val
        return state

    def a_getv(state, flag_val):
        if state.flag == flag_val:
            return state

    actions = Actions()
    actions.declare_actions([a_putv, a_getv])

    methods = Methods()
    method_list = []

    # N methods that put wrong value then check for 0
    for _ in range(n_failing):
        def make_bad():
            def bad(state):
                return [("a_putv", 99), ("a_getv", 0)]

            return bad

        method_list.append(make_bad())

    # Correct method
    def correct(state):
        return [("a_putv", 0), ("a_getv", 0)]

    method_list.append(correct)

    methods.declare_task_methods("task", method_list)

    def m_need0(state):
        return [("a_getv", 0)]

    methods.declare_task_methods("check", [m_need0])

    planner = IPyHOP(methods, actions)
    init_state = make_init_state()

    plan = planner.plan(init_state, [("task",), ("check",)])

    expected = [("a_putv", 0), ("a_getv", 0), ("a_getv", 0)]
    assert plan == expected


@given(st.sampled_from([0, 1]))
@settings(max_examples=20)
def test_need_specific_value(target_val):
    """Property: Requesting a specific value should produce the matching method."""
    planner = make_backtracking_planner()
    init_state = make_init_state()

    need_task = "need0" if target_val == 0 else "need1"
    plan = planner.plan(init_state, [("put_it",), (need_task,)])

    # All getv checks should match the target
    for step in plan:
        if step[0] == "a_getv":
            assert step[1] == target_val

    # The putv should set the target
    for step in plan:
        if step[0] == "a_putv":
            assert step[1] == target_val


# ============================================================================
# Edge Cases
# ============================================================================


def test_backtracking_with_default_state():
    """Standard backtracking test with the canonical initial state (flag=-1)."""
    planner = make_backtracking_planner()
    init_state = make_init_state(-1)

    plan = planner.plan(init_state, [("put_it",), ("need0",)])
    assert plan == [("a_putv", 0), ("a_getv", 0), ("a_getv", 0)]


def test_initial_flag_zero_still_backtracks():
    """Even if flag starts at 0, m_err still fails (puts 0 then checks 1)."""
    planner = make_backtracking_planner()
    init_state = make_init_state(0)

    plan = planner.plan(init_state, [("put_it",), ("need0",)])
    assert plan == [("a_putv", 0), ("a_getv", 0), ("a_getv", 0)]


def test_initial_flag_one_still_backtracks():
    """Even if flag starts at 1, m_err still fails (puts 0 then checks 1)."""
    planner = make_backtracking_planner()
    init_state = make_init_state(1)

    plan = planner.plan(init_state, [("put_it",), ("need1",)])
    assert plan == [("a_putv", 1), ("a_getv", 1), ("a_getv", 1)]


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
