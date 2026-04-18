"""plan_memory — bridge between holographic memory and HTN planner.

Holographic memory serves as a ReBAC tuple store; the planner's capability
state is hydrated from memory facts.  Exposes two tools:

  plan_with_memory  — memory-augmented HTN planning
  recall_plans      — algebraic recall of past planning contexts
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_SCHEMAS_DIR = Path(__file__).parent / "schemas"


def _get_domain_handler(domain: str):
    """Import the plan plugin's domain handler."""
    from ..plan.tools import (
        handle_simple_travel,
        handle_blocks_world,
        handle_rescue,
        handle_robosub,
        handle_healthcare,
        handle_temporal_travel,
        handle_entity_capabilities,
        handle_job_shop_scheduling,
        handle_gltf_interactivity,
    )
    handlers = {
        "simple_travel": handle_simple_travel,
        "blocks_world": handle_blocks_world,
        "rescue": handle_rescue,
        "robosub": handle_robosub,
        "healthcare": handle_healthcare,
        "temporal_travel": handle_temporal_travel,
        "entity_capabilities": handle_entity_capabilities,
        "job_shop_scheduling": handle_job_shop_scheduling,
        "gltf_interactivity": handle_gltf_interactivity,
    }
    return handlers.get(domain)


def _get_bridge(ctx, trust_threshold: float = 0.5):
    """Lazily obtain a PlanMemoryBridge from the holographic memory provider."""
    from .bridge import PlanMemoryBridge

    # The holographic plugin registers a MemoryProvider; retrieve its internals
    provider = getattr(ctx, "_memory_provider", None)
    if provider is None:
        raise RuntimeError(
            "Holographic memory provider not found. "
            "Ensure the 'holographic' plugin is loaded before 'plan_memory'."
        )
    store = getattr(provider, "_store", None)
    retriever = getattr(provider, "_retriever", None)
    if store is None or retriever is None:
        raise RuntimeError("Holographic provider not initialized (no store/retriever).")
    return PlanMemoryBridge(store, retriever, trust_threshold=trust_threshold)


def _extract_entities_from_state(state_dict: dict) -> list[str]:
    """Extract entity names from IPyHOP state dict keys."""
    entities = set()
    for key, val in state_dict.items():
        if isinstance(val, dict):
            for k in val:
                if isinstance(k, str) and not k.startswith("rigid"):
                    entities.add(k)
    return list(entities)


# ---------------------------------------------------------------------------
# Tool handlers
# ---------------------------------------------------------------------------


def handle_plan_with_memory(params: dict[str, Any], ctx: Any = None, **kwargs: Any) -> str:
    """Memory-augmented HTN planning.

    1. Hydrate ReBAC capability state from holographic memory
    2. Delegate to the domain-specific planner
    3. Store plan result back into memory
    """
    domain = params.get("domain")
    if not domain:
        return json.dumps({"error": "domain is required"})

    handler = _get_domain_handler(domain)
    if handler is None:
        return json.dumps({"error": f"unknown domain: {domain}"})

    use_memory = params.get("use_memory", True)
    store_result = params.get("store_result", True)
    trust_threshold = params.get("memory_trust_threshold", 0.5)

    memory_context = []

    # Step 1: Hydrate from memory
    if use_memory and ctx is not None:
        try:
            bridge = _get_bridge(ctx, trust_threshold)
            # Extract entities from state or tasks
            entity_names = []
            if params.get("state"):
                entity_names = _extract_entities_from_state(params["state"])
            elif params.get("tasks"):
                for task in params["tasks"]:
                    if isinstance(task, (list, tuple)):
                        entity_names.extend(str(a) for a in task[1:])

            if entity_names:
                result = bridge.hydrate_capability_state(entity_names, domain)
                memory_context = result.get("memory_context", [])
                logger.info(
                    "Hydrated %d facts from memory for %d entities",
                    len(memory_context), len(entity_names),
                )
        except Exception as exc:
            logger.warning("Memory hydration failed (proceeding without): %s", exc)

    # Step 1b: Store state bindings into holographic memory so future
    # probe(entity) can recall them.  Uses encode_binding (= Lean encodeFact)
    # which satisfies the GoalStateEquivalence proofs.
    if use_memory and ctx is not None and params.get("state"):
        try:
            bridge = _get_bridge(ctx, trust_threshold)
            bridge.store_state_bindings(params["state"], domain)
        except Exception as exc:
            logger.debug("State binding storage failed: %s", exc)

    # Step 1c: Store goal bindings using the SAME encoding as state
    # (Lean: encoding_independent_of_source, satisfaction_iff_encoding_eq)
    if use_memory and ctx is not None and params.get("goals"):
        try:
            bridge = _get_bridge(ctx, trust_threshold)
            goals = params["goals"]
            if isinstance(goals, dict):
                bridge.store_goal_bindings(goals, domain)
            elif isinstance(goals, list):
                for g in goals:
                    if isinstance(g, dict):
                        bridge.store_goal_bindings(g, domain)
        except Exception as exc:
            logger.debug("Goal binding storage failed: %s", exc)

    # Step 2: Delegate to domain handler
    plan_params = {k: v for k, v in params.items()
                   if k not in ("use_memory", "store_result", "memory_trust_threshold")}
    result_json = handler(plan_params, **kwargs)

    # Step 3: Store result in memory
    if store_result and ctx is not None:
        try:
            result_data = json.loads(result_json)
            plan = result_data.get("plan", [])
            if plan:
                bridge = _get_bridge(ctx, trust_threshold)
                entity_names = []
                if params.get("tasks"):
                    for task in params["tasks"]:
                        if isinstance(task, (list, tuple)):
                            entity_names.extend(str(a) for a in task[1:])
                bridge.store_plan_result(plan, domain, entity_names, params.get("tasks"))
        except Exception as exc:
            logger.warning("Failed to store plan result in memory: %s", exc)

    # Augment result with memory context
    try:
        result_data = json.loads(result_json)
        if memory_context:
            result_data["memory_context"] = [
                {"fact_id": f.get("fact_id"), "content": f.get("content"),
                 "trust": f.get("trust_score")}
                for f in memory_context
            ]
        return json.dumps(result_data)
    except (json.JSONDecodeError, TypeError):
        return result_json


def handle_recall_plans(params: dict[str, Any], ctx: Any = None, **kwargs: Any) -> str:
    """Algebraic recall of past planning contexts from holographic memory."""
    entities = params.get("entities")
    if not entities:
        return json.dumps({"error": "entities is required"})

    if ctx is None:
        return json.dumps({"error": "no context available"})

    try:
        bridge = _get_bridge(ctx)
        facts = bridge.recall_planning_context(
            entities=entities,
            domain=params.get("domain"),
            limit=params.get("limit", 5),
        )
        return json.dumps({
            "plans": [
                {"fact_id": f.get("fact_id"), "content": f.get("content"),
                 "trust": f.get("trust_score"), "entities": f.get("entities", [])}
                for f in facts
            ],
            "count": len(facts),
        })
    except Exception as exc:
        return json.dumps({"error": str(exc)})

