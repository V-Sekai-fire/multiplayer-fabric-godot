"""Hypothesis property-based tests for plan_memory.rebac.

Tests ReBAC computed relation expressions: Base, Union, Intersection,
Difference, TupleToUserset, fuel exhaustion, ReBACExprEngine integration,
copy independence, and expand.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Ensure taskweft and plan directories are importable
_TASKWEFT_DIR = Path(__file__).resolve().parent.parent.parent
_PLAN_DIR = _TASKWEFT_DIR / "plan"
for _d in (str(_TASKWEFT_DIR), str(_PLAN_DIR)):
    if _d not in sys.path:
        sys.path.insert(0, _d)

import pytest
from hypothesis import given, settings, assume
from hypothesis import strategies as st

from taskweft.plan_memory.rebac import (
    Base,
    Difference,
    Intersection,
    ReBACExprEngine,
    RelationExpr,
    TupleToUserset,
    Union,
    check_relation_expr,
    expand,
)
from taskweft.plan.ipyhop.capabilities import ReBACEngine, RelationshipType


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

# Identifiers: alphanumeric + underscore, 1-20 chars
_ident = st.text(
    alphabet=st.characters(whitelist_categories=("L", "N"), whitelist_characters="_"),
    min_size=1,
    max_size=20,
).filter(lambda s: s.strip() == s and len(s) > 0)

# Pick from the relation types that Base checks directly look at
_base_rel_types = st.sampled_from([
    RelationshipType.HAS_CAPABILITY,
    RelationshipType.CONTROLS,
    RelationshipType.OWNS,
    RelationshipType.IS_MEMBER_OF,
    RelationshipType.DELEGATED_TO,
    RelationshipType.SUPERVISOR_OF,
    RelationshipType.PARTNER_OF,
])

_base_expr = _base_rel_types.map(Base)

# Recursive expression strategy (shallow to keep tests fast)
_expr = st.recursive(
    _base_expr,
    lambda children: st.one_of(
        st.tuples(children, children).map(lambda t: Union(t[0], t[1])),
        st.tuples(children, children).map(lambda t: Intersection(t[0], t[1])),
        st.tuples(children, children).map(lambda t: Difference(t[0], t[1])),
        st.tuples(_base_rel_types, children).map(lambda t: TupleToUserset(t[0], t[1])),
    ),
    max_leaves=4,
)


def _fresh_engine() -> ReBACExprEngine:
    return ReBACExprEngine()


# ---------------------------------------------------------------------------
# Base check: add edge with matching rel -> check returns True
# ---------------------------------------------------------------------------

@given(subj=_ident, obj=_ident, rel=_base_rel_types)
@settings(max_examples=80)
def test_base_check_positive(subj: str, obj: str, rel: RelationshipType):
    """Adding an edge (subj, rel, obj) then checking Base(rel) returns True."""
    assume(subj != obj)
    engine = _fresh_engine()
    engine.add_relationship(subj, obj, rel)
    assert check_relation_expr(engine, subj, Base(rel), obj) is True


# ---------------------------------------------------------------------------
# Base check: no edge -> check returns False
# ---------------------------------------------------------------------------

@given(subj=_ident, obj=_ident, rel=_base_rel_types)
@settings(max_examples=80)
def test_base_check_negative(subj: str, obj: str, rel: RelationshipType):
    """Empty engine => Base(rel) always False."""
    engine = _fresh_engine()
    assert check_relation_expr(engine, subj, Base(rel), obj) is False


# ---------------------------------------------------------------------------
# Union monotonicity: if Base(rel) passes, Union(Base(rel), anything) passes
# ---------------------------------------------------------------------------

@given(subj=_ident, obj=_ident, rel=_base_rel_types, other_expr=_base_expr)
@settings(max_examples=80)
def test_union_monotonicity(subj, obj, rel, other_expr):
    """Union(a, b) passes whenever a passes, regardless of b."""
    assume(subj != obj)
    engine = _fresh_engine()
    engine.add_relationship(subj, obj, rel)

    base = Base(rel)
    assert check_relation_expr(engine, subj, base, obj) is True
    assert check_relation_expr(engine, subj, Union(base, other_expr), obj) is True
    assert check_relation_expr(engine, subj, Union(other_expr, base), obj) is True


# ---------------------------------------------------------------------------
# Intersection subset: if Intersection(a,b) passes, both a and b pass
# ---------------------------------------------------------------------------

@given(subj=_ident, obj=_ident, rel_a=_base_rel_types, rel_b=_base_rel_types)
@settings(max_examples=80)
def test_intersection_subset(subj, obj, rel_a, rel_b):
    """Intersection(a, b) => both a and b individually hold."""
    assume(subj != obj)
    engine = _fresh_engine()
    engine.add_relationship(subj, obj, rel_a)
    engine.add_relationship(subj, obj, rel_b)

    a = Base(rel_a)
    b = Base(rel_b)
    result = check_relation_expr(engine, subj, Intersection(a, b), obj, fuel=5)
    if result:
        assert check_relation_expr(engine, subj, a, obj, fuel=5) is True
        assert check_relation_expr(engine, subj, b, obj, fuel=5) is True


# ---------------------------------------------------------------------------
# Difference semantics: Difference(a, b) = a AND NOT b
# ---------------------------------------------------------------------------

@given(subj=_ident, obj=_ident, rel_a=_base_rel_types, rel_b=_base_rel_types)
@settings(max_examples=80)
def test_difference_semantics(subj, obj, rel_a, rel_b):
    """Difference(a, b) iff a holds and b does not."""
    assume(subj != obj)
    engine = _fresh_engine()
    engine.add_relationship(subj, obj, rel_a)
    # Do NOT add rel_b -- so b should be false

    a = Base(rel_a)
    b = Base(rel_b)

    a_holds = check_relation_expr(engine, subj, a, obj, fuel=5)
    b_holds = check_relation_expr(engine, subj, b, obj, fuel=5)
    diff = check_relation_expr(engine, subj, Difference(a, b), obj, fuel=5)

    assert diff == (a_holds and not b_holds)


# ---------------------------------------------------------------------------
# TupleToUserset: follow pivot then check inner
# ---------------------------------------------------------------------------

@given(
    subj=_ident,
    mid=_ident,
    obj=_ident,
    pivot_rel=_base_rel_types,
    inner_rel=_base_rel_types,
)
@settings(max_examples=80)
def test_tuple_to_userset(subj, mid, obj, pivot_rel, inner_rel):
    """TupleToUserset follows pivot_rel from subj to mid, then checks inner from mid."""
    assume(len({subj, mid, obj}) == 3)
    engine = _fresh_engine()
    engine.add_relationship(subj, mid, pivot_rel)
    engine.add_relationship(mid, obj, inner_rel)

    expr = TupleToUserset(pivot_rel, Base(inner_rel))
    assert check_relation_expr(engine, subj, expr, obj, fuel=5) is True


# ---------------------------------------------------------------------------
# Fuel exhaustion: fuel=0 -> always False
# ---------------------------------------------------------------------------

@given(subj=_ident, obj=_ident, expr=_expr)
@settings(max_examples=80)
def test_fuel_exhaustion(subj, obj, expr):
    """With fuel=0, check_relation_expr always returns False."""
    engine = _fresh_engine()
    assert check_relation_expr(engine, subj, expr, obj, fuel=0) is False


# ---------------------------------------------------------------------------
# ReBACExprEngine.define_relation + check integration
# ---------------------------------------------------------------------------

@given(
    subj=_ident,
    obj=_ident,
    rel=_base_rel_types,
    name=_ident,
)
@settings(max_examples=80)
def test_define_relation_and_check(subj, obj, rel, name):
    """define_relation + check dispatches to the named expression."""
    assume(subj != obj)
    engine = ReBACExprEngine()
    engine.add_relationship(subj, obj, rel)
    engine.define_relation(name, Base(rel))

    assert engine.check(subj, name, obj) is True


# ---------------------------------------------------------------------------
# ReBACExprEngine.copy independence
# ---------------------------------------------------------------------------

@given(subj=_ident, obj=_ident, rel=_base_rel_types, name=_ident)
@settings(max_examples=50)
def test_copy_independence(subj, obj, rel, name):
    """Mutating a copy does not affect the original engine."""
    assume(subj != obj)
    engine = ReBACExprEngine()
    engine.add_relationship(subj, obj, rel)
    engine.define_relation(name, Base(rel))

    clone = engine.copy()

    # Mutate clone
    other_rel = RelationshipType.PARTNER_OF
    clone.add_relationship("extra_subj", "extra_obj", other_rel)
    clone.define_relation("extra_def", Base(other_rel))

    # Original is unaffected
    assert "extra_subj" not in engine._subject_index
    assert "extra_def" not in engine._definitions
    # Clone has both old and new
    assert clone.check(subj, name, obj) is True
    assert "extra_def" in clone._definitions


# ---------------------------------------------------------------------------
# expand finds direct holders
# ---------------------------------------------------------------------------

@given(
    holders=st.lists(_ident, min_size=1, max_size=5, unique=True),
    obj=_ident,
    rel=_base_rel_types,
)
@settings(max_examples=60)
def test_expand_finds_direct_holders(holders, obj, rel):
    """expand returns all direct holders of rel -> obj."""
    assume(obj not in holders)
    engine = _fresh_engine()
    for h in holders:
        engine.add_relationship(h, obj, rel)

    result = expand(engine, rel, obj)
    for h in holders:
        assert h in result, f"{h} should be found by expand"
