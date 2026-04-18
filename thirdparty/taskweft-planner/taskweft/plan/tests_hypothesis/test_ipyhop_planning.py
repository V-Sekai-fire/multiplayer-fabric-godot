#!/usr/bin/env python
"""
Property-based tests for IPyHOP planner using Hypothesis.
Covers planning, backtracking at various depths, unsolvable scenarios,
and replanning after action failure.

Migrated from ipyhop_tests/sample_test_1 through sample_test_7.
"""

import hypothesis.strategies as st
import pytest
from hypothesis import HealthCheck, assume, given, settings

from ipyhop import Actions, IPyHOP, Methods, State

# ============================================================================
# Strategies
# ============================================================================


@st.composite
def flag_states(draw, min_flags=20, max_flags=30):
    """Generate initial states with a flag dict where flag[0] is True and others False."""
    n_flags = draw(st.integers(min_flags, max_flags))
    init_state = State("init_state")
    init_state.flag = {0: True}
    for i in range(1, n_flags):
        init_state.flag[i] = False
    return init_state


@st.composite
def flag_states_with_extra(draw, min_extra=0, max_extra=10):
    """Generate initial states with extra flags beyond the minimum 20."""
    n_extra = draw(st.integers(min_extra, max_extra))
    init_state = State("init_state")
    init_state.flag = {0: True}
    for i in range(1, 20 + n_extra):
        init_state.flag[i] = False
    return init_state


# ============================================================================
# Shared Fixtures: Actions
# ============================================================================


def make_chain_actions():
    """Create the standard t_a action used across sample tests."""

    def t_a(state, flag_key_1, flag_key_2):
        if state.flag[flag_key_1] is True:
            state.flag[flag_key_2] = True
            return state

    actions = Actions()
    actions.declare_actions([t_a])
    return actions


# ============================================================================
# Plan Validity Properties
# ============================================================================


@given(flag_states())
@settings(max_examples=50)
def test_plan_actions_are_declared(init_state):
    """Property: Every action in a plan should be a declared action name."""
    actions = make_chain_actions()
    methods = Methods()

    def tm_1_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3)]

    methods.declare_task_methods("tm_1", [tm_1_1])

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("tm_1",)])

    for step in plan:
        assert step[0] in actions.action_dict, f"Action {step[0]} not in declared actions"


@given(flag_states())
@settings(max_examples=50)
def test_plan_simulation_succeeds(init_state):
    """Property: A successful plan should be simulatable from the initial state."""
    actions = make_chain_actions()
    methods = Methods()

    def tm_1_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3)]

    methods.declare_task_methods("tm_1", [tm_1_1])

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("tm_1",)])

    assert plan is not None
    assert len(plan) > 0

    state_list = planner.simulate(init_state)
    assert state_list is not None
    # simulate returns one state per action plus the initial state
    assert len(state_list) == len(plan) + 1


# ============================================================================
# Backtracking Depth 2 (sample_test_1)
# ============================================================================


@given(flag_states())
@settings(max_examples=50)
def test_backtracking_depth_2(init_state):
    """
    Property: Planner should backtrack across methods to find a valid plan.
    Corresponds to sample_test_1: depth-2 backtracking.
    """
    actions = make_chain_actions()
    methods = Methods()

    def tm_1_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 3, 4)]

    def tm_1_2(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3)]

    def tm_1_3(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3), ("t_a", 3, 4)]

    methods.declare_task_methods("tm_1", [tm_1_1, tm_1_2, tm_1_3])

    def tm_2_1(state):
        return [("t_a", 3, 4), ("t_a", 4, 5), ("t_a", 6, 7)]

    def tm_2_2(state):
        return [("t_a", 4, 5), ("t_a", 5, 6), ("t_a", 6, 7)]

    methods.declare_task_methods("tm_2", [tm_2_1, tm_2_2])

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("tm_1",), ("tm_2",)])

    expected = [
        ("t_a", 0, 1),
        ("t_a", 1, 2),
        ("t_a", 2, 3),
        ("t_a", 3, 4),
        ("t_a", 4, 5),
        ("t_a", 5, 6),
        ("t_a", 6, 7),
    ]
    assert plan == expected


# ============================================================================
# Backtracking Depth 3 (sample_test_2)
# ============================================================================


@given(flag_states())
@settings(max_examples=50)
def test_backtracking_depth_3(init_state):
    """
    Property: Planner should backtrack across nested methods (depth 3).
    Corresponds to sample_test_2.
    """
    actions = make_chain_actions()
    methods = Methods()

    def tm_1_1(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5)]

    def tm_1_2(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5), ("t_a", 5, 6)]

    methods.declare_task_methods("tm_1", [tm_1_1, tm_1_2, tm_1_2])

    def tm_2_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3)]

    def tm_2_2(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3), ("t_a", 3, 7)]

    methods.declare_task_methods("tm_2", [tm_2_1, tm_2_2])

    def tm_3_1(state):
        return [("t_a", 7, 8)]

    methods.declare_task_methods("tm_3", [tm_3_1])

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("tm_1",), ("tm_3",)])

    expected = [
        ("t_a", 0, 1),
        ("t_a", 1, 2),
        ("t_a", 2, 3),
        ("t_a", 3, 7),
        ("t_a", 3, 4),
        ("t_a", 4, 5),
        ("t_a", 7, 8),
    ]
    assert plan == expected


# ============================================================================
# Unsolvable Backtracking (sample_test_3)
# ============================================================================


@given(flag_states())
@settings(max_examples=50)
def test_unsolvable_returns_empty(init_state):
    """
    Property: Planner should return empty list for unsolvable problems.
    Corresponds to sample_test_3.
    """
    actions = make_chain_actions()
    methods = Methods()

    def tm_1_1(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5)]

    def tm_1_2(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5), ("t_a", 5, 6)]

    methods.declare_task_methods("tm_1", [tm_1_1, tm_1_2, tm_1_2])

    def tm_2_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3)]

    def tm_2_2(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3), ("t_a", 3, 7)]

    methods.declare_task_methods("tm_2", [tm_2_1, tm_2_2])

    def tm_3_1(state):
        return [("t_a", 9, 10)]

    methods.declare_task_methods("tm_3", [tm_3_1])

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("tm_1",), ("tm_3",)])

    assert plan == []


# ============================================================================
# Replanning (sample_test_4)
# ============================================================================


@given(flag_states())
@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
def test_replanning_after_failure(init_state):
    """
    Property: After blacklisting a failed action, replanning should find an alternative.
    Corresponds to sample_test_4.
    """
    actions = make_chain_actions()
    methods = Methods()

    def tm_1_1(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5)]

    def tm_1_2(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5), ("t_a", 5, 6)]

    methods.declare_task_methods("tm_1", [tm_1_1, tm_1_2])

    def tm_2_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3)]

    def tm_2_2(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3), ("t_a", 3, 7)]

    def tm_2_3(state):
        return [("t_a", 0, 1), ("t_a", 1, 3), ("t_a", 3, 7)]

    methods.declare_task_methods("tm_2", [tm_2_1, tm_2_2, tm_2_3])

    def tm_3_1(state):
        return [("t_a", 7, 8)]

    methods.declare_task_methods("tm_3", [tm_3_1])

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("tm_1",), ("tm_3",)])

    expected_0 = [
        ("t_a", 0, 1),
        ("t_a", 1, 2),
        ("t_a", 2, 3),
        ("t_a", 3, 7),
        ("t_a", 3, 4),
        ("t_a", 4, 5),
        ("t_a", 7, 8),
    ]
    assert plan == expected_0

    state_list = planner.simulate(init_state)
    fail_node = plan[2]
    after_fail_state = state_list[2]
    planner.blacklist_command(fail_node)

    fail_node_id = 0
    for node in planner.sol_tree.nodes:
        if planner.sol_tree.nodes[node]["info"] == fail_node:
            fail_node_id = node
            break

    plan = planner.replan(after_fail_state, fail_node_id)

    expected_1 = [
        ("t_a", 0, 1),
        ("t_a", 1, 3),
        ("t_a", 3, 7),
        ("t_a", 3, 4),
        ("t_a", 4, 5),
        ("t_a", 7, 8),
    ]
    assert plan == expected_1


# ============================================================================
# Replanning with More Methods (sample_test_5)
# ============================================================================


@given(flag_states())
@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
def test_replanning_with_extra_methods(init_state):
    """
    Property: Replanning should explore additional method alternatives.
    Corresponds to sample_test_5.
    """
    actions = make_chain_actions()
    methods = Methods()

    def tm_1_1(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5)]

    def tm_1_2(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5), ("t_a", 5, 6)]

    def tm_1_3(state):
        return [("tm_2",), ("t_a", 2, 4), ("t_a", 4, 5), ("t_a", 5, 6)]

    methods.declare_task_methods("tm_1", [tm_1_1, tm_1_2, tm_1_3])

    def tm_2_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3)]

    def tm_2_2(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3), ("t_a", 3, 7)]

    def tm_2_3(state):
        return [("t_a", 0, 1), ("t_a", 1, 3), ("t_a", 3, 7)]

    methods.declare_task_methods("tm_2", [tm_2_1, tm_2_2, tm_2_3])

    def tm_3_1(state):
        return [("t_a", 7, 8)]

    methods.declare_task_methods("tm_3", [tm_3_1])

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("tm_1",), ("tm_3",)])

    expected_0 = [
        ("t_a", 0, 1),
        ("t_a", 1, 2),
        ("t_a", 2, 3),
        ("t_a", 3, 7),
        ("t_a", 3, 4),
        ("t_a", 4, 5),
        ("t_a", 7, 8),
    ]
    assert plan == expected_0

    state_list = planner.simulate(init_state)
    fail_node = plan[4]
    after_fail_state = state_list[4]
    planner.blacklist_command(fail_node)

    fail_node_id = 0
    for node in planner.sol_tree.nodes:
        if planner.sol_tree.nodes[node]["info"] == fail_node:
            fail_node_id = node
            break

    plan = planner.replan(after_fail_state, fail_node_id)

    expected_1 = [
        ("t_a", 0, 1),
        ("t_a", 1, 2),
        ("t_a", 2, 3),
        ("t_a", 2, 4),
        ("t_a", 4, 5),
        ("t_a", 5, 6),
        ("t_a", 7, 8),
    ]
    assert plan == expected_1


# ============================================================================
# Replanning with Method Alternatives (sample_test_6)
# ============================================================================


@given(flag_states())
@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
def test_replanning_last_action_failure(init_state):
    """
    Property: Replanning when the last action fails should find an alternative method.
    Corresponds to sample_test_6.
    """
    actions = make_chain_actions()
    methods = Methods()

    def tm_1_1(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5)]

    def tm_1_2(state):
        return [("tm_2",), ("t_a", 3, 4), ("t_a", 4, 5), ("t_a", 5, 6)]

    def tm_1_3(state):
        return [("tm_2",), ("t_a", 2, 4), ("t_a", 4, 5), ("t_a", 5, 6)]

    methods.declare_task_methods("tm_1", [tm_1_1, tm_1_2, tm_1_3])

    def tm_2_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3)]

    def tm_2_2(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3), ("t_a", 3, 7)]

    def tm_2_3(state):
        return [("t_a", 0, 1), ("t_a", 1, 3), ("t_a", 3, 7)]

    methods.declare_task_methods("tm_2", [tm_2_1, tm_2_2, tm_2_3])

    def tm_3_1(state):
        return [("t_a", 7, 8)]

    def tm_3_2(state):
        return [("t_a", 7, 9)]

    methods.declare_task_methods("tm_3", [tm_3_1, tm_3_2])

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("tm_1",), ("tm_3",)])

    expected_0 = [
        ("t_a", 0, 1),
        ("t_a", 1, 2),
        ("t_a", 2, 3),
        ("t_a", 3, 7),
        ("t_a", 3, 4),
        ("t_a", 4, 5),
        ("t_a", 7, 8),
    ]
    assert plan == expected_0

    state_list = planner.simulate(init_state)
    fail_node = plan[-1]
    after_fail_state = state_list[-1]
    planner.blacklist_command(fail_node)

    fail_node_id = 0
    for node in planner.sol_tree.nodes:
        if planner.sol_tree.nodes[node]["info"] == fail_node:
            fail_node_id = node
            break

    plan = planner.replan(after_fail_state, fail_node_id)

    expected_1 = [("t_a", 7, 9)]
    assert plan == expected_1


# ============================================================================
# Replanning with Multiple Tasks (sample_test_7)
# ============================================================================


@given(flag_states())
@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
def test_replanning_multiple_tasks(init_state):
    """
    Property: Replanning with three top-level tasks should find correct alternative.
    Corresponds to sample_test_7.
    """
    actions = make_chain_actions()
    methods = Methods()

    def tm_1_1(state):
        return [("t_a", 3, 4), ("t_a", 4, 5)]

    def tm_1_2(state):
        return [("t_a", 3, 4), ("t_a", 4, 5), ("t_a", 5, 6)]

    def tm_1_3(state):
        return [("t_a", 2, 4), ("t_a", 4, 5), ("t_a", 5, 6)]

    methods.declare_task_methods("tm_1", [tm_1_1, tm_1_2, tm_1_3])

    def tm_2_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3)]

    def tm_2_2(state):
        return [("t_a", 0, 1), ("t_a", 1, 2), ("t_a", 2, 3), ("t_a", 3, 7)]

    def tm_2_3(state):
        return [("t_a", 0, 1), ("t_a", 1, 3), ("t_a", 3, 7)]

    methods.declare_task_methods("tm_2", [tm_2_1, tm_2_2, tm_2_3])

    def tm_3_1(state):
        return [("t_a", 6, 8), ("t_a", 7, 10)]

    def tm_3_2(state):
        return [("t_a", 7, 9)]

    methods.declare_task_methods("tm_3", [tm_3_1, tm_3_2])

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("tm_2",), ("tm_1",), ("tm_3",)])

    expected_0 = [
        ("t_a", 0, 1),
        ("t_a", 1, 2),
        ("t_a", 2, 3),
        ("t_a", 3, 7),
        ("t_a", 3, 4),
        ("t_a", 4, 5),
        ("t_a", 7, 9),
    ]
    assert plan == expected_0

    state_list = planner.simulate(init_state)
    fail_node = plan[-1]
    after_fail_state = state_list[-1]
    planner.blacklist_command(fail_node)

    fail_node_id = 0
    for node in planner.sol_tree.nodes:
        if planner.sol_tree.nodes[node]["info"] == fail_node:
            fail_node_id = node
            break

    plan = planner.replan(after_fail_state, fail_node_id)

    expected_1 = [
        ("t_a", 3, 4),
        ("t_a", 4, 5),
        ("t_a", 5, 6),
        ("t_a", 6, 8),
        ("t_a", 7, 10),
    ]
    assert plan == expected_1


# ============================================================================
# Generalized Properties
# ============================================================================


@given(flag_states_with_extra())
@settings(max_examples=50)
def test_plan_preserves_initial_state_immutability(init_state):
    """Property: Planning should not mutate the initial state."""
    import copy

    original_flags = copy.deepcopy(init_state.flag)

    actions = make_chain_actions()
    methods = Methods()

    def tm_1(state):
        return [("t_a", 0, 1), ("t_a", 1, 2)]

    methods.declare_task_methods("tm_1", [tm_1])

    planner = IPyHOP(methods, actions)
    planner.plan(init_state, [("tm_1",)])

    assert init_state.flag == original_flags


@given(st.integers(min_value=3, max_value=10))
@settings(max_examples=30)
def test_chain_plan_length_equals_chain_length(chain_len):
    """Property: A simple chain of N actions should produce a plan of length N."""
    actions = make_chain_actions()
    methods = Methods()

    def make_chain_method(n):
        def chain_method(state):
            return [("t_a", i, i + 1) for i in range(n)]

        return chain_method

    methods.declare_task_methods("chain", [make_chain_method(chain_len)])

    init_state = State("init_state")
    init_state.flag = {0: True}
    for i in range(1, chain_len + 1):
        init_state.flag[i] = False

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("chain",)])

    assert len(plan) == chain_len
    for i in range(chain_len):
        assert plan[i] == ("t_a", i, i + 1)


@given(st.integers(min_value=2, max_value=5))
@settings(max_examples=30)
def test_first_method_failure_triggers_backtrack(n_bad_methods):
    """Property: N failing methods before a good one should still find the plan."""
    actions = make_chain_actions()
    methods = Methods()

    method_list = []

    # Create n_bad_methods that will fail (gap in chain)
    for k in range(n_bad_methods):
        def make_bad(gap=k + 2):
            def bad_method(state):
                return [("t_a", 0, 1), ("t_a", gap, gap + 1)]

            return bad_method

        method_list.append(make_bad())

    # Good method: complete chain
    def good_method(state):
        return [("t_a", 0, 1), ("t_a", 1, 2)]

    method_list.append(good_method)

    methods.declare_task_methods("task", method_list)

    init_state = State("init_state")
    init_state.flag = {0: True}
    for i in range(1, 20):
        init_state.flag[i] = False

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("task",)])

    assert plan == [("t_a", 0, 1), ("t_a", 1, 2)]


@given(flag_states())
@settings(max_examples=50)
def test_empty_task_list_returns_empty_plan(init_state):
    """Property: An empty task list should produce an empty plan."""
    actions = make_chain_actions()
    methods = Methods()

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [])

    assert plan == []


@given(st.integers(min_value=2, max_value=4))
@settings(max_examples=20)
def test_multiple_sequential_tasks(n_tasks):
    """Property: Multiple sequential tasks should produce a concatenated plan."""
    actions = make_chain_actions()
    methods = Methods()

    # Each task advances 2 flags: task_i covers [2*i, 2*i+2]
    for i in range(n_tasks):
        start = 2 * i

        def make_method(s=start):
            def method(state):
                return [("t_a", s, s + 1), ("t_a", s + 1, s + 2)]

            return method

        methods.declare_task_methods(f"task_{i}", [make_method()])

    init_state = State("init_state")
    init_state.flag = {0: True}
    for i in range(1, 2 * n_tasks + 1):
        init_state.flag[i] = False

    planner = IPyHOP(methods, actions)
    task_list = [(f"task_{i}",) for i in range(n_tasks)]
    plan = planner.plan(init_state, task_list)

    assert len(plan) == 2 * n_tasks
    for i in range(n_tasks):
        start = 2 * i
        assert plan[2 * i] == ("t_a", start, start + 1)
        assert plan[2 * i + 1] == ("t_a", start + 1, start + 2)


# ============================================================================
# Edge Cases
# ============================================================================


def test_single_action_plan():
    """A single action task should produce a single-step plan."""
    actions = make_chain_actions()
    methods = Methods()

    def single(state):
        return [("t_a", 0, 1)]

    methods.declare_task_methods("single", [single])

    init_state = State("init_state")
    init_state.flag = {0: True, 1: False}

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("single",)])

    assert plan == [("t_a", 0, 1)]


def test_all_methods_fail_returns_empty():
    """When all methods fail, the planner should return an empty list."""
    actions = make_chain_actions()
    methods = Methods()

    def bad_1(state):
        return [("t_a", 5, 6)]

    def bad_2(state):
        return [("t_a", 7, 8)]

    methods.declare_task_methods("impossible", [bad_1, bad_2])

    init_state = State("init_state")
    init_state.flag = {0: True}
    for i in range(1, 20):
        init_state.flag[i] = False

    planner = IPyHOP(methods, actions)
    plan = planner.plan(init_state, [("impossible",)])

    assert plan == []


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
