#pragma once
#include "eclass.h"
#include "ring_int.h"

// EGraph<N, Payload> — the equality-saturation graph backing the jitter buffer.
//
// The graph has exactly N nodes, one per ring slot in Z/N·Z.  Each node is an
// EClass that represents the equivalence class of all sequence numbers whose
// quotient under q(n) = n mod N equals that slot.
//
// Canonical structure:
//   nodes[i].slot == RingInt<N>(i)  for all i in [0, N)
//
// The head pointer advances in Z/N·Z to implement FIFO ordering.
// Sequence numbers are expected to arrive in approximately increasing order;
// the ring index places each packet into its canonical slot regardless of
// arrival order.
//
// Integer-only invariant:
//   All arithmetic (slot lookup, head/tail advancement, distance computation)
//   uses RingInt<N> — no floating-point values appear anywhere in this type.
template <int N, typename Payload>
struct EGraph {
	static_assert(N > 0, "graph must have at least one node");

	EClass<N, Payload> nodes[N];
	RingInt<N> head{ 0 }; // next dequeue position in Z/N·Z
	int count = 0; // number of occupied e-classes

	EGraph() {
		for (int i = 0; i < N; i++) {
			nodes[i].slot = RingInt<N>(i);
		}
	}

	// --- Query ---

	int size() const { return count; }
	bool empty() const { return count == 0; }
	bool full() const { return count == N; }

	// Return the e-class for a given sequence number (read-only).
	const EClass<N, Payload> &at(int seq) const {
		return nodes[EClass<N, Payload>::seq_to_slot(seq).v];
	}

	// --- Mutators ---

	// Insert a packet at the e-class determined by seq_num.
	// Returns false if that slot is already occupied.
	// The slot is seq_num mod N (the quotient map).
	bool insert(int seq_num, const Payload &p) {
		RingInt<N> slot = EClass<N, Payload>::seq_to_slot(seq_num);
		bool ok = nodes[slot.v].store(seq_num, p);
		if (ok) {
			count++;
		}
		return ok;
	}

	// Dequeue from the head slot.
	// Advances head by 1 in Z/N·Z regardless of whether the slot was occupied,
	// so that gaps (lost packets) do not stall the buffer.
	// Returns true and fills `out` if the head slot was occupied; returns false
	// (and advances head) if it was empty (packet loss / gap).
	bool dequeue(Payload &out) {
		bool had_packet = nodes[head.v].release(out);
		if (had_packet) {
			count--;
		}
		head = head + 1; // advance in Z/N·Z
		return had_packet;
	}

	// Peek at the head slot without advancing.
	bool peek(Payload &out) const {
		if (!nodes[head.v].occupied) {
			return false;
		}
		out = nodes[head.v].payload;
		return true;
	}

	// How many ring steps from the current head to seq_num?
	// Useful for deciding whether a packet is "ahead" or "behind".
	int distance_from_head(int seq_num) const {
		RingInt<N> slot = EClass<N, Payload>::seq_to_slot(seq_num);
		return head.distance_to(slot);
	}
};
