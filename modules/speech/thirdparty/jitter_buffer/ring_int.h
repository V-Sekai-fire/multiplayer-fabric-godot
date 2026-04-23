#pragma once
#include <cassert>

// RingInt<N> — a single integer in Z/N·Z.
//
// All arithmetic is modular: addition, subtraction, and comparison are
// performed in Z/N·Z. There is no floating-point arithmetic anywhere in
// this type.
//
// Algebraic properties that hold for every element r : RingInt<N>:
//   (r + N).v == r.v                 (additive periodicity)
//   (r - r).v == 0                   (additive inverse)
//   RingInt<N>(r.v + k*N).v == r.v   (quotient map)
//
// These are the defining axioms of Z/N·Z viewed as a commutative ring
// (with unity 1 and zero 0) under the operations defined below.
template <int N>
struct RingInt {
	static_assert(N > 0, "ring size must be positive");

	int v; // representative in [0, N)

	// Canonical constructor: reduce any integer into [0, N).
	// This is the quotient map Z → Z/N·Z.
	explicit RingInt(int i) :
			v(((i % N) + N) % N) {}

	// Ring addition: (a + b) mod N
	RingInt operator+(int d) const { return RingInt(v + d); }
	RingInt operator+(RingInt<N> o) const { return RingInt(v + o.v); }

	// Ring subtraction: (a - b + N) mod N
	RingInt operator-(int d) const { return RingInt(v - d); }
	RingInt operator-(RingInt<N> o) const { return RingInt(v - o.v); }

	// Ring equality: equal iff same representative
	bool operator==(RingInt<N> o) const { return v == o.v; }
	bool operator!=(RingInt<N> o) const { return v != o.v; }

	// Signed distance from this to other in [0, N): how many steps forward
	// in the ring to reach `other` from `this`.
	int distance_to(RingInt<N> other) const {
		return (other.v - v + N) % N;
	}
};
