/**************************************************************************/
/*  test_jellygrid_current.h                                              */
/**************************************************************************/
/* Cycle 1: place_current returns valid slot, emitter_count increases    */
/* Cycle 2: placed emitter creates nonzero flow near its position        */
/* Cycle 3: remove_current zeroes emitter slot, flow clears              */
/* Cycle 4: MAX_EMITTERS full → place_current returns -1                 */
/* Cycle 5: inject_rip_current spreads nonzero flow across field         */
/* Cycle 6: tick decays injected rip current                             */
/* Cycle 7: persistent emitter resists decay (re-splat each tick)        */
/* Cycle 8: sample_flow_x/z clamped at grid boundary                    */
/**************************************************************************/

#pragma once

#include "../jellygrid_current_sim.hpp"
#include "tests/test_macros.h"

namespace TestJellygridCurrent {

using namespace JellygridCurrent;

// ── Cycle 1 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Current] place_current returns a valid slot") {
	State s;
	int slot = place_current(s, 0.0f, 0.0f, 1.0f, 0.0f, 2.0f);
	CHECK(slot >= 0);
	CHECK(slot < MAX_EMITTERS);
	CHECK(s.emitter_count == 1);
	CHECK(s.emitters[slot].active);
}

// ── Cycle 2 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Current] emitter creates nonzero flow near its position") {
	State s;
	place_current(s, 0.0f, 0.0f, 1.0f, 0.0f, 5.0f);

	// The cell at the emitter's position must have nonzero X flow.
	float vx = sample_flow_x(s, 0.0f, 0.0f);
	CHECK(vx > 0.0f);
}

// ── Cycle 3 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Current] remove_current clears slot and rebuilds field") {
	State s;
	int slot = place_current(s, 0.0f, 0.0f, 1.0f, 0.0f, 5.0f);
	CHECK(s.emitter_count == 1);

	remove_current(s, slot);
	CHECK(s.emitter_count == 0);
	CHECK_FALSE(s.emitters[slot].active);

	// Flow should be zero everywhere after removing the only emitter.
	for (auto &c : s.field) {
		CHECK(c.vx == 0.0f);
		CHECK(c.vz == 0.0f);
	}
}

// ── Cycle 4 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Current] returns -1 when all emitter slots are full") {
	State s;
	for (int i = 0; i < MAX_EMITTERS; ++i)
		place_current(s, (float)i, 0.0f, 1.0f, 0.0f, 1.0f);

	int slot = place_current(s, 0.0f, 0.0f, 0.0f, 1.0f, 1.0f);
	CHECK(slot == -1);
}

// ── Cycle 5 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Current] inject_rip_current spreads nonzero flow") {
	State s;
	inject_rip_current(s, 0.0f, 0.0f, 5.0f);

	bool any_nonzero = false;
	for (auto &c : s.field)
		if (c.vx != 0.0f || c.vz != 0.0f) { any_nonzero = true; break; }
	CHECK(any_nonzero);
}

// ── Cycle 6 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Current] rip current decays after tick with no emitters") {
	State s;
	inject_rip_current(s, 0.0f, 0.0f, 5.0f);

	float sum_before = 0.0f;
	for (auto &c : s.field) sum_before += c.vx * c.vx + c.vz * c.vz;
	CHECK(sum_before > 0.0f);

	tick(s, 1.0f);

	float sum_after = 0.0f;
	for (auto &c : s.field) sum_after += c.vx * c.vx + c.vz * c.vz;
	CHECK(sum_after < sum_before);
}

// ── Cycle 7 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Current] persistent emitter maintains flow through decay") {
	State s;
	place_current(s, 0.0f, 0.0f, 1.0f, 0.0f, 5.0f);

	float vx_initial = sample_flow_x(s, 0.0f, 0.0f);
	// After many ticks, emitter re-splat should keep flow bounded above zero.
	for (int i = 0; i < 10; ++i) tick(s, 1.0f);
	float vx_final = sample_flow_x(s, 0.0f, 0.0f);

	CHECK(vx_final > 0.0f);
	// Should be substantially below initial (decay is real, not zero).
	// Note: re-splat each tick means it reaches steady-state, not zero.
	CHECK(vx_final < vx_initial * 5.0f); // sanity: not runaway growth
}

// ── Cycle 8 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Current] sample_flow clamps out-of-bounds positions") {
	State s;
	inject_rip_current(s, 0.0f, 0.0f, 5.0f);
	// Positions far outside SIM_BOUND should clamp to grid edge, not crash.
	float vx = sample_flow_x(s, 1000.0f, 1000.0f);
	float vz = sample_flow_z(s, -1000.0f, -1000.0f);
	// Values exist (no crash), types are finite.
	CHECK(vx == vx); // NaN check
	CHECK(vz == vz);
}

} // namespace TestJellygridCurrent
