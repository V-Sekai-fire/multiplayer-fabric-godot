#!/usr/bin/env python
"""
Hypothesis property-based tests for MultiGoal class.

Covers multi-goal handling, copying, updating, and string representation.
"""

import sys
import os
import importlib.util

import pytest
from hypothesis import given, settings, assume
from hypothesis import strategies as st

_plan_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, _plan_dir)

# Import directly to avoid matplotlib dependency
_mg_spec = importlib.util.spec_from_file_location("multigoal", os.path.join(_plan_dir, "ipyhop/multigoal.py"))
_mg_module = importlib.util.module_from_spec(_mg_spec)
_mg_spec.loader.exec_module(_mg_module)
MultiGoal = _mg_module.MultiGoal


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

_identifier_alphabet = st.characters(
    whitelist_categories=("L", "N"),
    whitelist_characters="_",
    min_codepoint=32,
)

name_strategy = st.text(
    alphabet=_identifier_alphabet,
    min_size=1,
    max_size=30,
).filter(lambda s: s[0].isalpha() or s[0] == "_")

value_strategy = st.one_of(
    st.text(min_size=0, max_size=20),
    st.integers(min_value=-1000, max_value=1000),
    st.floats(allow_nan=False, allow_infinity=False),
)

goal_dict_strategy = st.dictionaries(
    keys=name_strategy,
    values=value_strategy,
    min_size=1,
    max_size=5,
)


@st.composite
def multigoal_strategy(draw):
    """Draw a MultiGoal with a random name, optional tag, and 1-3 goal attributes."""
    mg_name = draw(name_strategy)
    tag = draw(st.one_of(st.none(), name_strategy))
    mg = MultiGoal(mg_name, tag)
    n_attrs = draw(st.integers(min_value=1, max_value=3))
    for _ in range(n_attrs):
        attr = draw(name_strategy)
        assume(attr not in ("__name__", "goal_tag"))
        setattr(mg, attr, draw(goal_dict_strategy))
    return mg


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@given(mg_name=name_strategy)
@settings(max_examples=80)
def test_initialization(mg_name):
    """MultiGoal stores its name and defaults goal_tag to None."""
    mg = MultiGoal(mg_name)
    assert mg.__name__ == mg_name
    assert mg.goal_tag is None


@given(mg_name=name_strategy, tag=name_strategy)
@settings(max_examples=80)
def test_initialization_with_tag(mg_name, tag):
    """MultiGoal stores the provided goal_tag."""
    mg = MultiGoal(mg_name, tag)
    assert mg.goal_tag == tag


@given(mg_name=name_strategy, goals=goal_dict_strategy)
@settings(max_examples=80)
def test_goal_assignment(mg_name, goals):
    """Arbitrary dicts assigned as attributes are retrievable."""
    mg = MultiGoal(mg_name)
    mg.loc = goals
    for key, val in goals.items():
        assert mg.loc[key] == val


@given(mg_name=name_strategy, goals_a=goal_dict_strategy, goals_b=goal_dict_strategy)
@settings(max_examples=80)
def test_multiple_goal_types(mg_name, goals_a, goals_b):
    """Multiple goal attributes coexist independently."""
    mg = MultiGoal(mg_name)
    mg.loc = goals_a
    mg.status = goals_b
    assert mg.loc == goals_a
    assert mg.status == goals_b


@given(mg1=multigoal_strategy(), mg2=multigoal_strategy())
@settings(max_examples=60)
def test_goal_update(mg1, mg2):
    """update() replaces __dict__ contents with those of the other MultiGoal."""
    mg1.update(mg2)
    # After update, all attributes from mg2 should be present in mg1
    for attr, val in mg2.__dict__.items():
        assert getattr(mg1, attr) == val


@given(mg=multigoal_strategy())
@settings(max_examples=80)
def test_goal_copy(mg):
    """copy() produces an independent deep copy."""
    mg_copy = mg.copy()
    # All attributes equal
    for attr in mg.__dict__:
        assert getattr(mg_copy, attr) == getattr(mg, attr)
    # Mutating the copy does not affect the original
    mg_copy.__name__ = mg_copy.__name__ + "_modified"
    assert mg.__name__ != mg_copy.__name__


@given(mg_name=name_strategy, goals=goal_dict_strategy)
@settings(max_examples=80)
def test_string_representation(mg_name, goals):
    """String representation includes the name and attribute names."""
    mg = MultiGoal(mg_name)
    mg.loc = goals
    text = str(mg)
    assert mg_name in text
    assert "loc" in text


@given(mg=multigoal_strategy())
@settings(max_examples=50)
def test_copy_deep_independence(mg):
    """Mutating a dict value inside the copy must not change the original."""
    mg_copy = mg.copy()
    # Find a dict attribute and mutate it in the copy
    for attr in list(mg_copy.__dict__):
        val = getattr(mg_copy, attr)
        if isinstance(val, dict) and len(val) > 0:
            val["__hypothesis_sentinel__"] = True
            orig_val = getattr(mg, attr)
            assert "__hypothesis_sentinel__" not in orig_val
            break
