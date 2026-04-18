#!/usr/bin/env python
"""
Hypothesis property-based tests for Simple Temporal Network (STN).

Covers initialization, time points, constraints, intervals, and consistency.
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
_stn_spec = importlib.util.spec_from_file_location("stn", os.path.join(_plan_dir, "ipyhop/temporal/stn.py"))
_stn_module = importlib.util.module_from_spec(_stn_spec)
_stn_spec.loader.exec_module(_stn_module)
STN = _stn_module.STN


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

_identifier_alphabet = st.characters(
    whitelist_categories=("L", "N"),
    whitelist_characters="_",
    min_codepoint=32,
)

point_name_strategy = st.text(
    alphabet=_identifier_alphabet,
    min_size=1,
    max_size=20,
).filter(lambda s: s[0].isalpha() or s[0] == "_")

time_unit_strategy = st.sampled_from(["second", "minute", "hour", "day", "millisecond"])

# A valid constraint where min <= max, using moderate floats to keep
# Floyd-Warshall well-behaved.
_bound = st.floats(min_value=0.0, max_value=1000.0, allow_nan=False, allow_infinity=False)


@st.composite
def valid_constraint(draw):
    """Draw a (min_dist, max_dist) tuple where min_dist <= max_dist."""
    a = draw(_bound)
    b = draw(_bound)
    lo, hi = min(a, b), max(a, b)
    assume(lo <= hi)
    return (lo, hi)


@st.composite
def invalid_constraint(draw):
    """Draw a constraint where min_dist > max_dist."""
    a = draw(_bound)
    b = draw(_bound)
    lo, hi = min(a, b), max(a, b)
    assume(lo < hi)  # ensure strictly different so swapping is invalid
    return (hi, lo)


@st.composite
def distinct_points(draw, min_count=2, max_count=5):
    """Draw a list of distinct point names."""
    names = draw(
        st.lists(point_name_strategy, min_size=min_count, max_size=max_count, unique=True)
    )
    return names


@st.composite
def consistent_chain_stn(draw):
    """Build an STN with a chain of constraints A->B->C->... that is always consistent."""
    points = draw(distinct_points(min_count=2, max_count=5))
    stn = STN(time_unit=draw(time_unit_strategy))
    for i in range(len(points) - 1):
        c = draw(valid_constraint())
        stn.add_constraint(points[i], points[i + 1], c)
    return stn, points


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


@given(unit=time_unit_strategy)
@settings(max_examples=50)
def test_initialization(unit):
    """Fresh STN has no points, no constraints, and stores the time unit."""
    stn = STN(time_unit=unit)
    assert len(stn.time_points) == 0
    assert len(stn.constraints) == 0
    assert stn.time_unit == unit


@settings(max_examples=50)
@given(unit=time_unit_strategy)
def test_time_unit_stored(unit):
    """The time_unit parameter is stored correctly."""
    stn = STN(time_unit=unit)
    assert stn.time_unit == unit


@given(names=st.lists(point_name_strategy, min_size=1, max_size=10, unique=True))
@settings(max_examples=80)
def test_add_time_points(names):
    """Adding N distinct points yields exactly N entries in time_points."""
    stn = STN()
    for n in names:
        stn.add_time_point(n)
    assert len(stn.time_points) == len(names)
    for n in names:
        assert n in stn.time_points


@given(name=point_name_strategy, repeats=st.integers(min_value=2, max_value=5))
@settings(max_examples=80)
def test_add_duplicate_time_point(name, repeats):
    """Adding the same point multiple times does not create duplicates."""
    stn = STN()
    for _ in range(repeats):
        stn.add_time_point(name)
    assert len(stn.time_points) == 1


@given(
    from_pt=point_name_strategy,
    to_pt=point_name_strategy,
    constraint=valid_constraint(),
)
@settings(max_examples=80)
def test_add_constraint(from_pt, to_pt, constraint):
    """add_constraint auto-creates points and stores the constraint tuple."""
    assume(from_pt != to_pt)
    stn = STN()
    stn.add_constraint(from_pt, to_pt, constraint)
    assert from_pt in stn.time_points
    assert to_pt in stn.time_points
    assert (from_pt, to_pt) in stn.constraints
    assert stn.constraints[(from_pt, to_pt)] == constraint


@given(
    from_pt=point_name_strategy,
    to_pt=point_name_strategy,
    constraint=invalid_constraint(),
)
@settings(max_examples=80)
def test_add_constraint_invalid(from_pt, to_pt, constraint):
    """Adding a constraint with min > max raises ValueError."""
    assume(from_pt != to_pt)
    stn = STN()
    with pytest.raises(ValueError):
        stn.add_constraint(from_pt, to_pt, constraint)


@given(
    start=point_name_strategy,
    end=point_name_strategy,
    duration=valid_constraint(),
)
@settings(max_examples=80)
def test_add_interval(start, end, duration):
    """add_interval delegates to add_constraint and stores correctly."""
    assume(start != end)
    stn = STN()
    stn.add_interval(start, end, duration)
    assert (start, end) in stn.constraints
    assert stn.constraints[(start, end)] == duration


@given(data=consistent_chain_stn())
@settings(max_examples=60)
def test_consistent_chain(data):
    """A forward-only chain of non-negative constraints is always consistent."""
    stn, points = data
    assert stn.consistent() is True


@given(
    from_pt=point_name_strategy,
    to_pt=point_name_strategy,
    c1=valid_constraint(),
    c2=valid_constraint(),
)
@settings(max_examples=60)
def test_inconsistent_opposing_constraints(from_pt, to_pt, c1, c2):
    """Two opposing constraints whose minimum distances sum > 0 form a negative cycle."""
    assume(from_pt != to_pt)
    # Only truly inconsistent when min_a + min_b > 0 and
    # there is no overlap that satisfies both directions.
    min_a, _ = c1
    min_b, _ = c2
    assume(min_a > 0 and min_b > 0)
    stn = STN()
    stn.add_constraint(from_pt, to_pt, c1)
    stn.add_constraint(to_pt, from_pt, c2)
    assert stn.consistent() is False


@settings(max_examples=50)
@given(st.just(None))
def test_consistent_empty(_):
    """An empty STN is always consistent."""
    stn = STN()
    assert stn.consistent() is True


@given(name=point_name_strategy)
@settings(max_examples=50)
def test_consistent_single_point(name):
    """An STN with a single point and no constraints is consistent."""
    stn = STN()
    stn.add_time_point(name)
    assert stn.consistent() is True


@given(data=consistent_chain_stn())
@settings(max_examples=60)
def test_multiple_constraints_count(data):
    """Chain of N points produces N-1 constraints and N time points."""
    stn, points = data
    assert len(stn.time_points) == len(points)
    assert len(stn.constraints) == len(points) - 1


@given(data=consistent_chain_stn())
@settings(max_examples=50)
def test_copy_independence(data):
    """Copying an STN produces an independent instance."""
    stn, points = data
    stn_copy = stn.copy()
    assert stn_copy.time_points == stn.time_points
    assert stn_copy.constraints == stn.constraints
    # Mutate original; copy should be unaffected
    stn.add_time_point("__sentinel__")
    assert "__sentinel__" not in stn_copy.time_points


@given(data=consistent_chain_stn())
@settings(max_examples=50)
def test_str_representation(data):
    """String representation includes point count and constraint count."""
    stn, points = data
    text = str(stn)
    assert f"time_points={len(points)}" in text
    assert f"constraints={len(points) - 1}" in text
