/**************************************************************************/
/*  test_jellygrid_swarm.h                                                */
/**************************************************************************/
/* Cycle 1: spawn → alive_count increments                                */
/* Cycle 2: bloom_ttl expiry removes entity after 30 ticks of delta=1    */
/* Cycle 3: jellyfish_reached_node → kw > 0, entity removed              */
/* Cycle 4: predator flee pushes entity away                              */
/* Cycle 5: rip current injects nonzero flow at grid cells near origin   */
/**************************************************************************/

#pragma once

#include "../jellygrid_swarm_sim.hpp"
#include "tests/test_macros.h"

namespace TestJellygridSwarm {

using namespace JellygridSwarm;

// ── Cycle 1 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Swarm] spawn increments alive_count") {
	State s;
	CHECK(s.alive_count == 0);
	spawn(s, 0);
	CHECK(s.alive_count == 1);
	spawn(s, 1);
	CHECK(s.alive_count == 2);
}

TEST_CASE("[Jellygrid][Swarm] spawn out-of-range id is a no-op") {
	State s;
	spawn(s, -1);
	spawn(s, MAX_JELLYFISH);
	CHECK(s.alive_count == 0);
}

// ── Cycle 2 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Swarm] entity expires after BLOOM_TTL seconds") {
	State s;
	spawn(s, 0);
	REQUIRE(s.fish[0].alive);

	// Tick just under TTL — still alive.
	tick(s, BLOOM_TTL - 0.01f);
	CHECK(s.fish[0].alive);

	// One more tick pushes ttl past zero — expired.
	tick(s, 0.02f);
	CHECK_FALSE(s.fish[0].alive);
	CHECK(s.alive_count == 0);
}

// ── Cycle 3 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Swarm] jellyfish_reached_node returns positive kw") {
	State s;
	spawn(s, 42);
	float kw = jellyfish_reached_node(s, 42);
	CHECK(kw > 0.0f);
	CHECK_FALSE(s.fish[42].alive);
	CHECK(s.alive_count == 0);
}

TEST_CASE("[Jellygrid][Swarm] jellyfish_reached_node on dead entity returns 0") {
	State s;
	float kw = jellyfish_reached_node(s, 0);
	CHECK(kw == 0.0f);
}

TEST_CASE("[Jellygrid][Swarm] kw is bounded by sync bonus range [0.1, 0.2]") {
	State s;
	// Phase=0 → sin(0)=0 → sync=0.5 → kw = 0.1*(1+0.5) = 0.15
	spawn(s, 0);
	s.fish[0].phase = 0.0f;
	float kw = jellyfish_reached_node(s, 0);
	CHECK(kw >= 0.1f);
	CHECK(kw <= 0.2f);
}

// ── Cycle 4 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Swarm] predator flee pushes entity outward") {
	State s;
	spawn(s, 0);
	// Place entity at (1, 0, 0) — just inside flee radius of predator at origin.
	s.fish[0].x = 1.0f;
	s.fish[0].z = 0.0f;
	add_predator(s, 0.0f, 0.0f, 0.0f);

	float x_before = s.fish[0].x;
	tick(s, 0.1f);
	// Entity should have moved further from predator (positive x direction).
	CHECK(s.fish[0].x > x_before);
}

// ── Cycle 5 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][Swarm] inject_rip_current sets nonzero flow near origin") {
	State s;
	// All cells start at zero.
	for (auto &cell : s.flow) { CHECK(cell.x == 0.0f); CHECK(cell.z == 0.0f); }

	inject_rip_current(s, 0.0f, 0.0f);

	bool any_nonzero = false;
	for (auto &cell : s.flow)
		if (cell.x != 0.0f || cell.z != 0.0f) { any_nonzero = true; break; }
	CHECK(any_nonzero);
}

TEST_CASE("[Jellygrid][Swarm] flow field decays toward zero after tick with no emitters") {
	State s;
	inject_rip_current(s, 0.0f, 0.0f);

	// Record max magnitude before decay.
	float max_before = 0.0f;
	for (auto &c : s.flow) {
		float mag = c.x * c.x + c.z * c.z;
		if (mag > max_before) max_before = mag;
	}
	CHECK(max_before > 0.0f);

	tick(s, 1.0f);

	float max_after = 0.0f;
	for (auto &c : s.flow) {
		float mag = c.x * c.x + c.z * c.z;
		if (mag > max_after) max_after = mag;
	}
	CHECK(max_after < max_before);
}

} // namespace TestJellygridSwarm
