import HRR.Basic

/-!
# HRR Phase Vector Algebra — Formal Proofs

Proves the algebraic properties that make holographic memory work:
1. bind/unbind are exact inverses
2. bind is commutative and associative
3. fact encoding supports exact content/entity recovery

All proofs use `omega` (linear integer arithmetic) after
`simp`-unfolding the definitions. Since (ℤ, +) is an abelian
group and ℤ/nℤ is its quotient, these properties hold for any
modular phase arithmetic.
-/

namespace PhaseVec

variable {d : Nat}

-- ═══════════════════════════════════════════════════════════════════
-- 1. Bind / Unbind Inverse Properties
-- ═══════════════════════════════════════════════════════════════════

/-- Core property: unbind(bind(a, b), a) = b.
    Unbinding with the first argument recovers the second. -/
theorem bind_unbind_left (a b : PhaseVec d) :
    unbind (bind a b) a = b := by
  funext i; simp [bind, unbind]; omega

/-- Symmetric: unbind(bind(a, b), b) = a.
    Unbinding with the second argument recovers the first. -/
theorem bind_unbind_right (a b : PhaseVec d) :
    unbind (bind a b) b = a := by
  funext i; simp [bind, unbind]

/-- Double unbind: unbind(unbind(m, a), b) = unbind(m, bind(a, b)). -/
theorem unbind_unbind (m a b : PhaseVec d) :
    unbind (unbind m a) b = unbind m (bind a b) := by
  funext i; simp [bind, unbind]; omega

-- ═══════════════════════════════════════════════════════════════════
-- 2. Bind is a Commutative Group Operation
-- ═══════════════════════════════════════════════════════════════════

/-- Bind is commutative: bind(a, b) = bind(b, a). -/
theorem bind_comm (a b : PhaseVec d) :
    bind a b = bind b a := by
  funext i; simp [bind]; omega

/-- Bind is associative: bind(bind(a, b), c) = bind(a, bind(b, c)). -/
theorem bind_assoc (a b c : PhaseVec d) :
    bind (bind a b) c = bind a (bind b c) := by
  funext i; simp [bind]; omega

/-- Zero vector is the right identity for bind. -/
theorem bind_zero_right (a : PhaseVec d) :
    bind a zero = a := by
  funext i; simp [bind, zero]

/-- Zero vector is the left identity for bind. -/
theorem bind_zero_left (a : PhaseVec d) :
    bind zero a = a := by
  funext i; simp [bind, zero]

/-- Binding with the negation gives zero (inverse element). -/
theorem bind_neg_self (a : PhaseVec d) :
    bind a (neg a) = zero := by
  funext i; simp [bind, neg, zero]; omega

/-- Unbinding from itself gives zero. -/
theorem unbind_self (a : PhaseVec d) :
    unbind a a = zero := by
  funext i; simp [unbind, zero]

-- ═══════════════════════════════════════════════════════════════════
-- 3. Self-Similarity
-- ═══════════════════════════════════════════════════════════════════

/-- Two phase vectors are equal iff their pointwise diff is everywhere zero —
    the formal analogue of "cosine similarity = 1 iff a = b". -/
theorem diff_eq_iff_zero (a b : PhaseVec d) :
    (∀ i, diff a b i = 0) ↔ a = b := by
  constructor
  · intro h; funext i; have := h i; simp [diff, zero] at this; omega
  · intro h; subst h; intro i; simp [diff, zero]

/-- The difference of a vector with itself is zero at every component.
    In the real implementation: cos(a_i - a_i) = cos(0) = 1,
    so mean(cos(a - a)) = 1.0. -/
theorem self_diff_zero (a : PhaseVec d) (i : Fin d) :
    a i - a i = 0 := by omega

-- ═══════════════════════════════════════════════════════════════════
-- 4. Fact Encoding / Recovery — THE KEY PROPERTY
-- ═══════════════════════════════════════════════════════════════════

/-- **Fact recovery (content):**
    Given fact = encodeFact content entity = bind(content, entity),
    unbind(fact, entity) recovers content exactly.

    This is THE property that makes holographic memory work:
    storing bind(content, entity) and probing with entity
    yields the original content with zero noise. -/
theorem fact_recovery_content (content entity : PhaseVec d) :
    unbind (encodeFact content entity) entity = content :=
  bind_unbind_right content entity

/-- **Fact recovery (entity):**
    Given fact = encodeFact content entity,
    unbind(fact, content) recovers entity exactly. -/
theorem fact_recovery_entity (content entity : PhaseVec d) :
    unbind (encodeFact content entity) content = entity :=
  bind_unbind_left content entity

/-- **Wrong key residual:**
    unbind(bind(v, k₁), k₂) = bind(v, k₁ - k₂).
    When k₁ ≠ k₂, the result is v "rotated" by the key difference —
    quasi-random when keys are random, giving near-zero similarity. -/
theorem wrong_key_residual (v key₁ key₂ : PhaseVec d) :
    unbind (bind v key₁) key₂ = bind v (fun i => key₁ i - key₂ i) := by
  funext i; simp [bind, unbind]; omega

-- ═══════════════════════════════════════════════════════════════════
-- 5. Composition Properties
-- ═══════════════════════════════════════════════════════════════════

/-- Nested fact encoding is associative. -/
theorem encodeFact_assoc (a b c : PhaseVec d) :
    encodeFact (encodeFact a b) c = encodeFact a (bind b c) :=
  bind_assoc a b c

/-- Fact encoding is commutative. -/
theorem encodeFact_comm (content entity : PhaseVec d) :
    encodeFact content entity = encodeFact entity content :=
  bind_comm content entity

-- ═══════════════════════════════════════════════════════════════════
-- 6. Similarity via Difference Vectors
-- ═══════════════════════════════════════════════════════════════════

/-- `diff` is the same as `unbind` (both are pointwise subtraction).
    This lets us reuse unbind theorems for similarity reasoning. -/
theorem diff_eq_unbind (a b : PhaseVec d) : diff a b = unbind a b := by
  funext i; simp [diff, unbind]

/-- Self-difference is zero: `diff(a, a) = zero`.
    In the real implementation: cos(0) = 1 at every component,
    so `similarity(a, a) = mean(cos(diff a a)) = mean(1) = 1.0`. -/
theorem diff_self (a : PhaseVec d) : diff a a = zero := by
  funext i; simp [diff, zero]

/-- Recovery implies zero difference — the key similarity guarantee.
    After `unbind(encodeFact(c, e), e)` recovers `c`, the difference
    between recovered and original is zero at every component.
    This means `similarity(recovered, c) = 1.0` in the real system. -/
theorem recovery_diff_zero (content entity : PhaseVec d) :
    diff (unbind (encodeFact content entity) entity) content = zero := by
  rw [fact_recovery_content]; exact diff_self content

/-- Wrong-key recovery has non-trivial difference.
    When unbinding with key₂ ≠ key₁, the difference from the original
    content is `unbind(key₁, key₂)` — a quasi-random vector for random keys,
    giving `similarity ≈ 0` by concentration of measure. -/
theorem wrong_key_diff (content key₁ key₂ : PhaseVec d) :
    diff (unbind (bind content key₁) key₂) content = unbind key₁ key₂ := by
  funext i; simp [diff, bind, unbind]; omega

-- ═══════════════════════════════════════════════════════════════════
-- 7. Bundle is a Commutative Group (= bind algebraically)
-- ═══════════════════════════════════════════════════════════════════

/-- Bundle and bind are the same operation (pointwise addition).
    The distinction is semantic: bind associates concepts,
    bundle superimposes them. -/
theorem bundle_eq_bind (a b : PhaseVec d) : bundle a b = bind a b := by
  funext i; simp [bundle, bind]

/-- Bundle is commutative. -/
theorem bundle_comm (a b : PhaseVec d) : bundle a b = bundle b a := by
  funext i; simp [bundle]; omega

/-- Bundle is associative. -/
theorem bundle_assoc (a b c : PhaseVec d) :
    bundle (bundle a b) c = bundle a (bundle b c) := by
  funext i; simp [bundle]; omega

/-- Zero is a right identity for bundle. -/
theorem bundle_zero_right (a : PhaseVec d) : bundle a zero = a := by
  funext i; simp [bundle, zero]

/-- Zero is a left identity for bundle. -/
theorem bundle_zero_left (a : PhaseVec d) : bundle zero a = a := by
  funext i; simp [bundle, zero]

-- ═══════════════════════════════════════════════════════════════════
-- 8. Chained Binding
-- ═══════════════════════════════════════════════════════════════════

/-- **Chained binding is reversible.**
    `bind(bind(a, b), c)` can be fully unwound:
      - `unbind(_, c)` recovers `bind(a, b)`
      - `unbind(_, b)` then recovers `a` -/
theorem chained_unbind (a b c : PhaseVec d) :
    unbind (unbind (bind (bind a b) c) c) b = a := by
  funext i; simp [bind, unbind]

-- ═══════════════════════════════════════════════════════════════════
-- 7. Additive Bundle (Superposition) Properties
-- ═══════════════════════════════════════════════════════════════════

/-- **Additive bundle extraction.**
    If `bank = add(bind(c1, e1), bind(c2, e2))`, then:
      `unbind(bank, e1) = add(c1, bind(c2, unbind(e2, e1)))`
    The first term `c1` is the signal; the second is noise.
    For random independent vectors, the noise term is quasi-orthogonal to `c1`,
    so `similarity(result, c1) ≈ 1/√n_components` by concentration of measure. -/
theorem additive_bundle_unbind (c1 c2 e1 e2 : PhaseVec d) :
    unbind (bundle (bind c1 e1) (bind c2 e2)) e1
    = bundle c1 (bind c2 e2) := by
  funext i; simp [bundle, bind, unbind]; omega

/-- Three-item bundle extraction.
    Unbinding e1 from a 3-item bundle recovers c1 plus two noise terms.
    Used by Python's `_rebuild_bank` + `probe` for category memory banks. -/
theorem bundle_three_unbind (c1 c2 c3 e1 e2 e3 : PhaseVec d) :
    unbind (bundle (bundle (bind c1 e1) (bind c2 e2)) (bind c3 e3)) e1
    = bundle (bundle c1 (bind c2 e2)) (bind c3 e3) := by
  funext i; simp [bundle, bind, unbind]; omega

-- ═══════════════════════════════════════════════════════════════════
-- 10. Multi-Entity Composition (Python `reason` method)
-- ═══════════════════════════════════════════════════════════════════

/-- **Multi-entity binding is separable.**
    Each entity's binding can be independently verified:
    `unbind(bind(content, e_i), e_i) = content` regardless of other entities.
    This is why Python's `reason` can check each entity independently
    and AND-combine the scores (min across entities). -/
theorem multi_entity_independent (content e1 e2 : PhaseVec d) :
    unbind (bind content e1) e1 = content ∧
    unbind (bind content e2) e2 = content :=
  ⟨bind_unbind_right content e1, bind_unbind_right content e2⟩

/-- **Chained multi-entity binding.**
    Binding content with two entities sequentially:
    `bind(bind(content, e1), e2)` can recover content by unbinding both.
    This supports nested role-filler bindings. -/
theorem multi_bind_recovery (content e1 e2 : PhaseVec d) :
    unbind (unbind (bind (bind content e1) e2) e2) e1 = content := by
  funext i; simp [bind, unbind]

end PhaseVec
