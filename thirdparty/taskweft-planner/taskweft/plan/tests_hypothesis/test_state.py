#!/usr/bin/env python
"""
Property-based tests for State class with temporal extensions using Hypothesis.
Tests state creation, temporal tracking, and timeline management.
"""

import hypothesis.strategies as st
import pytest
from hypothesis import HealthCheck, given, settings

from ipyhop.state import State
from ipyhop.temporal.utils import parse_iso8601_datetime

# ============================================================================
# Strategies
# ============================================================================


@st.composite
def state_names(draw):
    """Generate valid state names."""
    return draw(
        st.text(alphabet=st.characters(whitelist_categories=("Ll", "Lu", "Nd")), min_size=1, max_size=20).filter(
            lambda x: x[0].isalpha()
        )
    )


@st.composite
def state_variables(draw):
    """Generate state variable assignments."""
    n_vars = draw(st.integers(0, 10))
    vars_dict = {}
    for _ in range(n_vars):
        name = draw(
            st.text(alphabet=st.characters(whitelist_categories=("Ll", "Lu", "Nd")), min_size=1, max_size=15).filter(
                lambda x: x[0].isalpha()
            )
        )
        value_type = draw(st.sampled_from(["int", "float", "str", "bool", "list", "dict"]))

        if value_type == "int":
            vars_dict[name] = draw(st.integers(-1000, 1000))
        elif value_type == "float":
            vars_dict[name] = draw(st.floats(-1000.0, 1000.0, allow_infinity=False, allow_nan=False))
        elif value_type == "str":
            vars_dict[name] = draw(st.text(min_size=0, max_size=20))
        elif value_type == "bool":
            vars_dict[name] = draw(st.booleans())
        elif value_type == "list":
            vars_dict[name] = draw(st.lists(st.integers(-100, 100), max_size=5))
        elif value_type == "dict":
            vars_dict[name] = {"key1": draw(st.integers(0, 100)), "key2": draw(st.text(min_size=0, max_size=10))}
    return vars_dict


@st.composite
def action_tuples(draw):
    """Generate action tuples."""
    action_name = draw(
        st.text(
            alphabet=st.characters(whitelist_categories=("Ll", "Lu", "Nd"), whitelist_characters="_"),
            min_size=1,
            max_size=20,
        ).filter(lambda x: x[0].isalpha())
    )
    num_args = draw(st.integers(0, 5))
    args = [draw(st.text(min_size=0, max_size=10)) for _ in range(num_args)]
    return (action_name,) + tuple(args)


@st.composite
def valid_iso8601_datetimes(draw):
    """Generate valid ISO 8601 datetime strings."""
    year = draw(st.integers(2000, 2100))
    month = draw(st.integers(1, 12))
    day = draw(st.integers(1, 28))
    hour = draw(st.integers(0, 23))
    minute = draw(st.integers(0, 59))
    second = draw(st.integers(0, 59))
    return f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z"


# ============================================================================
# Constructor Tests
# ============================================================================


@given(state_names())
@settings(max_examples=100)
def test_constructor_creates_state(name):
    """Constructor should create a state with the given name."""
    state = State(name)
    assert state.__name__ == name
    # Should have temporal attributes
    assert hasattr(state, "_current_time")
    assert hasattr(state, "_timeline")
    assert state.get_current_time() is not None


@given(state_names(), valid_iso8601_datetimes())
@settings(max_examples=100)
def test_constructor_with_initial_time(name, initial_time):
    """Constructor should accept initial_time parameter."""
    state = State(name, initial_time=initial_time)
    assert state.get_current_time() == initial_time
    assert state._initial_time_set is True


@given(state_names())
@settings(max_examples=50)
def test_constructor_auto_generates_time(name):
    """Constructor without initial_time should auto-generate time."""
    state = State(name)
    current_time = state.get_current_time()
    assert current_time is not None
    # Should be parseable
    parsed = parse_iso8601_datetime(current_time)
    assert parsed is not None
    # Should be marked as auto-generated
    assert state._initial_time_set is False


# ============================================================================
# Variable Assignment Tests
# ============================================================================


@given(state_names(), state_variables())
@settings(max_examples=100)
def test_variable_assignment(name, variables):
    """State should support dynamic variable assignment."""
    state = State(name)
    for var_name, var_value in variables.items():
        setattr(state, var_name, var_value)
        assert getattr(state, var_name) == var_value


@given(state_names(), state_variables())
@settings(max_examples=100)
def test_variable_assignment_preserves_time(name, variables):
    """Variable assignment should not affect temporal state."""
    state = State(name, initial_time="2025-01-01T10:00:00Z")
    original_time = state.get_current_time()

    for var_name, var_value in variables.items():
        setattr(state, var_name, var_value)

    assert state.get_current_time() == original_time


# ============================================================================
# Temporal Methods Tests
# ============================================================================


@given(state_names(), valid_iso8601_datetimes())
@settings(max_examples=100)
def test_set_current_time(name, new_time):
    """set_current_time should update the current time."""
    state = State(name)
    state.set_current_time(new_time)
    assert state.get_current_time() == new_time


@given(state_names())
@settings(max_examples=50)
def test_get_current_time_returns_string(name):
    """get_current_time should return a string."""
    state = State(name)
    time_str = state.get_current_time()
    assert isinstance(time_str, str)
    assert len(time_str) > 0


# ============================================================================
# Timeline Tests
# ============================================================================


@given(state_names(), action_tuples(), valid_iso8601_datetimes(), valid_iso8601_datetimes())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_add_to_timeline(name, action, start_time, end_time):
    """add_to_timeline should add action to timeline."""
    state = State(name)
    state.add_to_timeline(action, start_time, end_time)

    timeline = state.get_timeline()
    assert len(timeline) == 1
    assert timeline[0] == (action, start_time, end_time)


@given(state_names())
@settings(max_examples=100)
def test_add_multiple_to_timeline(name):
    """Multiple actions should be added to timeline in order."""
    state = State(name)

    actions = [
        (("move", "a", "b"), "2025-01-01T10:00:00Z", "2025-01-01T10:05:00Z"),
        (("move", "b", "c"), "2025-01-01T10:05:00Z", "2025-01-01T10:10:00Z"),
        (("grab", "obj1"), "2025-01-01T10:10:00Z", "2025-01-01T10:11:00Z"),
    ]

    for action, start, end in actions:
        state.add_to_timeline(action, start, end)

    timeline = state.get_timeline()
    assert len(timeline) == 3
    for i, (action, start, end) in enumerate(actions):
        assert timeline[i] == (action, start, end)


@given(state_names(), action_tuples(), valid_iso8601_datetimes(), valid_iso8601_datetimes())
@settings(max_examples=100)
def test_clear_timeline(name, action, start_time, end_time):
    """clear_timeline should empty the timeline."""
    state = State(name)
    state.add_to_timeline(action, start_time, end_time)
    assert len(state.get_timeline()) == 1

    state.clear_timeline()
    assert len(state.get_timeline()) == 0


@given(state_names(), action_tuples(), valid_iso8601_datetimes(), valid_iso8601_datetimes())
@settings(max_examples=100)
def test_get_timeline_returns_copy(name, action, start_time, end_time):
    """get_timeline should return a copy, not the original."""
    state = State(name)
    state.add_to_timeline(action, start_time, end_time)

    timeline1 = state.get_timeline()
    timeline2 = state.get_timeline()

    assert timeline1 == timeline2
    assert timeline1 is not timeline2

    # Modifying copy shouldn't affect original
    timeline1.append((("fake",), "0000-00-00T00:00:00Z", "0000-00-00T00:00:00Z"))
    assert len(state.get_timeline()) == 1


# ============================================================================
# Copy Tests
# ============================================================================


@given(state_names(), state_variables())
@settings(max_examples=100)
def test_copy_creates_independent_copy(name, variables):
    """copy() should create an independent deep copy."""
    state1 = State(name, initial_time="2025-01-01T10:00:00Z")

    # Set variables
    for var_name, var_value in variables.items():
        setattr(state1, var_name, var_value)

    # Add to timeline
    state1.add_to_timeline(("action1",), "2025-01-01T10:00:00Z", "2025-01-01T10:05:00Z")

    state2 = state1.copy()

    # Values should match
    assert state2.__name__ == state1.__name__
    assert state2.get_current_time() == state1.get_current_time()
    assert state2.get_timeline() == state1.get_timeline()

    for var_name in variables:
        assert getattr(state2, var_name) == getattr(state1, var_name)

    # Modifications should be independent
    state2.set_current_time("2025-01-02T10:00:00Z")
    assert state1.get_current_time() != state2.get_current_time()

    state2.add_to_timeline(("action2",), "2025-01-01T10:05:00Z", "2025-01-01T10:10:00Z")
    assert len(state1.get_timeline()) != len(state2.get_timeline())


@given(state_names())
@settings(max_examples=50)
def test_copy_preserves_nested_structures(name):
    """copy() should deep copy nested structures."""
    state1 = State(name)
    state1.nested_dict = {"key": {"inner": [1, 2, 3]}}
    state1.nested_list = [[1, 2], [3, 4]]

    state2 = state1.copy()

    # Modify nested structures in copy
    state2.nested_dict["key"]["inner"].append(4)
    state2.nested_list[0].append(3)

    # Original should be unchanged
    assert state1.nested_dict["key"]["inner"] == [1, 2, 3]
    assert state1.nested_list[0] == [1, 2]


# ============================================================================
# Update Tests
# ============================================================================


@given(state_names(), state_names(), state_variables())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_update_merges_variables(name1, name2, variables):
    """update() should merge variables from another state."""
    state1 = State(name1)
    state2 = State(name2)

    for var_name, var_value in variables.items():
        setattr(state2, var_name, var_value)

    state1.update(state2)

    for var_name, var_value in variables.items():
        assert getattr(state1, var_name) == var_value


@given(state_names(), state_variables())
@settings(max_examples=50)
def test_update_returns_self(name, variables):
    """update() should return self for chaining."""
    state1 = State(name)
    state2 = State("source")

    for var_name, var_value in variables.items():
        setattr(state2, var_name, var_value)

    result = state1.update(state2)
    assert result is state1


# ============================================================================
# String Representation Tests
# ============================================================================


@given(state_names(), state_variables())
@settings(max_examples=50)
def test_str_repr_includes_variables(name, variables):
    """__str__ should include variable assignments."""
    state = State(name)

    # State always has internal attributes (_current_time, _timeline, __name__),
    # so it is always truthy and __str__ always returns the formatted string.
    # Even an "empty" state (no user variables) still has those internal attrs.
    str_repr = str(state)
    assert isinstance(str_repr, str)
    assert name in str_repr

    for var_name, var_value in variables.items():
        setattr(state, var_name, var_value)

    str_repr = str(state)
    assert isinstance(str_repr, str)
    assert name in str_repr

    for var_name in variables:
        assert var_name in str_repr


def test_repr_format():
    """__repr__ should have consistent format."""
    state = State("test_state")
    repr_str = repr(state)
    assert "<class" in repr_str
    assert "State" in repr_str
    assert "test_state" in repr_str


# ============================================================================
# Property: Timeline Order Preservation
# ============================================================================


@given(state_names(), st.integers(1, 20))
@settings(max_examples=100)
def test_timeline_order_preserved(name, n_actions):
    """
    Property: Actions added to timeline should be retrievable in the same order.
    """
    state = State(name)

    actions_added = []

    for i in range(n_actions):
        action = (f"action_{i}", f"arg_{i}")
        start = f"2025-01-01T{10+i:02d}:00:00Z"
        end = f"2025-01-01T{10+i+1:02d}:00:00Z"
        actions_added.append((action, start, end))
        state.add_to_timeline(action, start, end)

    timeline = state.get_timeline()
    assert len(timeline) == n_actions

    for i, expected in enumerate(actions_added):
        assert timeline[i] == expected


# ============================================================================
# Property: Time Monotonicity (Optional Constraint)
# ============================================================================


@given(state_names())
@settings(max_examples=100)
def test_can_set_arbitrary_times(name):
    """
    State should allow setting arbitrary times (not enforcing monotonicity).
    This is a design choice - the state doesn't enforce time ordering.
    """
    state = State(name)

    # Set time forward
    state.set_current_time("2025-01-01T12:00:00Z")
    assert state.get_current_time() == "2025-01-01T12:00:00Z"

    # Can set time backward
    state.set_current_time("2025-01-01T10:00:00Z")
    assert state.get_current_time() == "2025-01-01T10:00:00Z"


# ============================================================================
# Edge Cases
# ============================================================================


def test_empty_state():
    """Empty state should work correctly."""
    state = State("empty")
    assert state.__name__ == "empty"
    assert state.get_current_time() is not None
    assert state.get_timeline() == []
    # State is always truthy (has internal attributes), so __str__ returns
    # the formatted attribute listing, never "False".
    str_repr = str(state)
    assert isinstance(str_repr, str)
    assert "empty" in str_repr


def test_state_with_special_chars_in_name():
    """State name with underscores should work."""
    state = State("my_test_state_123")
    assert state.__name__ == "my_test_state_123"


@given(state_names())
@settings(max_examples=50)
def test_timeline_with_empty_action(name):
    """Timeline should handle actions with no arguments."""
    state = State(name)
    action = ("simple_action",)
    state.add_to_timeline(action, "2025-01-01T10:00:00Z", "2025-01-01T10:05:00Z")

    timeline = state.get_timeline()
    assert len(timeline) == 1
    assert timeline[0][0] == action


@given(state_names())
@settings(max_examples=50)
def test_many_variables(name):
    """State should handle many variables."""
    state = State(name)

    for i in range(100):
        setattr(state, f"var_{i}", i)

    for i in range(100):
        assert getattr(state, f"var_{i}") == i


# ============================================================================
# Integration: State with Complex Workflows
# ============================================================================


@given(state_names())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_state_workflow_simulation(name):
    """
    Property: Simulate a planning workflow with state updates and timeline tracking.
    """
    # Initial state
    state = State(name, initial_time="2025-01-01T08:00:00Z")
    state.location = "home"
    state.inventory = []

    # Action 1: Move to store
    state.location = "store"
    state.add_to_timeline(("move", "home", "store"), "2025-01-01T08:00:00Z", "2025-01-01T08:10:00Z")

    # Action 2: Buy item
    state.inventory.append("item1")
    state.add_to_timeline(("buy", "item1"), "2025-01-01T08:10:00Z", "2025-01-01T08:12:00Z")

    # Verify state
    assert state.location == "store"
    assert state.inventory == ["item1"]
    assert len(state.get_timeline()) == 2

    # Copy and continue from copy
    state_copy = state.copy()
    state_copy.location = "home"
    state_copy.add_to_timeline(("move", "store", "home"), "2025-01-01T08:12:00Z", "2025-01-01T08:22:00Z")

    # Original unchanged
    assert state.location == "store"
    assert len(state.get_timeline()) == 2

    # Copy has new state
    assert state_copy.location == "home"
    assert len(state_copy.get_timeline()) == 3


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
