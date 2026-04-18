/-!
# HRR Phase Vector Algebra — Core Definitions

Holographic Reduced Representations using phase encoding.
We model phase arithmetic using integers (ℤ), which form an
additive commutative group. The real implementation uses
ℝ/2πℤ (reals mod 2π), but the algebraic properties we verify
depend only on the group axioms of (ℤ, +, 0, -).

Since ℤ/nℤ is a quotient of ℤ and addition/subtraction commute
with the quotient map, all properties proved here transfer to
any modular arithmetic — including `float64 mod 2π`.
-/

/-- Phase vectors of dimension `d` over ℤ.
    Each component is an integer, modeling a discretized phase angle.
    The group axioms of (ℤ, +) guarantee exact bind/unbind. -/
def PhaseVec (d : Nat) := Fin d → Int

namespace PhaseVec

variable {d : Nat}

/-- Bind: element-wise addition (circular convolution in phase space). -/
def bind (a b : PhaseVec d) : PhaseVec d :=
  fun i => a i + b i

/-- Unbind: element-wise subtraction (circular correlation in phase space). -/
def unbind (memory key : PhaseVec d) : PhaseVec d :=
  fun i => memory i - key i

/-- Two phase vectors are pointwise equal. -/
def pointwiseEq (a b : PhaseVec d) : Prop :=
  ∀ i : Fin d, a i = b i

/-- Extensionality for phase vectors. -/
theorem ext_iff (a b : PhaseVec d) : a = b ↔ pointwiseEq a b := by
  constructor
  · intro h i; rw [h]
  · intro h; funext i; exact h i

/-- Encode a fact as bind(content, entity).
    Models Python's `encode_binding(content, entity, dim)`.
    Note: Python's `encode_fact` uses a richer role-vector structure —
    a 3-component bundle with fixed role atoms (`__hrr_role_content__`,
    `__hrr_role_entity__`).  That structure is not yet formalized here;
    the algebraic properties in Properties.lean apply to this simpler form
    and transfer to `encode_binding` in the Python store. -/
def encodeFact (content entity : PhaseVec d) : PhaseVec d :=
  bind content entity

/-- The zero vector (identity element). -/
def zero : PhaseVec d := fun _ => 0

/-- Negation (element-wise). -/
def neg (a : PhaseVec d) : PhaseVec d := fun i => -(a i)

/-- Pointwise addition of phase vectors (used for additive superposition).
    Unlike circular-mean bundling, additive superposition preserves unbindability
    (with noise proportional to 1/√dim for random components). -/
def bundle (a b : PhaseVec d) : PhaseVec d := fun i => a i + b i

/-- The difference vector between two phase vectors.
    In the real implementation, `similarity(a, b) = mean(cos(diff a b))`.
    When `diff a b = zero`, every component is 0 and cos(0) = 1,
    so similarity = 1.0 (perfect match). -/
def diff (a b : PhaseVec d) : PhaseVec d := fun i => a i - b i

end PhaseVec
