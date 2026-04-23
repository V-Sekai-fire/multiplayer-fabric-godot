#pragma once
#include "ring_int.h"

// EClass<N> — an equivalence class of sequence numbers that share a ring slot.
//
// The quotient map  q : Z → Z/N·Z,  q(n) = n mod N  partitions the integers
// into N equivalence classes.  EClass<N> represents one such class: the set
//   { n ∈ Z  |  n mod N == slot.v }
//
// Amolean occupancy invariant:
//   occupied ∈ { 0, 1 }  with  occupied * occupied == occupied
//
// This is the idempotent axiom of a Boolean ring (x² = x).  It means a slot
// is either fully occupied or fully empty — there is no partial state.  The
// Boolean ring {0,1} under (XOR, AND) is the algebraic structure that makes
// this precise: "setting a slot that is already set" is a no-op (1 XOR 1 = 0
// in the additive sense, but 1 AND 1 = 1 in the multiplicative/idempotent
// sense used here for the occupancy predicate).
template <int N, typename Payload>
struct EClass {
	RingInt<N> slot; // the ring index that names this equivalence class
	int seq_num = -1; // representative integer from Z that is currently stored
	Payload payload{}; // the data attached to this class
	bool occupied = false; // amolean bit: 0 (empty) or 1 (full), x*x = x

	// Map an arbitrary sequence number to the slot of its equivalence class.
	// This is the quotient map q applied to seq.
	static RingInt<N> seq_to_slot(int seq) { return RingInt<N>(seq); }

	// Check whether a sequence number belongs to this equivalence class.
	bool owns(int seq) const { return seq_to_slot(seq) == slot; }

	// Occupy: transition occupied from 0 to 1 (Boolean ring: was 0, becomes 1).
	// Fails (returns false) if already occupied — idempotent guard.
	bool store(int seq, const Payload &p) {
		if (occupied) {
			return false; // already 1; 1*1=1, no change allowed
		}
		seq_num = seq;
		payload = p;
		occupied = true;
		return true;
	}

	// Release: transition occupied from 1 to 0.
	// Returns false if already empty.
	bool release(Payload &out) {
		if (!occupied) {
			return false;
		}
		out = payload;
		payload = Payload{};
		seq_num = -1;
		occupied = false;
		return true;
	}
};
