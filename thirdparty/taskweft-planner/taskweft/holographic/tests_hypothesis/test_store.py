"""Property-based tests for MemoryStore (store.py).

Tests add_fact, list_facts, remove_fact, record_feedback, trust clamping,
and _extract_entities using Hypothesis strategies.
"""

import tempfile
import os
import pytest

from hypothesis import given, settings, assume
from hypothesis import strategies as st

import sys
from pathlib import Path

# Import modules directly (bypass __init__.py which needs 'agent' package)
import importlib.util as _ilu
_holo_dir = Path(__file__).resolve().parent.parent

# Pre-register holographic.py as 'holographic' in sys.modules so store.py's
# fallback `import holographic as hrr` finds it instead of __init__.py
_hrr_path = str(_holo_dir / "holographic.py")
_hrr_spec = _ilu.spec_from_file_location("holographic", _hrr_path)
_hrr_mod = _ilu.module_from_spec(_hrr_spec)
_hrr_spec.loader.exec_module(_hrr_mod)
sys.modules["holographic"] = _hrr_mod

_store_path = str(_holo_dir / "store.py")
_store_spec = _ilu.spec_from_file_location("holographic_store", _store_path)
_store_mod = _ilu.module_from_spec(_store_spec)
_store_spec.loader.exec_module(_store_mod)
MemoryStore = _store_mod.MemoryStore
_clamp_trust = _store_mod._clamp_trust


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_store(tmp_dir: str) -> MemoryStore:
    """Create a MemoryStore backed by a temporary SQLite database."""
    db_path = os.path.join(tmp_dir, "test_memory.db")
    return MemoryStore(db_path=db_path)


# Strategy for non-empty fact content: printable strings that are not blank.
_content_strategy = st.text(
    alphabet=st.characters(whitelist_categories=("L", "N", "P", "Z"), whitelist_characters=" "),
    min_size=1,
    max_size=200,
).filter(lambda s: s.strip())


# ---------------------------------------------------------------------------
# add_fact
# ---------------------------------------------------------------------------


class TestAddFact:
    @given(content=_content_strategy)
    @settings(max_examples=60)
    def test_returns_positive_id(self, content):
        """add_fact always returns a positive integer ID."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                fact_id = store.add_fact(content)
                assert isinstance(fact_id, int)
                assert fact_id > 0
            finally:
                store.close()

    @given(content=_content_strategy)
    @settings(max_examples=50)
    def test_deduplication(self, content):
        """Adding the same content twice returns the same ID."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                id1 = store.add_fact(content)
                id2 = store.add_fact(content)
                assert id1 == id2
            finally:
                store.close()

    @given(content=_content_strategy)
    @settings(max_examples=50)
    def test_list_after_add(self, content):
        """After adding a fact, list_facts should return it."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                store.add_fact(content)
                facts = store.list_facts()
                contents = [f["content"] for f in facts]
                assert content.strip() in contents
            finally:
                store.close()


# ---------------------------------------------------------------------------
# remove_fact
# ---------------------------------------------------------------------------


class TestRemoveFact:
    @given(content=_content_strategy)
    @settings(max_examples=50)
    def test_remove_makes_fact_disappear(self, content):
        """After removing a fact, it should not appear in list_facts."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                fact_id = store.add_fact(content)
                removed = store.remove_fact(fact_id)
                assert removed is True
                facts = store.list_facts()
                ids = [f["fact_id"] for f in facts]
                assert fact_id not in ids
            finally:
                store.close()

    def test_remove_nonexistent(self):
        """Removing a non-existent fact returns False."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                assert store.remove_fact(999999) is False
            finally:
                store.close()


# ---------------------------------------------------------------------------
# record_feedback / trust
# ---------------------------------------------------------------------------


class TestRecordFeedback:
    @given(content=_content_strategy)
    @settings(max_examples=50)
    def test_helpful_increases_trust(self, content):
        """Marking a fact as helpful should increase (or maintain) trust."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                fact_id = store.add_fact(content)
                result = store.record_feedback(fact_id, helpful=True)
                assert result["new_trust"] >= result["old_trust"]
            finally:
                store.close()

    @given(content=_content_strategy)
    @settings(max_examples=50)
    def test_unhelpful_decreases_trust(self, content):
        """Marking a fact as unhelpful should decrease (or maintain) trust."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                fact_id = store.add_fact(content)
                result = store.record_feedback(fact_id, helpful=False)
                assert result["new_trust"] <= result["old_trust"]
            finally:
                store.close()

    @given(
        content=_content_strategy,
        n_helpful=st.integers(min_value=0, max_value=30),
        n_unhelpful=st.integers(min_value=0, max_value=30),
    )
    @settings(max_examples=50)
    def test_trust_clamped(self, content, n_helpful, n_unhelpful):
        """Trust must always stay within [0.0, 1.0] regardless of feedback count."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                fact_id = store.add_fact(content)
                for _ in range(n_helpful):
                    store.record_feedback(fact_id, helpful=True)
                for _ in range(n_unhelpful):
                    store.record_feedback(fact_id, helpful=False)
                facts = store.list_facts(min_trust=0.0)
                for f in facts:
                    if f["fact_id"] == fact_id:
                        assert 0.0 <= f["trust_score"] <= 1.0
                        break
            finally:
                store.close()

    def test_feedback_nonexistent_raises(self):
        """Feedback on a non-existent fact should raise KeyError."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                with pytest.raises(KeyError):
                    store.record_feedback(999999, helpful=True)
            finally:
                store.close()


# ---------------------------------------------------------------------------
# _clamp_trust
# ---------------------------------------------------------------------------


class TestClampTrust:
    @given(value=st.floats(min_value=-100.0, max_value=100.0, allow_nan=False))
    @settings(max_examples=100)
    def test_clamp_range(self, value):
        """_clamp_trust always returns a value in [0.0, 1.0]."""
        result = _clamp_trust(value)
        assert 0.0 <= result <= 1.0

    @given(value=st.floats(min_value=0.0, max_value=1.0, allow_nan=False))
    @settings(max_examples=50)
    def test_clamp_identity_in_range(self, value):
        """Values already in [0, 1] are unchanged."""
        assert _clamp_trust(value) == value


# ---------------------------------------------------------------------------
# _extract_entities
# ---------------------------------------------------------------------------


class TestExtractEntities:
    @given(
        first=st.sampled_from("ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        rest=st.text(
            alphabet=st.sampled_from("abcdefghijklmnopqrstuvwxyz"),
            min_size=1,
            max_size=8,
        ),
        first2=st.sampled_from("ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        rest2=st.text(
            alphabet=st.sampled_from("abcdefghijklmnopqrstuvwxyz"),
            min_size=1,
            max_size=8,
        ),
    )
    @settings(max_examples=80)
    def test_finds_capitalized_multi_word(self, first, rest, first2, rest2):
        """Capitalized multi-word phrases are detected as entities."""
        name = f"{first}{rest} {first2}{rest2}"
        text = f"I met {name} yesterday."
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                entities = store._extract_entities(text)
                # The regex looks for multi-word capitalized sequences.
                # Our constructed name should match.
                lowered = [e.lower() for e in entities]
                assert name.lower() in lowered
            finally:
                store.close()

    def test_quoted_entities(self):
        """Double-quoted terms are extracted."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                entities = store._extract_entities('He uses "Python" for work.')
                lowered = [e.lower() for e in entities]
                assert "python" in lowered
            finally:
                store.close()

    def test_empty_text(self):
        """Empty text yields no entities."""
        with tempfile.TemporaryDirectory() as tmp:
            store = _make_store(tmp)
            try:
                assert store._extract_entities("") == []
            finally:
                store.close()
