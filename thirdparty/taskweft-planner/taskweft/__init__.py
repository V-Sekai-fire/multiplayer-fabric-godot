"""taskweft — Temporal entity-capability goal task network with holographic memory.

Combines three capabilities:
  holographic  — HRR algebra, SQLite fact store, hybrid retrieval
  plan         — HTN planner (IPyHOP) over six built-in domains
  plan_memory  — Memory-augmented planning and algebraic plan recall via ReBAC
"""

import json
from pathlib import Path

# Re-export holographic public API
from .holographic import (
    bind,
    bundle,
    bytes_to_phases,
    encode_atom,
    encode_binding,
    encode_fact,
    encode_text,
    phases_to_bytes,
    similarity,
    snr_estimate,
    unbind,
    MemoryStore,
    FactRetriever,
)

# Plan tool handler
from .plan.tools import handle_taskweft

# Plan-memory tool handlers
from .plan_memory import (
    handle_plan_with_memory,
    handle_recall_plans,
)

_PLAN_SCHEMAS = Path(__file__).parent / "plan" / "schemas"
_PLAN_MEMORY_SCHEMAS = Path(__file__).parent / "plan_memory" / "schemas"

_TOOLS = [
    # JSON-LD planner (plan / simulate / replan)
    ("taskweft",                   _PLAN_SCHEMAS,        handle_taskweft),
    # Plan-memory tools
    ("plan_with_memory",           _PLAN_MEMORY_SCHEMAS, handle_plan_with_memory),
    ("recall_plans",               _PLAN_MEMORY_SCHEMAS, handle_recall_plans),
]


def register(ctx):
    """Register all taskweft tools with the Hermes plugin system."""
    plugin_name = ctx.manifest.name
    for name, schemas_dir, handler in _TOOLS:
        schema = json.loads((schemas_dir / f"{name}.json").read_text())
        ctx.register_tool(name, plugin_name, schema, handler)
