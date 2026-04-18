"""ReBAC computed relation expressions — Python mirror of Lean RelationExpr.

Adds algebraic relation combinators (union, intersection, difference,
tuple-to-userset) on top of IPyHOP's existing ReBACEngine.  The Lean
definitions in Types.lean / Capabilities.lean are the verified spec;
this module is the runtime implementation with identical semantics.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Set, Tuple

from ..plan.ipyhop.capabilities import ReBACEngine, RelationshipType


# ---------------------------------------------------------------------------
# RelationExpr — mirrors Lean inductive
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class RelationExpr:
    """Base class for computed relation expressions."""
    pass


@dataclass(frozen=True)
class Base(RelationExpr):
    """Direct relation check."""
    rel: RelationshipType


@dataclass(frozen=True)
class Union(RelationExpr):
    """Either relation grants access."""
    a: RelationExpr
    b: RelationExpr


@dataclass(frozen=True)
class Intersection(RelationExpr):
    """Both relations required."""
    a: RelationExpr
    b: RelationExpr


@dataclass(frozen=True)
class Difference(RelationExpr):
    """First relation required, second must NOT hold."""
    a: RelationExpr
    b: RelationExpr


@dataclass(frozen=True)
class TupleToUserset(RelationExpr):
    """Follow pivot relation, then evaluate inner from the target."""
    pivot_rel: RelationshipType
    inner: RelationExpr


# ---------------------------------------------------------------------------
# check_relation_expr — mirrors Lean checkRelationExpr
# ---------------------------------------------------------------------------

def check_relation_expr(
    engine: ReBACEngine,
    subj: str,
    expr: RelationExpr,
    obj: str,
    state: Any = None,
    fuel: int = 3,
) -> bool:
    """Evaluate a computed relation expression against a ReBACEngine graph.

    Mirrors Lean ``checkRelationExpr`` with identical semantics:
    - Base: delegates to ``engine.can()``
    - Union: short-circuit OR
    - Intersection: short-circuit AND
    - Difference: a AND NOT b
    - TupleToUserset: follow pivot_rel edges from subj, then check inner
      from the target entity
    """
    if fuel <= 0:
        return False

    if isinstance(expr, Base):
        # Direct relation check — mirrors Lean: hasCapability graph subj rel obj n
        # Check direct edges with the specific relation type
        for edge in engine._subject_index.get(subj, set()):
            if edge.relationship_type == expr.rel and edge.object == obj:
                if state is None or edge.is_valid(state):
                    return True
        # Transitive: follow IS_MEMBER_OF chains (mirrors Lean's second branch)
        for edge in engine._subject_index.get(subj, set()):
            if edge.relationship_type == RelationshipType.IS_MEMBER_OF:
                if state is None or edge.is_valid(state):
                    if check_relation_expr(engine, edge.object, expr, obj, state, fuel - 1):
                        return True
        # Delegation inversion (mirrors Lean's third branch)
        if expr.rel == RelationshipType.CONTROLS:
            for edge in engine._object_index.get(subj, set()):
                if (edge.relationship_type == RelationshipType.DELEGATED_TO
                        and edge.subject == obj):
                    if state is None or edge.is_valid(state):
                        return True
        return False

    elif isinstance(expr, Union):
        return (check_relation_expr(engine, subj, expr.a, obj, state, fuel - 1) or
                check_relation_expr(engine, subj, expr.b, obj, state, fuel - 1))

    elif isinstance(expr, Intersection):
        return (check_relation_expr(engine, subj, expr.a, obj, state, fuel - 1) and
                check_relation_expr(engine, subj, expr.b, obj, state, fuel - 1))

    elif isinstance(expr, Difference):
        return (check_relation_expr(engine, subj, expr.a, obj, state, fuel - 1) and
                not check_relation_expr(engine, subj, expr.b, obj, state, fuel - 1))

    elif isinstance(expr, TupleToUserset):
        for edge in engine._subject_index.get(subj, set()):
            if edge.relationship_type == expr.pivot_rel:
                if state is None or edge.is_valid(state):
                    if check_relation_expr(engine, edge.object, expr.inner, obj, state, fuel - 1):
                        return True
        return False

    return False


# ---------------------------------------------------------------------------
# expand — mirrors Lean expand
# ---------------------------------------------------------------------------

def expand(
    engine: ReBACEngine,
    rel: RelationshipType,
    obj: str,
    state: Any = None,
    fuel: int = 3,
) -> List[str]:
    """Find all entities with the given relation to an object.

    Returns direct holders and those who inherit via IS_MEMBER_OF chains.
    Mirrors Lean ``expand``.
    """
    direct: Set[str] = set()
    for edge in engine._object_index.get(obj, set()):
        if edge.relationship_type == rel:
            if state is None or edge.is_valid(state):
                direct.add(edge.subject)

    inherited: Set[str] = set()
    for edge in engine._edges:
        if edge.relationship_type == RelationshipType.IS_MEMBER_OF:
            group = edge.object
            authorized, _ = engine.can(group, obj, state, max_depth=fuel)
            if authorized:
                inherited.add(edge.subject)

    return list(direct | inherited)


# ---------------------------------------------------------------------------
# ReBACExprEngine — extends ReBACEngine with computed relation definitions
# ---------------------------------------------------------------------------

class ReBACExprEngine(ReBACEngine):
    """ReBACEngine extended with named computed relation definitions.

    Mirrors Lean ``ReBACState`` which extends ``CapabilityState`` with
    a ``definitions : List (String x RelationExpr)`` field.
    """

    def __init__(self):
        super().__init__()
        self._definitions: Dict[str, RelationExpr] = {}

    def define_relation(self, name: str, expr: RelationExpr) -> None:
        """Register a named computed relation definition."""
        self._definitions[name] = expr

    def check(
        self,
        subj: str,
        action: str,
        obj: str,
        state: Any = None,
        fuel: int = 3,
    ) -> bool:
        """ReBAC-aware capability check.

        Looks up named computed relation definitions first; falls through
        to ``self.can()`` for unknown action names.  Mirrors Lean
        ``hasCapabilityReBAC``.
        """
        if action in self._definitions:
            return check_relation_expr(
                self, subj, self._definitions[action], obj, state, fuel
            )
        authorized, _ = self.can(subj, action, state, max_depth=fuel)
        return authorized

    def copy(self) -> ReBACExprEngine:
        """Deep copy including definitions."""
        from copy import deepcopy
        new = ReBACExprEngine()
        new._edges = deepcopy(self._edges)
        new._subject_index = deepcopy(self._subject_index)
        new._object_index = deepcopy(self._object_index)
        new._definitions = dict(self._definitions)  # RelationExpr is frozen
        return new
