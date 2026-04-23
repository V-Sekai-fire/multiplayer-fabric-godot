#pragma once
#include "egraph.h"

// JitterBuffer<CAPACITY> — a fixed-size audio packet queue.
//
// Built on EGraph<CAPACITY, PackedBytes> where:
//   PackedBytes = a plain byte array (not Godot-dependent; swap in
//   PackedByteArray or a raw buffer at the call site via the Payload param).
//
// Design properties
// -----------------
// Ring integers (Z/CAPACITY·Z):
//   All slot indices live in Z/CAPACITY·Z (see ring_int.h).  There is no
//   floating-point arithmetic anywhere in this file.
//
// E-classes:
//   Each of the CAPACITY slots is an equivalence class of sequence numbers:
//     slot i = { n ∈ Z | n mod CAPACITY == i }
//   Inserting packet with seq n goes to nodes[n mod CAPACITY] (the quotient map).
//
// Amolean (Boolean ring) occupancy:
//   Every slot satisfies  occupied ∈ {0,1}  with  occupied * occupied = occupied
//   (idempotent).  Attempting to insert into an occupied slot returns false
//   without mutating the slot — the Boolean ring's multiplicative identity is
//   preserved.
//
// Gap-tolerance:
//   dequeue() always advances the head pointer in Z/CAPACITY·Z, even when the
//   head slot is empty.  This means packet loss does not stall playback beyond
//   one frame.
//
// Usage (Godot speech module):
//   JitterBuffer<16, PackedByteArray> buf;
//   buf.insert(seq_num, compressed_frame);   // from on_received_audio_packet
//   PackedByteArray frame;
//   if (buf.dequeue(frame)) { /* decode and play */ }
//   // else: gap — play silence or repeat previous frame

template <int CAPACITY, typename Payload = struct PackedBytes>
struct JitterBuffer {
	static_assert(CAPACITY > 0);

	EGraph<CAPACITY, Payload> graph;

	// Insert a compressed audio frame keyed by sequence number.
	// Returns false if the destination slot is already occupied.
	bool insert(int seq_num, const Payload &frame) {
		return graph.insert(seq_num, frame);
	}

	// Dequeue the next frame in order.
	// Returns true and writes to `out` when the head slot is occupied.
	// Returns false (gap / packet loss) and advances the head regardless.
	bool dequeue(Payload &out) {
		return graph.dequeue(out);
	}

	// Is the next expected frame already buffered?
	bool head_ready() const {
		Payload dummy;
		return graph.peek(dummy);
	}

	// Number of occupied slots.
	int size() const { return graph.size(); }
	bool empty() const { return graph.empty(); }
	bool full() const { return graph.full(); }

	// Ring-distance from the current head to an incoming sequence number.
	// < CAPACITY/2: packet is ahead of head (normal); otherwise it is stale.
	int distance_from_head(int seq_num) const {
		return graph.distance_from_head(seq_num);
	}
};

// Convenience alias for the Godot speech module.
// Uses PackedByteArray as the payload type; replace with a raw buffer struct
// if this header is used outside Godot.
#ifdef GODOT_PROJECT
#include "core/variant/array.h"
#include "core/variant/variant.h"
using SpeechJitterBuffer = JitterBuffer<16, PackedByteArray>;
#endif
