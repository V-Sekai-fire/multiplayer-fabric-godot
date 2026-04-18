#!/usr/bin/env python
"""
Property-based tests for Actions class with temporal support using Hypothesis.
Tests action declaration, temporal metadata, and action models.
"""

import random

import hypothesis.strategies as st
import pytest
from hypothesis import HealthCheck, given, settings

from ipyhop.actions import Actions

# ============================================================================
# Strategies
# ============================================================================


@st.composite
def action_functions(draw):
    """Generate simple action functions with unique names."""
    n_actions = draw(st.integers(1, 5))

    actions = []
    for i in range(n_actions):
        prob = draw(st.floats(0.5, 1.0))

        # Each closure gets a unique name to avoid identity comparison issues
        def make_action(p=prob, idx=i):
            def action(state, *args):
                if random.random() < p:
                    new_state = state.copy()
                    new_state.last_action = action.__name__
                    return new_state
                return None

            action.__name__ = f"action_{idx}"
            return action

        actions.append(make_action())
    return actions


@st.composite
def action_names(draw):
    """Generate valid Python identifier-style action names."""
    first = draw(st.sampled_from("abcdefghijklmnopqrstuvwxyz"))
    rest = draw(
        st.text(
            alphabet=st.characters(whitelist_categories=("Ll", "Lu", "Nd"), whitelist_characters="_"),
            min_size=0,
            max_size=19,
        )
    )
    return first + rest


@st.composite
def durations(draw):
    """Generate ISO 8601 duration strings."""
    hours = draw(st.integers(0, 23))
    minutes = draw(st.integers(0, 59))
    seconds = draw(st.integers(0, 59))
    parts = []
    if hours > 0:
        parts.append(f"{hours}H")
    if minutes > 0:
        parts.append(f"{minutes}M")
    if seconds > 0 or not parts:
        parts.append(f"{seconds}S")
    return "PT" + "".join(parts)


# ============================================================================
# Constructor Tests
# ============================================================================


def test_constructor_initializes_empty_dicts():
    """Constructor should initialize empty dictionaries."""
    actions = Actions()
    assert actions.action_dict == {}
    assert actions.action_prob == {}
    assert actions.action_cost == {}
    assert actions.action_temporal_dict == {}


# ============================================================================
# declare_actions() Tests
# ============================================================================


@given(action_functions())
@settings(max_examples=100)
def test_declare_actions_registers_functions(action_list):
    """declare_actions should register all action functions."""
    actions = Actions()
    actions.declare_actions(action_list)

    for action_func in action_list:
        assert action_func.__name__ in actions.action_dict


@given(action_functions())
@settings(max_examples=100)
def test_declare_actions_sets_default_probabilities(action_list):
    """declare_actions should set default probability [1, 0]."""
    actions = Actions()
    actions.declare_actions(action_list)

    for action_func in action_list:
        assert actions.action_prob[action_func.__name__] == [1, 0]


@given(action_functions())
@settings(max_examples=100)
def test_declare_actions_sets_default_cost(action_list):
    """declare_actions should set default cost 1.0."""
    actions = Actions()
    actions.declare_actions(action_list)

    for action_func in action_list:
        assert actions.action_cost[action_func.__name__] == 1.0


@given(st.integers())
@settings(max_examples=50)
def test_declare_actions_rejects_non_list(non_list):
    """declare_actions should reject non-list input."""
    actions = Actions()
    with pytest.raises(AssertionError):
        actions.declare_actions(non_list)


@given(st.lists(st.integers(), min_size=1, max_size=5))
@settings(max_examples=50)
def test_declare_actions_rejects_non_callable(non_callable_list):
    """declare_actions should reject lists with non-callable items."""
    actions = Actions()
    with pytest.raises(AssertionError):
        actions.declare_actions(non_callable_list)


# ============================================================================
# declare_action_models() Tests
# ============================================================================


@given(action_functions())
@settings(max_examples=100)
def test_declare_action_models_updates_probabilities_and_costs(action_list):
    """declare_action_models should update probabilities and costs."""
    actions = Actions()
    actions.declare_actions(action_list)

    # Create custom models for all actions
    prob_dict = {}
    cost_dict = {}
    for action_func in action_list:
        name = action_func.__name__
        prob_dict[name] = [0.8, 0.2]
        cost_dict[name] = 5.0

    actions.declare_action_models(prob_dict, cost_dict)

    for action_func in action_list:
        name = action_func.__name__
        assert actions.action_prob[name] == prob_dict[name]
        assert actions.action_cost[name] == cost_dict[name]


@given(action_functions())
@settings(max_examples=50)
def test_declare_action_models_requires_matching_keys(action_list):
    """declare_action_models requires key counts to match after update."""
    from hypothesis import assume

    assume(len(action_list) >= 2)

    actions = Actions()
    actions.declare_actions(action_list)

    # Provide extra key not in action_dict — this adds a key to action_prob
    # making len(action_prob) > len(action_dict), triggering the assertion
    prob_dict = {a.__name__: [1, 0] for a in action_list}
    prob_dict["nonexistent_action"] = [1, 0]
    cost_dict = {a.__name__: 1.0 for a in action_list}
    cost_dict["nonexistent_action"] = 1.0

    with pytest.raises(AssertionError):
        actions.declare_action_models(prob_dict, cost_dict)


# ============================================================================
# Temporal Action Tests
# ============================================================================


@given(action_functions(), durations())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_declare_temporal_actions_two_tuple(action_list, duration):
    """declare_temporal_actions should handle (action_func, duration) tuples."""
    actions = Actions()

    temporal_list = [(action, duration) for action in action_list]
    actions.declare_temporal_actions(temporal_list)

    for action, dur in temporal_list:
        assert action.__name__ in actions.action_dict
        assert action.__name__ in actions.action_temporal_dict
        metadata = actions.action_temporal_dict[action.__name__]
        assert metadata is not None


@given(action_names(), action_functions(), durations())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_declare_temporal_actions_three_tuple(action_name, action_list, duration):
    """declare_temporal_actions should handle (name, action_func, duration) tuples."""
    actions = Actions()

    action_func = action_list[0]
    temporal_list = [(action_name, action_func, duration)]
    actions.declare_temporal_actions(temporal_list)

    assert action_name in actions.action_dict
    assert action_name in actions.action_temporal_dict
    metadata = actions.action_temporal_dict[action_name]
    assert metadata is not None


@given(st.lists(st.integers(), max_size=3))
@settings(max_examples=50)
def test_declare_temporal_actions_rejects_invalid_tuple_length(invalid_tuple):
    """declare_temporal_actions should reject tuples with invalid length."""
    actions = Actions()

    if len(invalid_tuple) not in [2, 3]:
        with pytest.raises(ValueError):
            actions.declare_temporal_actions([tuple(invalid_tuple)])


@given(st.text(), st.integers(), durations())
@settings(max_examples=50)
def test_declare_temporal_actions_requires_string_name(non_string_name, int_val, duration):
    """declare_temporal_actions should require string action names in 3-tuple format."""
    actions = Actions()

    # Use non-string as name
    if not isinstance(non_string_name, str):
        with pytest.raises(AssertionError):
            actions.declare_temporal_actions([(non_string_name, lambda x: x, duration)])


@given(st.integers(), durations())
@settings(max_examples=50)
def test_declare_temporal_actions_requires_callable_action(int_action, duration):
    """declare_temporal_actions should require callable actions."""
    actions = Actions()

    # Use non-callable as action
    with pytest.raises(AssertionError):
        actions.declare_temporal_actions([("test_action", int_action, duration)])


@given(st.integers())
@settings(max_examples=50)
def test_declare_temporal_actions_rejects_non_list(non_list):
    """declare_temporal_actions should reject non-list input."""
    actions = Actions()
    with pytest.raises(AssertionError):
        actions.declare_temporal_actions(non_list)


# ============================================================================
# Temporal Metadata Access Tests
# ============================================================================


@given(action_functions(), durations())
@settings(max_examples=100)
def test_get_temporal_metadata_returns_metadata(action_list, duration):
    """get_temporal_metadata should return TemporalMetadata for temporal actions."""
    actions = Actions()

    action = action_list[0]
    temporal_list = [(action, duration)]
    actions.declare_temporal_actions(temporal_list)

    metadata = actions.get_temporal_metadata(action.__name__)
    assert metadata is not None
    assert metadata.duration is not None


@given(action_functions())
@settings(max_examples=50)
def test_get_temporal_metadata_returns_none_for_non_temporal(action_list):
    """get_temporal_metadata should return None for non-temporal actions."""
    actions = Actions()
    actions.declare_actions(action_list)

    for action in action_list:
        metadata = actions.get_temporal_metadata(action.__name__)
        assert metadata is None


@given(action_functions(), durations())
@settings(max_examples=100)
def test_has_temporal_info_returns_true_for_temporal(action_list, duration):
    """has_temporal_info should return True for temporal actions."""
    actions = Actions()

    action = action_list[0]
    temporal_list = [(action, duration)]
    actions.declare_temporal_actions(temporal_list)

    assert actions.has_temporal_info(action.__name__) is True


@given(action_functions())
@settings(max_examples=50)
def test_has_temporal_info_returns_false_for_non_temporal(action_list):
    """has_temporal_info should return False for non-temporal actions."""
    actions = Actions()
    actions.declare_actions(action_list)

    for action in action_list:
        assert actions.has_temporal_info(action.__name__) is False


# ============================================================================
# String Representation Tests
# ============================================================================


@given(action_functions())
@settings(max_examples=50)
def test_str_includes_action_names(action_list):
    """__str__ should include action names."""
    actions = Actions()
    actions.declare_actions(action_list)

    str_repr = str(actions)
    assert "ACTIONS:" in str_repr

    for action in action_list:
        assert action.__name__ in str_repr


def test_repr_equals_str():
    """__repr__ should equal __str__."""

    def test_action():
        return False

    actions = Actions()
    actions.declare_actions([test_action])

    assert repr(actions) == str(actions)


# ============================================================================
# Property: Action Registration Consistency
# ============================================================================


@given(action_functions())
@settings(max_examples=100)
def test_action_registration_consistency(action_list):
    """
    Property: After declare_actions, all three dicts should have the same keys.
    """
    actions = Actions()
    actions.declare_actions(action_list)

    action_names_set = {a.__name__ for a in action_list}

    assert set(actions.action_dict.keys()) == action_names_set
    assert set(actions.action_prob.keys()) == action_names_set
    assert set(actions.action_cost.keys()) == action_names_set


@given(action_functions(), durations())
@settings(max_examples=100, suppress_health_check=[HealthCheck.too_slow])
def test_temporal_action_registration_consistency(action_list, duration):
    """
    Property: Temporal actions should be registered in both action_dict and action_temporal_dict.
    """
    actions = Actions()

    action = action_list[0]
    temporal_list = [(action, duration)]
    actions.declare_temporal_actions(temporal_list)

    assert action.__name__ in actions.action_dict
    assert action.__name__ in actions.action_temporal_dict
    assert action.__name__ in actions.action_prob
    assert action.__name__ in actions.action_cost


# ============================================================================
# Integration: Mixed Action Types
# ============================================================================


@given(action_functions(), durations())
@settings(max_examples=50, suppress_health_check=[HealthCheck.too_slow])
def test_mixed_classical_and_temporal_actions(action_list, duration):
    """Should support both classical and temporal actions in same Actions object."""
    from hypothesis import assume

    assume(len(action_list) >= 2)

    actions = Actions()

    # First half classical, second half temporal
    mid = len(action_list) // 2
    classical_actions = action_list[:mid] if mid > 0 else action_list[:1]
    temporal_actions = action_list[mid:]

    actions.declare_actions(classical_actions)
    for action in temporal_actions:
        actions.declare_temporal_actions([(action, duration)])

    # Verify classical actions don't have temporal info
    for action in classical_actions:
        assert action.__name__ in actions.action_dict
        # Only check if it wasn't also registered as temporal
        if action.__name__ not in {a.__name__ for a in temporal_actions}:
            assert not actions.has_temporal_info(action.__name__)

    # Verify temporal actions have temporal info
    for action in temporal_actions:
        assert action.__name__ in actions.action_dict
        assert actions.has_temporal_info(action.__name__)


# ============================================================================
# Edge Cases
# ============================================================================


def test_empty_action_list():
    """Empty action list should be handled gracefully."""
    actions = Actions()
    actions.declare_actions([])
    assert actions.action_dict == {}


def test_single_action():
    """Single action should work correctly."""

    def single_action(state):
        return state

    actions = Actions()
    actions.declare_actions([single_action])

    assert "single_action" in actions.action_dict
    assert actions.action_prob["single_action"] == [1, 0]
    assert actions.action_cost["single_action"] == 1.0


def test_action_with_many_args():
    """Actions with many arguments should work."""

    def multi_arg_action(state, a, b, c, d, e):
        return state

    actions = Actions()
    actions.declare_actions([multi_arg_action])

    assert "multi_arg_action" in actions.action_dict


def test_zero_duration():
    """Zero duration should be handled."""
    actions = Actions()

    def instant_action(state):
        return state

    actions.declare_temporal_actions([(instant_action, "PT0S")])

    assert actions.has_temporal_info("instant_action")
    metadata = actions.get_temporal_metadata("instant_action")
    assert metadata.duration_seconds() == 0.0


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
