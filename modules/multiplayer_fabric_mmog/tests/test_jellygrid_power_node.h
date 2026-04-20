/**************************************************************************/
/*  test_jellygrid_power_node.h                                           */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "../jellygrid_power_node_sim.hpp"

#include "tests/test_macros.h"

namespace TestJellygridPowerNode {

using namespace JellygridPowerNode;

// ── Cycle 1 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][PowerNode] receive_jellyfish returns positive kw") {
	State s;
	float kw = receive_jellyfish(s, 0.0f);
	CHECK(kw > 0.0f);
	CHECK(s.total_kwh > 0.0f);
	CHECK(s.current_kw > 0.0f);
}

// ── Cycle 2 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][PowerNode] in-phase arrival yields more kw than out-of-phase") {
	State s_sync, s_base;

	// sync_phase = π/2 → sin=1 → sync=1.0 → bonus factor = 1 + SYNC_BONUS_MAX
	float kw_sync = receive_jellyfish(s_sync, 3.14159f / 2.0f);
	// sync_phase = π   → sin=0 → sync=0.5 → bonus factor = 1 + 0.5*SYNC_BONUS_MAX
	float kw_base = receive_jellyfish(s_base, 3.14159f);

	CHECK(kw_sync > kw_base);
}

// ── Cycle 3 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][PowerNode] overload triggers when rolling window exceeds threshold") {
	State s;
	// Each arrival at sync_phase=π/2 gives BASE_KW*(1+SYNC_BONUS_MAX) ≈ 0.216 kW.
	// OVERLOAD_THRESHOLD=50 kW → need ~232 arrivals within ROLLING_WINDOW seconds.
	// Drive it well past threshold with rapid arrivals at t=0.
	bool triggered = false;
	for (int i = 0; i < 300; ++i) {
		receive_jellyfish(s, 1.5708f);
		if (s.overloaded) {
			triggered = true;
			break;
		}
	}
	CHECK(triggered);
	CHECK(s.current_kw == 0.0f);
}

// ── Cycle 4 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][PowerNode] overloaded node rejects arrivals") {
	State s;
	s.overloaded = true;
	float kw = receive_jellyfish(s, 0.0f);
	CHECK(kw == 0.0f);
	CHECK(s.current_kw == 0.0f);
	CHECK(s.total_kwh == 0.0f);
}

// ── Cycle 5 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][PowerNode] node comes back online after shutdown expires") {
	State s;
	s.overloaded = true;
	s.shutdown_timer = SHUTDOWN_DURATION;

	tick(s, SHUTDOWN_DURATION - 0.01f);
	CHECK(s.overloaded);

	tick(s, 0.02f);
	CHECK_FALSE(s.overloaded);
	CHECK(s.shutdown_timer == 0.0f);
}

// ── Cycle 6 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][PowerNode] tick decays current_kw when online") {
	State s;
	receive_jellyfish(s, 0.0f);
	float kw_before = s.current_kw;
	tick(s, 1.0f);
	CHECK(s.current_kw < kw_before);
	CHECK(s.current_kw >= 0.0f);
}

// ── Cycle 7 ──────────────────────────────────────────────────────────────────

TEST_CASE("[Jellygrid][PowerNode] reset clears all state") {
	State s;
	receive_jellyfish(s, 0.0f);
	s.overloaded = true;
	reset(s);
	CHECK(s.current_kw == 0.0f);
	CHECK(s.total_kwh == 0.0f);
	CHECK_FALSE(s.overloaded);
	CHECK(s.time == 0.0f);
}

} // namespace TestJellygridPowerNode
