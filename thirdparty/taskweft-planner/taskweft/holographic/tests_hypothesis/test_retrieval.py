"""Property-based tests for FactRetriever (retrieval.py).

Tests _jaccard_similarity, _tokenize, and search using Hypothesis strategies.
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

_retrieval_path = str(_holo_dir / "retrieval.py")
_retrieval_spec = _ilu.spec_from_file_location("holographic_retrieval", _retrieval_path)
_retrieval_mod = _ilu.module_from_spec(_retrieval_spec)
_retrieval_spec.loader.exec_module(_retrieval_mod)
FactRetriever = _retrieval_mod.FactRetriever


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_store_and_retriever(tmp_dir: str):
    """Create a MemoryStore and FactRetriever backed by a temp database."""
    db_path = os.path.join(tmp_dir, "test_retrieval.db")
    store = MemoryStore(db_path=db_path)
    retriever = FactRetriever(store)
    return store, retriever


# Strategy for non-empty word tokens (lowercase alpha).
_word_strategy = st.text(
    alphabet=st.characters(whitelist_categories=("Ll",)),
    min_size=1,
    max_size=15,
)

# Strategy for sets of words.
_word_set_strategy = st.frozensets(_word_strategy, min_size=0, max_size=20)


# ---------------------------------------------------------------------------
# _jaccard_similarity
# ---------------------------------------------------------------------------


class TestJaccardSimilarity:
    @given(s=_word_set_strategy)
    @settings(max_examples=80)
    def test_identical_sets(self, s):
        """Jaccard similarity of a non-empty set with itself is 1.0."""
        assume(len(s) > 0)
        assert FactRetriever._jaccard_similarity(set(s), set(s)) == 1.0

    def test_empty_sets(self):
        """Empty sets yield 0.0."""
        assert FactRetriever._jaccard_similarity(set(), set()) == 0.0
        assert FactRetriever._jaccard_similarity({"a"}, set()) == 0.0
        assert FactRetriever._jaccard_similarity(set(), {"b"}) == 0.0

    @given(a=_word_set_strategy, b=_word_set_strategy)
    @settings(max_examples=80)
    def test_range(self, a, b):
        """Jaccard similarity is always in [0, 1]."""
        sim = FactRetriever._jaccard_similarity(set(a), set(b))
        assert 0.0 <= sim <= 1.0

    @given(a=_word_set_strategy, b=_word_set_strategy)
    @settings(max_examples=60)
    def test_symmetry(self, a, b):
        """Jaccard similarity is symmetric."""
        sim_ab = FactRetriever._jaccard_similarity(set(a), set(b))
        sim_ba = FactRetriever._jaccard_similarity(set(b), set(a))
        assert sim_ab == sim_ba

    @given(
        common=_word_set_strategy.filter(lambda s: len(s) > 0),
        extra_a=_word_set_strategy,
        extra_b=_word_set_strategy,
    )
    @settings(max_examples=60)
    def test_subset_monotonicity(self, common, extra_a, extra_b):
        """Adding elements to only one set should not increase Jaccard similarity."""
        a = set(common)
        b = set(common)
        sim_equal = FactRetriever._jaccard_similarity(a, b)

        # Add extras to b only
        b_extended = b | set(extra_b)
        if b_extended != b:
            sim_extended = FactRetriever._jaccard_similarity(a, b_extended)
            assert sim_extended <= sim_equal + 1e-12


# ---------------------------------------------------------------------------
# _tokenize
# ---------------------------------------------------------------------------


class TestTokenize:
    @given(text=st.text(min_size=0, max_size=200))
    @settings(max_examples=80)
    def test_returns_set_of_strings(self, text):
        """_tokenize always returns a set of strings."""
        result = FactRetriever._tokenize(text)
        assert isinstance(result, set)
        for token in result:
            assert isinstance(token, str)

    @given(text=st.text(min_size=1, max_size=200))
    @settings(max_examples=80)
    def test_all_lowercase(self, text):
        """All tokens are lowercase."""
        result = FactRetriever._tokenize(text)
        for token in result:
            assert token == token.lower()

    def test_empty_string(self):
        """Empty string produces an empty set."""
        assert FactRetriever._tokenize("") == set()

    def test_punctuation_stripped(self):
        """Leading/trailing punctuation is stripped from tokens."""
        result = FactRetriever._tokenize('"Hello," she said.')
        # "hello" and "she" and "said" should appear without quotes/commas/periods
        assert "hello" in result or "hello," not in result
        for token in result:
            assert not token.startswith('"')
            assert not token.endswith(",")
            assert not token.endswith(".")


# ---------------------------------------------------------------------------
# search integration
# ---------------------------------------------------------------------------


class TestSearch:
    def test_search_returns_list_of_dicts(self):
        """search returns a list of dicts with expected keys."""
        with tempfile.TemporaryDirectory() as tmp:
            store, retriever = _make_store_and_retriever(tmp)
            try:
                store.add_fact("The quick brown fox jumps over the lazy dog")
                store.add_fact("Python is a programming language")
                results = retriever.search("fox")
                assert isinstance(results, list)
                for r in results:
                    assert isinstance(r, dict)
                    # Must have at least these keys
                    assert "fact_id" in r
                    assert "content" in r
                    assert "trust_score" in r
                    assert "score" in r
            finally:
                store.close()

    def test_search_empty_query(self):
        """Empty query returns empty list."""
        with tempfile.TemporaryDirectory() as tmp:
            store, retriever = _make_store_and_retriever(tmp)
            try:
                store.add_fact("Some fact content here")
                results = retriever.search("")
                assert results == []
            finally:
                store.close()

    @given(
        word1=st.text(
            alphabet=st.characters(whitelist_categories=("Ll",)),
            min_size=3,
            max_size=15,
        ),
        word2=st.text(
            alphabet=st.characters(whitelist_categories=("Ll",)),
            min_size=3,
            max_size=15,
        ),
    )
    @settings(max_examples=30)
    def test_search_scores_non_negative(self, word1, word2):
        """All search result scores should be non-negative."""
        content = f"{word1} {word2}"
        with tempfile.TemporaryDirectory() as tmp:
            store, retriever = _make_store_and_retriever(tmp)
            try:
                store.add_fact(content)
                results = retriever.search(word1)
                for r in results:
                    assert r["score"] >= 0.0
            finally:
                store.close()

    def test_search_respects_limit(self):
        """search does not return more results than the limit."""
        with tempfile.TemporaryDirectory() as tmp:
            store, retriever = _make_store_and_retriever(tmp)
            try:
                for i in range(20):
                    store.add_fact(f"Fact number {i} about testing things")
                results = retriever.search("testing", limit=5)
                assert len(results) <= 5
            finally:
                store.close()
