"""PlanMemoryBridge — connects holographic memory to the HTN planner via ReBAC.

Holographic memory serves as the persistent ReBAC tuple store.  Memory facts
encode relationship tuples; HRR algebra maps to ReBAC operations:

    probe(entity)        -> expand(rel, obj)
    reason([e1, e2])     -> intersection of relations
    contradict()         -> conflicting tuples
    trust_score          -> tuple confidence gate

The bridge hydrates a ReBACExprEngine from memory facts before planning
and stores plan results back as relationship tuples after planning.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any, Dict, List, Optional, Tuple

from .rebac import (
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

logger = logging.getLogger(__name__)

# Mapping from text relation names to RelationshipType
_RELATION_KEYWORDS = {
    "owns": "OWNS",
    "controls": "CONTROLS",
    "delegated": "DELEGATED_TO",
    "delegates": "DELEGATED_TO",
    "capable": "HAS_CAPABILITY",
    "capability": "HAS_CAPABILITY",
    "member": "IS_MEMBER_OF",
    "belongs": "IS_MEMBER_OF",
    "supervises": "SUPERVISOR_OF",
    "supervisor": "SUPERVISOR_OF",
    "partner": "PARTNER_OF",
}

# Pattern: "subject RELATION object" in fact content
_RE_RELATION = re.compile(
    r"(\w[\w\s]*?)\s+"
    r"(owns|controls|delegated to|delegates to|has capability|"
    r"is member of|belongs to|supervises|partner of)\s+"
    r"(\w[\w\s]*?)(?:\.|$)",
    re.IGNORECASE,
)


class PlanMemoryBridge:
    """Bridge between holographic memory (fact store) and the HTN planner.

    Treats holographic memory as a ReBAC tuple store and builds a
    ReBACExprEngine from recalled facts for use as planning state.
    """

    def __init__(
        self,
        store: Any,       # holographic.store.MemoryStore
        retriever: Any,   # holographic.retrieval.FactRetriever
        trust_threshold: float = 0.5,
    ) -> None:
        self.store = store
        self.retriever = retriever
        self.trust_threshold = trust_threshold

    # ------------------------------------------------------------------
    # Memory -> ReBAC graph hydration
    # ------------------------------------------------------------------

    def hydrate_capability_state(
        self,
        entity_names: List[str],
        domain: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Query holographic memory and build a ReBACExprEngine.

        1. Probe memory for each entity
        2. Use reason() for multi-entity compositional recall (HRR algebra)
        3. Parse facts into relationship tuples
        4. Return engine + raw memory context

        Returns:
            {"engine": ReBACExprEngine, "memory_context": [fact dicts]}
        """
        engine = ReBACExprEngine()
        all_facts: List[Dict] = []
        seen_ids: set = set()

        category = "planning" if domain else None

        # Single-entity probes
        for entity in entity_names:
            try:
                facts = self.retriever.probe(
                    entity, category=category, limit=20
                )
            except Exception:
                facts = self.retriever.search(
                    entity, category=category, limit=20
                )
            for fact in facts:
                if fact.get("trust_score", 0) < self.trust_threshold:
                    continue
                fid = fact.get("fact_id")
                if fid and fid not in seen_ids:
                    seen_ids.add(fid)
                    all_facts.append(fact)

        # Multi-entity compositional recall (HRR reason)
        if len(entity_names) >= 2:
            try:
                composed = self.retriever.reason(
                    entity_names, category=category, limit=10
                )
                for fact in composed:
                    if fact.get("trust_score", 0) < self.trust_threshold:
                        continue
                    fid = fact.get("fact_id")
                    if fid and fid not in seen_ids:
                        seen_ids.add(fid)
                        all_facts.append(fact)
            except Exception as exc:
                logger.debug("reason() failed: %s", exc)

        # Parse facts into relationship edges
        from ..plan.ipyhop.capabilities import RelationshipType

        for fact in all_facts:
            content = fact.get("content", "")
            for match in _RE_RELATION.finditer(content):
                subj_text = match.group(1).strip()
                rel_text = match.group(2).strip().lower()
                obj_text = match.group(3).strip()

                # Map text to RelationshipType
                rel_key = rel_text.split()[0]  # first word
                rel_name = _RELATION_KEYWORDS.get(rel_key)
                if rel_name is None:
                    continue
                try:
                    rel_type = RelationshipType[rel_name]
                except KeyError:
                    continue

                engine.add_relationship(subj_text, obj_text, rel_type)

        return {"engine": engine, "memory_context": all_facts}

    # ------------------------------------------------------------------
    # State / Goal binding storage
    #
    # Lean GoalStateEquivalence.lean proves that State and MultiGoal
    # bindings produce identical HRR vectors when the (var, arg, val)
    # triple is the same.  Both use encode_binding (= Lean encodeFact
    # = bind(content, entity)), so probe(entity) recovers the content
    # with zero noise (fact_recovery_content theorem).
    #
    # This method encodes each variable binding as a fact so the
    # holographic memory can algebraically recall state/goal context.
    # ------------------------------------------------------------------

    @staticmethod
    def _binding_to_content(var_name: str, arg: str, val: str) -> str:
        """Canonical text for a state/goal variable binding.

        Using a single canonical form ensures that State and MultiGoal
        produce the same HRR vector for the same assignment, satisfying
        the Lean proof ``encoding_independent_of_source``.
        """
        return f"{var_name} {arg} {val}"

    def store_state_bindings(
        self,
        state_dict: Dict[str, Any],
        domain: str,
        category: str = "state",
    ) -> List[int]:
        """Encode state variable bindings into holographic memory.

        Each binding ``state.var_name[arg] = val`` becomes a fact with
        content ``"var_name arg val"`` and entities ``[arg]``.  The
        store computes ``encode_binding(content, arg)`` per entity,
        which equals Lean's ``encodeFact content entity = bind(content, entity)``.

        Returns list of fact_ids.
        """
        fact_ids: List[int] = []
        for var_name, bindings in state_dict.items():
            if var_name.startswith("_") or var_name == "__name__" or var_name == "rigid":
                continue
            if not isinstance(bindings, dict):
                continue
            for arg, val in bindings.items():
                content = self._binding_to_content(var_name, str(arg), str(val))
                try:
                    fid = self.store.add_fact(
                        content=content,
                        category=category,
                        tags=domain,
                    )
                    fact_ids.append(fid)
                except Exception as exc:
                    logger.debug("Failed to store binding %s.%s=%s: %s",
                                 var_name, arg, val, exc)
        return fact_ids

    def store_goal_bindings(
        self,
        goal_dict: Dict[str, Any],
        domain: str,
        category: str = "goal",
    ) -> List[int]:
        """Encode goal/multigoal variable bindings into holographic memory.

        Uses the **same** ``_binding_to_content`` as ``store_state_bindings``
        so that identical (var, arg, val) triples produce identical HRR
        vectors.  This satisfies Lean's ``satisfaction_iff_encoding_eq``:
        ``state_val = goal_val ↔ encodeFact state_val entity = encodeFact goal_val entity``

        Returns list of fact_ids.
        """
        fact_ids: List[int] = []
        for var_name, bindings in goal_dict.items():
            if var_name in ("__name__", "goal_tag"):
                continue
            if not isinstance(bindings, dict):
                continue
            for arg, val in bindings.items():
                content = self._binding_to_content(var_name, str(arg), str(val))
                try:
                    fid = self.store.add_fact(
                        content=content,
                        category=category,
                        tags=domain,
                    )
                    fact_ids.append(fid)
                except Exception as exc:
                    logger.debug("Failed to store goal binding %s.%s=%s: %s",
                                 var_name, arg, val, exc)
        return fact_ids

    # ------------------------------------------------------------------
    # Plan results -> Memory storage
    # ------------------------------------------------------------------

    def store_plan_result(
        self,
        plan_json: List,
        domain: str,
        entities: List[str],
        tasks: Optional[List] = None,
    ) -> List[int]:
        """Store plan result as structured facts in holographic memory.

        Each fact is tagged with category="planning" so it auto-builds the
        cat:planning HRR memory bank for future algebraic recall.

        Returns list of fact_ids.
        """
        fact_ids: List[int] = []

        # Summary fact
        step_count = len(plan_json)
        entity_str = ", ".join(entities[:5])
        task_str = ""
        if tasks:
            task_str = f" Tasks: {json.dumps(tasks[:3])}."

        summary = (
            f"Plan for {domain}: {step_count} steps involving {entity_str}.{task_str}"
        )
        try:
            fid = self.store.add_fact(
                content=summary,
                category="planning",
                tags=domain,
            )
            fact_ids.append(fid)
        except Exception as exc:
            logger.warning("Failed to store plan summary: %s", exc)

        # Individual step facts (lightweight)
        for i, step in enumerate(plan_json[:20]):  # cap at 20 steps
            if isinstance(step, (list, tuple)):
                action_name = step[0] if step else "unknown"
                args = step[1:] if len(step) > 1 else []
                content = f"Plan step {i+1}: {action_name}({', '.join(str(a) for a in args)}) in {domain}."
            elif isinstance(step, dict):
                action_name = step.get("action", ["unknown"])[0]
                content = f"Plan step {i+1}: {action_name} in {domain}."
            else:
                continue

            try:
                fid = self.store.add_fact(
                    content=content,
                    category="planning",
                    tags=domain,
                )
                fact_ids.append(fid)
            except Exception as exc:
                logger.debug("Failed to store step %d: %s", i, exc)

        return fact_ids

    # ------------------------------------------------------------------
    # Algebraic plan recall
    # ------------------------------------------------------------------

    def recall_planning_context(
        self,
        entities: List[str],
        domain: Optional[str] = None,
        limit: int = 5,
    ) -> List[Dict]:
        """Recall past planning contexts from holographic memory.

        Single entity: probe() against cat:planning bank (HRR unbind).
        Multiple entities: reason() — compositional AND across entity probes.
        """
        category = "planning"

        if len(entities) == 1:
            try:
                return self.retriever.probe(
                    entities[0], category=category, limit=limit
                )
            except Exception:
                return self.retriever.search(
                    entities[0], category=category, limit=limit
                )

        # Multi-entity: compositional recall
        try:
            return self.retriever.reason(
                entities, category=category, limit=limit
            )
        except Exception as exc:
            logger.debug("reason() failed, falling back to search: %s", exc)
            query = " ".join(entities)
            return self.retriever.search(
                query, category=category, limit=limit
            )
