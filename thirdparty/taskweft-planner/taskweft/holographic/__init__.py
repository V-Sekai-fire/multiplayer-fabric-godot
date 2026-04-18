"""holographic — Holographic Reduced Representation memory with structured fact storage.

Provides SQLite-backed fact storage with entity resolution, trust scoring,
and HRR-based compositional retrieval (bind/unbind/bundle/similarity).

Core modules:
  holographic.py  — HRR algebra (encode_atom, bind, unbind, bundle, similarity, etc.)
  store.py        — MemoryStore: SQLite fact storage with entity resolution and trust
  retrieval.py    — FactRetriever: hybrid search (FTS5 + Jaccard + HRR similarity)

Original plugin by dusterbloom (PR #2351), extracted as a standalone library.
"""

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
)
from .store import MemoryStore
from .retrieval import FactRetriever

__all__ = [
    "bind",
    "bundle",
    "bytes_to_phases",
    "encode_atom",
    "encode_binding",
    "encode_fact",
    "encode_text",
    "phases_to_bytes",
    "similarity",
    "snr_estimate",
    "unbind",
    "MemoryStore",
    "FactRetriever",
]
