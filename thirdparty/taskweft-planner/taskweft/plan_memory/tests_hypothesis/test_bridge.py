"""Hypothesis property-based tests for plan_memory.bridge and helpers.

Lighter tests focusing on:
- The _RE_RELATION regex pattern and _RELATION_KEYWORDS mapping
- The _extract_entities_from_state helper
- PlanMemoryBridge with mock store/retriever
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional
from unittest.mock import MagicMock

# Ensure taskweft and plan directories are importable
_TASKWEFT_DIR = Path(__file__).resolve().parent.parent.parent
_PLAN_DIR = _TASKWEFT_DIR / "plan"
for _d in (str(_TASKWEFT_DIR), str(_PLAN_DIR)):
    if _d not in sys.path:
        sys.path.insert(0, _d)

import pytest
from hypothesis import given, settings, assume
from hypothesis import strategies as st

from taskweft.plan_memory.bridge import (
    PlanMemoryBridge,
    _RE_RELATION,
    _RELATION_KEYWORDS,
)
from taskweft.plan_memory import _extract_entities_from_state


# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

_word = st.text(
    alphabet=st.characters(whitelist_categories=("Ll", "Lu"), whitelist_characters="_"),
    min_size=2,
    max_size=15,
).filter(lambda s: s[0].isalpha())

# All verbs the regex can match
_all_relation_verbs = [
    "owns",
    "controls",
    "delegated to",
    "delegates to",
    "has capability",
    "is member of",
    "belongs to",
    "supervises",
    "partner of",
]
_relation_verbs = st.sampled_from(_all_relation_verbs)

# Verbs whose first word is in _RELATION_KEYWORDS (i.e., will produce edges)
_edge_producing_verbs = st.sampled_from([
    "owns",        # first word "owns" -> OWNS
    "controls",    # first word "controls" -> CONTROLS
    "delegated to",  # first word "delegated" -> DELEGATED_TO
    "delegates to",  # first word "delegates" -> DELEGATED_TO
    "belongs to",    # first word "belongs" -> IS_MEMBER_OF
    "supervises",    # first word "supervises" -> SUPERVISOR_OF
    "partner of",    # first word "partner" -> PARTNER_OF
])


# ---------------------------------------------------------------------------
# _RE_RELATION regex: well-formed sentences match
# ---------------------------------------------------------------------------

@given(subj=_word, verb=_relation_verbs, obj=_word)
@settings(max_examples=100)
def test_regex_matches_well_formed_sentence(subj: str, verb: str, obj: str):
    """A sentence of form 'subj VERB obj.' should match _RE_RELATION."""
    assume(subj.strip() == subj and obj.strip() == obj)
    assume(len(subj) > 0 and len(obj) > 0)
    sentence = f"{subj} {verb} {obj}."
    matches = list(_RE_RELATION.finditer(sentence))
    assert len(matches) >= 1, f"Expected match for: {sentence!r}"
    m = matches[0]
    assert m.group(1).strip() == subj
    assert m.group(3).strip() == obj


# ---------------------------------------------------------------------------
# _RE_RELATION regex: random non-relation text does not match
# ---------------------------------------------------------------------------

@given(
    text=st.text(
        alphabet=st.characters(whitelist_categories=("L", "N", "Z"), whitelist_characters=",.!?"),
        min_size=0,
        max_size=60,
    )
)
@settings(max_examples=80)
def test_regex_no_false_positives_on_noise(text: str):
    """Random text without relation verbs should rarely match.

    We only assert that if it matches, the verb group is one of the known
    relation patterns (i.e. no spurious verb capture).
    """
    known_verbs = {
        "owns", "controls", "delegated to", "delegates to",
        "has capability", "is member of", "belongs to",
        "supervises", "partner of",
    }
    for m in _RE_RELATION.finditer(text):
        verb = m.group(2).strip().lower()
        assert verb in known_verbs, f"Unexpected verb captured: {verb!r}"


# ---------------------------------------------------------------------------
# _RELATION_KEYWORDS: every first-word key maps to a valid RelationshipType name
# ---------------------------------------------------------------------------

def test_relation_keywords_valid():
    """Every value in _RELATION_KEYWORDS is a valid RelationshipType name."""
    from taskweft.plan.ipyhop.capabilities import RelationshipType
    for keyword, rel_name in _RELATION_KEYWORDS.items():
        assert hasattr(RelationshipType, rel_name), (
            f"_RELATION_KEYWORDS[{keyword!r}] = {rel_name!r} is not a RelationshipType member"
        )


# ---------------------------------------------------------------------------
# _extract_entities_from_state: extracts inner dict keys (non-rigid)
# ---------------------------------------------------------------------------

@given(
    outer_keys=st.lists(_word, min_size=1, max_size=5, unique=True),
    inner_keys=st.lists(_word, min_size=1, max_size=5, unique=True),
)
@settings(max_examples=80)
def test_extract_entities_from_state_dict_keys(outer_keys, inner_keys):
    """Inner dict keys (not starting with 'rigid') should be extracted."""
    assume(all(not k.startswith("rigid") for k in inner_keys))
    state = {}
    for ok in outer_keys:
        state[ok] = {ik: "value" for ik in inner_keys}

    entities = _extract_entities_from_state(state)
    for ik in inner_keys:
        assert ik in entities, f"{ik} should have been extracted"


@given(
    outer_keys=st.lists(_word, min_size=1, max_size=3, unique=True),
    rigid_keys=st.lists(
        st.text(
            alphabet=st.characters(whitelist_categories=("L",)),
            min_size=1,
            max_size=10,
        ).map(lambda s: "rigid" + s),
        min_size=1,
        max_size=3,
        unique=True,
    ),
)
@settings(max_examples=60)
def test_extract_entities_filters_rigid(outer_keys, rigid_keys):
    """Keys starting with 'rigid' are excluded from entity extraction."""
    state = {}
    for ok in outer_keys:
        state[ok] = {rk: "value" for rk in rigid_keys}

    entities = _extract_entities_from_state(state)
    for rk in rigid_keys:
        assert rk not in entities, f"rigid key {rk} should have been filtered"


@given(
    outer_keys=st.lists(_word, min_size=1, max_size=3, unique=True),
    scalar_vals=st.lists(st.integers(), min_size=1, max_size=3),
)
@settings(max_examples=50)
def test_extract_entities_ignores_non_dict_values(outer_keys, scalar_vals):
    """Non-dict state values should produce no entities."""
    state = {}
    for ok, sv in zip(outer_keys, scalar_vals):
        state[ok] = sv

    entities = _extract_entities_from_state(state)
    assert entities == []


# ---------------------------------------------------------------------------
# PlanMemoryBridge with mock store/retriever
# ---------------------------------------------------------------------------

class _MockRetriever:
    """Minimal mock retriever returning canned facts."""

    def __init__(self, facts: List[Dict]):
        self._facts = facts

    def probe(self, entity, category=None, limit=20):
        return [f for f in self._facts if entity.lower() in f.get("content", "").lower()][:limit]

    def search(self, query, category=None, limit=20):
        return self.probe(query, category, limit)

    def reason(self, entities, category=None, limit=10):
        results = []
        for f in self._facts:
            content = f.get("content", "").lower()
            if all(e.lower() in content for e in entities):
                results.append(f)
        return results[:limit]


class _MockStore:
    """Minimal mock store that records add_fact calls."""

    def __init__(self):
        self.facts: List[Dict] = []
        self._next_id = 1

    def add_fact(self, content: str, category: str = "", tags: str = "") -> int:
        fid = self._next_id
        self._next_id += 1
        self.facts.append({"fact_id": fid, "content": content, "category": category, "tags": tags})
        return fid


@given(
    subj=_word,
    obj=_word,
    verb=_edge_producing_verbs,
)
@settings(max_examples=60)
def test_hydrate_parses_facts_into_edges(subj, obj, verb):
    """hydrate_capability_state should parse 'subj VERB obj.' facts into engine edges."""
    assume(subj != obj)
    assume(subj.strip() == subj and obj.strip() == obj)
    fact_content = f"{subj} {verb} {obj}."
    facts = [
        {"fact_id": 1, "content": fact_content, "trust_score": 0.9}
    ]
    retriever = _MockRetriever(facts)
    store = _MockStore()
    bridge = PlanMemoryBridge(store, retriever, trust_threshold=0.5)

    result = bridge.hydrate_capability_state([subj])
    engine = result["engine"]

    # The engine should have at least one edge
    assert len(engine._edges) >= 1, (
        f"Expected edges from fact: {fact_content!r}"
    )


@given(
    subj=_word,
    obj=_word,
    verb=_relation_verbs,
    trust=st.floats(min_value=0.0, max_value=0.49),
)
@settings(max_examples=50)
def test_hydrate_filters_low_trust(subj, obj, verb, trust):
    """Facts below trust_threshold are excluded from hydration."""
    assume(subj != obj)
    fact_content = f"{subj} {verb} {obj}."
    facts = [
        {"fact_id": 1, "content": fact_content, "trust_score": trust}
    ]
    retriever = _MockRetriever(facts)
    store = _MockStore()
    bridge = PlanMemoryBridge(store, retriever, trust_threshold=0.5)

    result = bridge.hydrate_capability_state([subj])
    # Low-trust facts should be filtered out
    assert result["memory_context"] == []


@given(
    domain=_word,
    entities=st.lists(_word, min_size=1, max_size=3, unique=True),
    n_steps=st.integers(min_value=1, max_value=5),
)
@settings(max_examples=50)
def test_store_plan_result_creates_facts(domain, entities, n_steps):
    """store_plan_result should write summary + step facts to the store."""
    store = _MockStore()
    retriever = _MockRetriever([])
    bridge = PlanMemoryBridge(store, retriever)

    plan_json = [["action", f"arg{i}"] for i in range(n_steps)]
    fact_ids = bridge.store_plan_result(plan_json, domain, entities)

    # 1 summary + n_steps individual step facts
    assert len(fact_ids) == 1 + n_steps
    assert len(store.facts) == 1 + n_steps


@given(entity=_word)
@settings(max_examples=50)
def test_recall_single_entity_uses_probe(entity):
    """recall_planning_context with one entity delegates to probe."""
    facts = [
        {"fact_id": 1, "content": f"Plan for {entity}", "trust_score": 0.9}
    ]
    retriever = _MockRetriever(facts)
    store = _MockStore()
    bridge = PlanMemoryBridge(store, retriever)

    result = bridge.recall_planning_context([entity])
    assert isinstance(result, list)
    # Should find the fact containing the entity name
    assert len(result) >= 1


@given(
    e1=_word,
    e2=_word,
)
@settings(max_examples=50)
def test_recall_multi_entity_uses_reason(e1, e2):
    """recall_planning_context with 2+ entities delegates to reason."""
    assume(e1 != e2)
    facts = [
        {"fact_id": 1, "content": f"Plan involving {e1} and {e2}", "trust_score": 0.9}
    ]
    retriever = _MockRetriever(facts)
    store = _MockStore()
    bridge = PlanMemoryBridge(store, retriever)

    result = bridge.recall_planning_context([e1, e2])
    assert isinstance(result, list)


# ---------------------------------------------------------------------------
# State / Goal encoding equivalence tests
#
# These tests use state tuples (mock store) to verify the Lean-proved
# invariant: State and MultiGoal bindings produce the SAME canonical
# content string for the same (var, arg, val) triple.
#
# In production, the SQLite-backed holographic MemoryStore computes
# encode_binding(content, entity) per entity, which equals the Lean
# encodeFact = bind(content, entity).  The mock store captures the
# content strings so we can verify encoding equivalence without numpy.
# ---------------------------------------------------------------------------


def test_binding_to_content_canonical():
    """_binding_to_content produces a deterministic canonical string."""
    assert PlanMemoryBridge._binding_to_content("loc", "alice", "park") == "loc alice park"
    assert PlanMemoryBridge._binding_to_content("pos", "a", "table") == "pos a table"


@given(
    var_name=_word,
    arg=_word,
    val=_word,
)
@settings(max_examples=80)
def test_state_goal_same_encoding(var_name, arg, val):
    """State and Goal bindings with the same (var, arg, val) produce
    identical content strings in the store.

    Corresponds to Lean theorem: encoding_independent_of_source
    """
    store = _MockStore()
    retriever = _MockRetriever([])
    bridge = PlanMemoryBridge(store, retriever)

    # Store as state binding
    state_dict = {var_name: {arg: val}}
    state_ids = bridge.store_state_bindings(state_dict, "test_domain")
    state_contents = [f["content"] for f in store.facts]

    # Reset store, store as goal binding
    store2 = _MockStore()
    bridge2 = PlanMemoryBridge(store2, _MockRetriever([]))
    goal_dict = {var_name: {arg: val}}
    goal_ids = bridge2.store_goal_bindings(goal_dict, "test_domain")
    goal_contents = [f["content"] for f in store2.facts]

    # Both must produce the same content (Lean: satisfaction_iff_encoding_eq)
    assert state_contents == goal_contents, (
        f"State and Goal produced different content for ({var_name}, {arg}, {val}): "
        f"state={state_contents}, goal={goal_contents}"
    )


@given(
    var_name=_word,
    arg=_word,
    state_val=_word,
    goal_val=_word,
)
@settings(max_examples=80)
def test_different_vals_different_content(var_name, arg, state_val, goal_val):
    """Different values produce different content strings.

    Corresponds to Lean theorem: unsatisfied_probe_nonzero
    """
    assume(state_val != goal_val)

    content_s = PlanMemoryBridge._binding_to_content(var_name, arg, state_val)
    content_g = PlanMemoryBridge._binding_to_content(var_name, arg, goal_val)

    assert content_s != content_g, (
        f"Different values produced same content: {content_s}"
    )


@given(
    bindings=st.dictionaries(
        keys=_word,
        values=st.dictionaries(keys=_word, values=_word, min_size=1, max_size=3),
        min_size=1,
        max_size=3,
    ),
)
@settings(max_examples=50)
def test_store_state_bindings_roundtrip(bindings):
    """store_state_bindings writes one fact per (var, arg, val) triple.

    In production, the SQLite-backed MemoryStore would compute
    encode_binding(content, entity) for each entity in the content,
    enabling algebraic probe(entity) recall.
    """
    store = _MockStore()
    bridge = PlanMemoryBridge(store, _MockRetriever([]))

    fact_ids = bridge.store_state_bindings(bindings, "test_domain")

    # Count expected bindings
    expected_count = sum(len(v) for v in bindings.values() if isinstance(v, dict))
    assert len(fact_ids) == expected_count
    assert len(store.facts) == expected_count

    # Each stored fact should have category="state"
    for fact in store.facts:
        assert fact["category"] == "state"


@given(
    bindings=st.dictionaries(
        keys=_word,
        values=st.dictionaries(keys=_word, values=_word, min_size=1, max_size=3),
        min_size=1,
        max_size=3,
    ),
)
@settings(max_examples=50)
def test_store_goal_bindings_roundtrip(bindings):
    """store_goal_bindings writes one fact per (var, arg, val) triple."""
    store = _MockStore()
    bridge = PlanMemoryBridge(store, _MockRetriever([]))

    fact_ids = bridge.store_goal_bindings(bindings, "test_domain")

    expected_count = sum(len(v) for v in bindings.values() if isinstance(v, dict))
    assert len(fact_ids) == expected_count

    # Each stored fact should have category="goal"
    for fact in store.facts:
        assert fact["category"] == "goal"


def test_private_vars_skipped():
    """State bindings skip private/internal attributes."""
    store = _MockStore()
    bridge = PlanMemoryBridge(store, _MockRetriever([]))

    state_dict = {
        "__name__": "test",
        "_current_time": "2025-01-01T00:00:00Z",
        "_timeline": [],
        "rigid": {"types": {"person": ["alice"]}},
        "loc": {"alice": "park"},  # only this should be stored
    }
    fact_ids = bridge.store_state_bindings(state_dict, "test")

    assert len(fact_ids) == 1
    assert store.facts[0]["content"] == "loc alice park"


def test_goal_tag_skipped():
    """Goal bindings skip goal_tag attribute."""
    store = _MockStore()
    bridge = PlanMemoryBridge(store, _MockRetriever([]))

    goal_dict = {
        "__name__": "goal1",
        "goal_tag": "loc",
        "loc": {"alice": "park"},
    }
    fact_ids = bridge.store_goal_bindings(goal_dict, "test")

    assert len(fact_ids) == 1
    assert store.facts[0]["content"] == "loc alice park"
