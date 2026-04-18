"""Property-based tests for HRR algebra (holographic.py).

Tests encode_atom, bind, unbind, bundle, similarity, phases_to_bytes,
bytes_to_phases, encode_fact, and snr_estimate using Hypothesis strategies.
"""

import math
import pytest

try:
    import numpy as np
    _HAS_NUMPY = True
except ImportError:
    _HAS_NUMPY = False

from hypothesis import given, settings, assume
from hypothesis import strategies as st

# Skip the entire module if numpy is not available.
pytestmark = pytest.mark.skipif(not _HAS_NUMPY, reason="numpy is required")

import sys
from pathlib import Path

# Import holographic.py module directly (bypass __init__.py which needs 'agent' package)
import importlib.util as _ilu
_hrr_path = str(Path(__file__).resolve().parent.parent / "holographic.py")
_hrr_spec = _ilu.spec_from_file_location("holographic_hrr", _hrr_path)
_hrr_mod = _ilu.module_from_spec(_hrr_spec)
_hrr_spec.loader.exec_module(_hrr_mod)

encode_atom = _hrr_mod.encode_atom
bind = _hrr_mod.bind
unbind = _hrr_mod.unbind
bundle = _hrr_mod.bundle
similarity = _hrr_mod.similarity
encode_text = _hrr_mod.encode_text
encode_fact = _hrr_mod.encode_fact
encode_binding = _hrr_mod.encode_binding
phases_to_bytes = _hrr_mod.phases_to_bytes
bytes_to_phases = _hrr_mod.bytes_to_phases
snr_estimate = _hrr_mod.snr_estimate

del _hrr_path, _hrr_spec, _hrr_mod

# ---------------------------------------------------------------------------
# Strategies
# ---------------------------------------------------------------------------

# Words: printable ASCII letters plus underscore, length 1-30.
_word_strategy = st.text(
    alphabet=st.characters(whitelist_categories=("L", "N"), whitelist_characters="_"),
    min_size=1,
    max_size=30,
)

# Dimensions: small to keep tests fast but large enough for statistical properties.
_dim_strategy = st.sampled_from([64, 128, 256, 512])


# ---------------------------------------------------------------------------
# encode_atom
# ---------------------------------------------------------------------------


class TestEncodeAtom:
    @given(word=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=80)
    def test_determinism(self, word, dim):
        """Same word and dim always produce the same vector."""
        v1 = encode_atom(word, dim)
        v2 = encode_atom(word, dim)
        np.testing.assert_array_equal(v1, v2)

    @given(word=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=80)
    def test_output_shape(self, word, dim):
        """Output shape matches the requested dimension."""
        v = encode_atom(word, dim)
        assert v.shape == (dim,)

    @given(word=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=80)
    def test_phase_range(self, word, dim):
        """All phase values lie in [0, 2*pi)."""
        v = encode_atom(word, dim)
        assert np.all(v >= 0.0)
        assert np.all(v < 2.0 * math.pi)


# ---------------------------------------------------------------------------
# bind / unbind inverse property
# ---------------------------------------------------------------------------


class TestBindUnbind:
    @given(w1=_word_strategy, w2=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=80)
    def test_inverse_property(self, w1, w2, dim):
        """unbind(bind(a, b), a) should be similar to b."""
        a = encode_atom(w1, dim)
        b = encode_atom(w2, dim)
        bound = bind(a, b)
        recovered = unbind(bound, a)
        sim = similarity(recovered, b)
        # Exact inverse in phase arithmetic => similarity should be ~1.0
        assert sim > 0.99, f"Expected sim > 0.99, got {sim}"

    @given(w1=_word_strategy, w2=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=50)
    def test_bind_output_shape(self, w1, w2, dim):
        """bind preserves dimensionality."""
        a = encode_atom(w1, dim)
        b = encode_atom(w2, dim)
        result = bind(a, b)
        assert result.shape == (dim,)


# ---------------------------------------------------------------------------
# bundle
# ---------------------------------------------------------------------------


class TestBundle:
    @given(w1=_word_strategy, w2=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=60)
    def test_commutativity(self, w1, w2, dim):
        """bundle(a, b) == bundle(b, a)."""
        a = encode_atom(w1, dim)
        b = encode_atom(w2, dim)
        ab = bundle(a, b)
        ba = bundle(b, a)
        np.testing.assert_allclose(ab, ba, atol=1e-10)

    @given(
        w1=_word_strategy, w2=_word_strategy, w3=_word_strategy, dim=_dim_strategy
    )
    @settings(max_examples=60)
    def test_associativity(self, w1, w2, w3, dim):
        """bundle(bundle(a,b), c) == bundle(a, bundle(b,c)).

        Additive bundling is strictly associative (mod 2π).
        Verified in Lean 4: bundle_assoc.
        """
        a = encode_atom(w1, dim)
        b = encode_atom(w2, dim)
        c = encode_atom(w3, dim)
        left = bundle(bundle(a, b), c)
        right = bundle(a, bundle(b, c))
        np.testing.assert_allclose(left, right, atol=1e-10)

    @given(w1=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=50)
    def test_single_item_identity(self, w1, dim):
        """bundle of a single vector returns the same vector."""
        a = encode_atom(w1, dim)
        result = bundle(a)
        np.testing.assert_allclose(result, a % (2.0 * math.pi), atol=1e-10)


# ---------------------------------------------------------------------------
# similarity
# ---------------------------------------------------------------------------


class TestSimilarity:
    @given(w1=_word_strategy, w2=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=80)
    def test_range(self, w1, w2, dim):
        """similarity is in [-1, 1]."""
        a = encode_atom(w1, dim)
        b = encode_atom(w2, dim)
        sim = similarity(a, b)
        assert -1.0 <= sim <= 1.0

    @given(w1=_word_strategy, w2=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=80)
    def test_symmetry(self, w1, w2, dim):
        """similarity(a, b) == similarity(b, a)."""
        a = encode_atom(w1, dim)
        b = encode_atom(w2, dim)
        assert math.isclose(similarity(a, b), similarity(b, a), abs_tol=1e-12)

    @given(word=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=80)
    def test_self_similarity(self, word, dim):
        """similarity(a, a) should be approximately 1.0."""
        a = encode_atom(word, dim)
        sim = similarity(a, a)
        assert math.isclose(sim, 1.0, abs_tol=1e-10)


# ---------------------------------------------------------------------------
# phases_to_bytes / bytes_to_phases roundtrip
# ---------------------------------------------------------------------------


class TestSerialization:
    @given(word=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=80)
    def test_roundtrip(self, word, dim):
        """phases_to_bytes -> bytes_to_phases is a perfect roundtrip."""
        original = encode_atom(word, dim)
        restored = bytes_to_phases(phases_to_bytes(original))
        np.testing.assert_array_equal(original, restored)

    @given(word=_word_strategy, dim=_dim_strategy)
    @settings(max_examples=50)
    def test_byte_length(self, word, dim):
        """Serialized bytes should be dim * 8 (float64)."""
        v = encode_atom(word, dim)
        data = phases_to_bytes(v)
        assert len(data) == dim * 8


# ---------------------------------------------------------------------------
# encode_fact with entity unbinding
# ---------------------------------------------------------------------------


class TestEncodeFact:
    @given(dim=_dim_strategy)
    @settings(max_examples=50)
    def test_encode_fact_shape_and_range(self, dim):
        """encode_fact returns a phase vector with correct shape and range."""
        content = "The cat sat on the mat"
        entities = ["Cat"]
        fact_vec = encode_fact(content, entities, dim)

        assert fact_vec.shape == (dim,)
        assert np.all(fact_vec >= 0.0)
        assert np.all(fact_vec < 2 * np.pi)

    @given(dim=st.sampled_from([512, 1024]))
    @settings(max_examples=20)
    def test_encode_fact_deterministic(self, dim):
        """encode_fact is deterministic for same inputs."""
        content = "The cat sat on the mat"
        entities = ["Cat", "Mat"]
        v1 = encode_fact(content, entities, dim)
        v2 = encode_fact(content, entities, dim)

        assert similarity(v1, v2) > 0.99

    @given(dim=st.sampled_from([512, 1024]))
    @settings(max_examples=20)
    def test_encode_fact_different_content(self, dim):
        """Different content should produce different fact vectors."""
        v1 = encode_fact("cats are great", ["Cat"], dim)
        v2 = encode_fact("dogs are terrible", ["Dog"], dim)

        sim = similarity(v1, v2)
        assert abs(sim) < 0.5, f"Different facts too similar: {sim}"


# ---------------------------------------------------------------------------
# encode_binding — exact algebraic extraction
# ---------------------------------------------------------------------------


class TestEncodeBinding:
    @given(
        content=st.text(min_size=1, max_size=50).filter(lambda s: s.strip()),
        entity=_word_strategy,
        dim=_dim_strategy,
    )
    @settings(max_examples=80)
    def test_exact_content_recovery(self, content, entity, dim):
        """unbind(encode_binding(content, entity), entity_atom) == encode_text(content)."""
        binding = encode_binding(content, entity, dim)
        entity_vec = encode_atom(entity.lower(), dim)
        recovered = unbind(binding, entity_vec)
        content_vec = encode_text(content, dim)
        sim = similarity(recovered, content_vec)
        assert sim > 0.99, f"Content recovery failed: sim={sim}"

    @given(
        content=st.text(min_size=1, max_size=50).filter(lambda s: s.strip()),
        entity=_word_strategy,
        dim=_dim_strategy,
    )
    @settings(max_examples=80)
    def test_exact_entity_recovery(self, content, entity, dim):
        """unbind(encode_binding(content, entity), content_text) == entity_atom."""
        binding = encode_binding(content, entity, dim)
        content_vec = encode_text(content, dim)
        recovered = unbind(binding, content_vec)
        entity_vec = encode_atom(entity.lower(), dim)
        sim = similarity(recovered, entity_vec)
        assert sim > 0.99, f"Entity recovery failed: sim={sim}"

    @given(
        content=st.text(min_size=1, max_size=50).filter(lambda s: s.strip()),
        entity=_word_strategy,
        dim=_dim_strategy,
    )
    @settings(max_examples=50)
    def test_shape_and_range(self, content, entity, dim):
        """encode_binding returns a valid phase vector."""
        v = encode_binding(content, entity, dim)
        assert v.shape == (dim,)
        assert np.all(v >= 0.0)
        assert np.all(v < 2.0 * math.pi)

    @given(
        content=st.text(min_size=1, max_size=50).filter(lambda s: s.strip()),
        entity=_word_strategy,
        unrelated=_word_strategy,
        dim=_dim_strategy,
    )
    @settings(max_examples=60)
    def test_wrong_key_gives_noise(self, content, entity, unrelated, dim):
        """Unbinding with a wrong key gives near-zero similarity to content."""
        assume(entity.lower() != unrelated.lower())
        binding = encode_binding(content, entity, dim)
        wrong_key = encode_atom(unrelated.lower(), dim)
        recovered = unbind(binding, wrong_key)
        content_vec = encode_text(content, dim)
        sim = similarity(recovered, content_vec)
        # At dim>=64, random similarity should be well below 0.3
        assert abs(sim) < 0.5, f"Wrong key gave too-high similarity: {sim}"

    @given(
        content=st.text(min_size=1, max_size=50).filter(lambda s: s.strip()),
        entity=_word_strategy,
        dim=_dim_strategy,
    )
    @settings(max_examples=50)
    def test_deterministic(self, content, entity, dim):
        """encode_binding is deterministic."""
        v1 = encode_binding(content, entity, dim)
        v2 = encode_binding(content, entity, dim)
        np.testing.assert_array_equal(v1, v2)


# ---------------------------------------------------------------------------
# snr_estimate
# ---------------------------------------------------------------------------


class TestSnrEstimate:
    @given(
        dim_small=st.integers(min_value=64, max_value=512),
        n_items=st.integers(min_value=1, max_value=50),
    )
    @settings(max_examples=80)
    def test_monotonicity_dim(self, dim_small, n_items):
        """Larger dim with same n_items gives higher or equal SNR."""
        dim_large = dim_small * 2
        snr_small = snr_estimate(dim_small, n_items)
        snr_large = snr_estimate(dim_large, n_items)
        assert snr_large >= snr_small

    @given(dim=st.integers(min_value=64, max_value=1024))
    @settings(max_examples=50)
    def test_zero_items_inf(self, dim):
        """SNR is inf when n_items <= 0."""
        assert snr_estimate(dim, 0) == float("inf")
        assert snr_estimate(dim, -1) == float("inf")

    @given(
        dim=st.integers(min_value=64, max_value=1024),
        n_items=st.integers(min_value=1, max_value=100),
    )
    @settings(max_examples=60)
    def test_positive(self, dim, n_items):
        """SNR is always positive for positive n_items."""
        assert snr_estimate(dim, n_items) > 0.0
