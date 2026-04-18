#!/usr/bin/env python
"""
Property-based tests for Methods class using Hypothesis.
Tests method declaration for tasks, goals, and multigoals.
"""

import hypothesis.strategies as st
import pytest
from hypothesis import HealthCheck, assume, given, settings

from ipyhop.methods import Methods, _goals_not_achieved, mgm_split_multigoal
from ipyhop.multigoal import MultiGoal
from ipyhop.state import State

# ============================================================================
# Strategies
# ============================================================================


@st.composite
def method_functions(draw):
    """Generate simple method functions."""
    n_methods = draw(st.integers(1, 5))

    def make_method():
        def method(state, *args):
            # Return a simple subtask list
            return [("subtask",) + args]

        return method

    return [make_method() for _ in range(n_methods)]


@st.composite
def task_names(draw):
    """Generate valid task names."""
    return draw(
        st.text(alphabet=st.characters(whitelist_categories=("Ll", "Lu", "Nd"), whitelist_characters="_"), min_size=1, max_size=20).filter(
            lambda x: x[0].isalpha()
        )
    )


@st.composite
def goal_names(draw):
    """Generate valid goal names."""
    return draw(
        st.text(alphabet=st.characters(whitelist_categories=("Ll", "Lu", "Nd"), whitelist_characters="_"), min_size=1, max_size=20).filter(
            lambda x: x[0].isalpha()
        )
    )


@st.composite
def multigoal_tags(draw):
    """Generate multigoal tags (string or None)."""
    if draw(st.booleans()):
        return draw(
            st.text(
                alphabet=st.characters(whitelist_categories=("Ll", "Lu", "Nd"), whitelist_characters="_"), min_size=1, max_size=20
            ).filter(lambda x: x[0].isalpha())
        )
    return None


# ============================================================================
# Constructor Tests
# ============================================================================


def test_constructor_initializes_dicts():
    """Constructor should initialize empty dictionaries."""
    methods = Methods()
    assert methods.task_method_dict == {}
    assert methods.goal_method_dict == {}
    assert methods.multigoal_method_dict == {None: []}


# ============================================================================
# declare_task_methods() Tests
# ============================================================================


@given(task_names(), method_functions())
@settings(max_examples=100)
def test_declare_task_methods_registers_methods(task_name, method_list):
    """declare_task_methods should register methods for a task."""
    methods = Methods()
    methods.declare_task_methods(task_name, method_list)

    assert task_name in methods.task_method_dict
    assert methods.task_method_dict[task_name] == method_list


@given(st.integers(), method_functions())
@settings(max_examples=50)
def test_declare_task_methods_requires_string_task_name(non_string, method_list):
    """declare_task_methods should require string task name."""
    methods = Methods()
    with pytest.raises(AssertionError):
        methods.declare_task_methods(non_string, method_list)


@given(task_names(), st.integers())
@settings(max_examples=50)
def test_declare_task_methods_requires_list(task_name, non_list):
    """declare_task_methods should require list of methods."""
    methods = Methods()
    with pytest.raises(AssertionError):
        methods.declare_task_methods(task_name, non_list)


@given(task_names(), st.lists(st.integers(), min_size=1))
@settings(max_examples=50)
def test_declare_task_methods_requires_callable_methods(task_name, non_callable_list):
    """declare_task_methods should require callable methods."""
    methods = Methods()
    with pytest.raises(AssertionError):
        methods.declare_task_methods(task_name, non_callable_list)


@given(task_names(), method_functions(), method_functions())
@settings(max_examples=50)
def test_declare_task_methods_overwrites_existing(task_name, method_list1, method_list2):
    """declare_task_methods should overwrite existing methods for same task."""
    methods = Methods()
    methods.declare_task_methods(task_name, method_list1)
    methods.declare_task_methods(task_name, method_list2)

    assert methods.task_method_dict[task_name] == method_list2


# ============================================================================
# declare_goal_methods() Tests
# ============================================================================


@given(goal_names(), method_functions())
@settings(max_examples=100)
def test_declare_goal_methods_registers_methods(goal_name, method_list):
    """declare_goal_methods should register methods for a goal."""
    methods = Methods()
    methods.declare_goal_methods(goal_name, method_list)

    assert goal_name in methods.goal_method_dict
    assert methods.goal_method_dict[goal_name] == method_list


@given(st.integers(), method_functions())
@settings(max_examples=50)
def test_declare_goal_methods_requires_string_goal_name(non_string, method_list):
    """declare_goal_methods should require string goal name."""
    methods = Methods()
    with pytest.raises(AssertionError):
        methods.declare_goal_methods(non_string, method_list)


@given(goal_names(), st.lists(st.integers(), min_size=1))
@settings(max_examples=50)
def test_declare_goal_methods_requires_list(goal_name, non_callable_list):
    """declare_goal_methods should require list of callable methods."""
    methods = Methods()
    with pytest.raises(AssertionError):
        methods.declare_goal_methods(goal_name, non_callable_list)


# ============================================================================
# declare_multigoal_methods() Tests
# ============================================================================


@given(multigoal_tags(), method_functions())
@settings(max_examples=100)
def test_declare_multigoal_methods_registers_methods(multigoal_tag, method_list):
    """declare_multigoal_methods should register methods for a multigoal."""
    methods = Methods()
    methods.declare_multigoal_methods(multigoal_tag, method_list)

    assert multigoal_tag in methods.multigoal_method_dict
    assert methods.multigoal_method_dict[multigoal_tag] == method_list


@given(st.integers(), method_functions())
@settings(max_examples=50)
def test_declare_multigoal_methods_requires_string_or_none_tag(int_tag, method_list):
    """declare_multigoal_methods should require string or None tag."""
    methods = Methods()
    with pytest.raises(AssertionError):
        methods.declare_multigoal_methods(int_tag, method_list)


@given(multigoal_tags(), st.lists(st.integers(), min_size=1))
@settings(max_examples=50)
def test_declare_multigoal_methods_requires_list(multigoal_tag, non_callable_list):
    """declare_multigoal_methods should require list of callable methods."""
    methods = Methods()
    with pytest.raises(AssertionError):
        methods.declare_multigoal_methods(multigoal_tag, non_callable_list)


# ============================================================================
# String Representation Tests
# ============================================================================


@given(task_names(), method_functions(), goal_names(), method_functions())
@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
def test_str_includes_all_method_types(task_name, task_methods, goal_name, goal_methods):
    """__str__ should include task, goal, and multigoal methods."""
    methods = Methods()
    methods.declare_task_methods(task_name, task_methods)
    methods.declare_goal_methods(goal_name, goal_methods)
    methods.declare_multigoal_methods(None, task_methods)

    str_repr = str(methods)
    assert "TASK:" in str_repr
    assert "GOAL:" in str_repr
    assert "MULTIGOAL:" in str_repr
    assert task_name in str_repr
    assert goal_name in str_repr


def test_repr_equals_str():
    """__repr__ should equal __str__."""
    methods = Methods()

    def dummy_method(state, *args):
        return []

    methods.declare_task_methods("test_task", [dummy_method])

    assert repr(methods) == str(methods)


# ============================================================================
# _goals_not_achieved() Tests
# ============================================================================


@given(
    st.integers(1, 10),  # n_achieved
    st.integers(0, 5),  # n_unachieved
)
@settings(max_examples=100)
def test_goals_not_achieved_identifies_unachieved(n_achieved, n_unachieved):
    """_goals_not_achieved should correctly identify unachieved goals."""
    # Create state with achieved goals
    state = State("test_state")
    state.loc = {}

    # Create multigoal with some achieved, some not
    multigoal = MultiGoal("test_mg")
    multigoal.loc = {}

    # Set achieved goals
    for i in range(n_achieved):
        key = f"obj_{i}"
        value = f"loc_{i}"
        state.loc[key] = value
        multigoal.loc[key] = value

    # Set unachieved goals
    for i in range(n_unachieved):
        key = f"obj_{n_achieved + i}"
        state_loc = f"current_{i}"
        desired_loc = f"desired_{i}"
        state.loc[key] = state_loc
        multigoal.loc[key] = desired_loc

    unachieved = _goals_not_achieved(state, multigoal)

    # Should have exactly n_unachieved unachieved goals
    if "loc" in unachieved:
        assert len(unachieved["loc"]) == n_unachieved
    else:
        assert n_unachieved == 0


def test_goals_not_achieved_all_achieved():
    """_goals_not_achieved should return empty dict when all goals achieved."""
    state = State("test_state")
    state.loc = {"obj1": "room1", "obj2": "room2"}

    multigoal = MultiGoal("test_mg")
    multigoal.loc = {"obj1": "room1", "obj2": "room2"}

    unachieved = _goals_not_achieved(state, multigoal)
    assert unachieved == {}


def test_goals_not_achieved_none_achieved():
    """_goals_not_achieved should return all goals when none achieved."""
    state = State("test_state")
    state.loc = {"obj1": "room1", "obj2": "room2"}

    multigoal = MultiGoal("test_mg")
    multigoal.loc = {"obj1": "room3", "obj2": "room4"}

    unachieved = _goals_not_achieved(state, multigoal)

    assert "loc" in unachieved
    assert unachieved["loc"]["obj1"] == "room3"
    assert unachieved["loc"]["obj2"] == "room4"


# ============================================================================
# mgm_split_multigoal() Tests
# ============================================================================


@given(
    st.integers(1, 5),  # n_goals
)
@settings(max_examples=100)
def test_mgm_split_multigoal_splits_unachieved(n_goals):
    """mgm_split_multigoal should split unachieved goals into list."""
    state = State("test_state")
    state.loc = {}

    multigoal = MultiGoal("test_mg")
    multigoal.loc = {}

    # Set some achieved, some not
    for i in range(n_goals):
        key = f"obj_{i}"
        if i < n_goals // 2:
            # Achieved
            value = f"loc_{i}"
            state.loc[key] = value
            multigoal.loc[key] = value
        else:
            # Not achieved
            state.loc[key] = f"current_{i}"
            multigoal.loc[key] = f"desired_{i}"

    result = mgm_split_multigoal(state, multigoal)

    # Should return list of unachieved goals + multigoal
    assert isinstance(result, list)

    # Count unachieved goals in result
    unachieved_count = n_goals - (n_goals // 2)
    if unachieved_count > 0:
        # Should have unachieved goals + multigoal at end
        assert len(result) == unachieved_count + 1
        assert result[-1] == multigoal
    else:
        # All achieved, empty list
        assert result == []


def test_mgm_split_multigoal_all_achieved():
    """mgm_split_multigoal should return empty list when all achieved."""
    state = State("test_state")
    state.loc = {"obj1": "room1"}

    multigoal = MultiGoal("test_mg")
    multigoal.loc = {"obj1": "room1"}

    result = mgm_split_multigoal(state, multigoal)
    assert result == []


# ============================================================================
# Property: Method Dictionary Consistency
# ============================================================================


@given(task_names(), method_functions())
@settings(max_examples=100)
def test_task_method_dict_consistency(task_name, method_list):
    """
    Property: After declaring task methods, the dict should contain exactly those methods.
    """
    methods = Methods()
    methods.declare_task_methods(task_name, method_list)

    assert task_name in methods.task_method_dict
    assert len(methods.task_method_dict[task_name]) == len(method_list)
    for i, method in enumerate(method_list):
        assert methods.task_method_dict[task_name][i] == method


# ============================================================================
# Edge Cases
# ============================================================================


def test_empty_method_list():
    """Empty method list should be allowed (though unusual)."""
    methods = Methods()
    methods.declare_task_methods("empty_task", [])
    assert methods.task_method_dict["empty_task"] == []


def test_single_method():
    """Single method should work correctly."""

    def single_method(state, *args):
        return []

    methods = Methods()
    methods.declare_task_methods("single_task", [single_method])

    assert len(methods.task_method_dict["single_task"]) == 1


def test_many_tasks():
    """Many tasks should be handled correctly."""
    methods = Methods()

    def dummy_method(state, *args):
        return []

    for i in range(100):
        methods.declare_task_methods(f"task_{i}", [dummy_method])

    assert len(methods.task_method_dict) == 100


def test_multigoal_with_none_tag():
    """None tag should work for multigoals."""
    methods = Methods()

    def dummy_method(state, *args):
        return []

    methods.declare_multigoal_methods(None, [dummy_method])
    assert None in methods.multigoal_method_dict


# ============================================================================
# Integration: Full Methods Object
# ============================================================================


@given(task_names(), method_functions(), goal_names(), method_functions(), multigoal_tags(), method_functions())
@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
def test_full_methods_object(task_name, task_methods, goal_name, goal_methods, mg_tag, mg_methods):
    """Should support all method types in one Methods object."""
    methods = Methods()

    methods.declare_task_methods(task_name, task_methods)
    methods.declare_goal_methods(goal_name, goal_methods)
    methods.declare_multigoal_methods(mg_tag, mg_methods)

    # Verify all registered
    assert task_name in methods.task_method_dict
    assert goal_name in methods.goal_method_dict
    assert mg_tag in methods.multigoal_method_dict

    # Verify counts
    assert len(methods.task_method_dict[task_name]) == len(task_methods)
    assert len(methods.goal_method_dict[goal_name]) == len(goal_methods)
    assert len(methods.multigoal_method_dict[mg_tag]) == len(mg_methods)


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
