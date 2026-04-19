/**************************************************************************/
/*  jellygrid_power_node_sim.hpp                                          */
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
#include <array>
#include <cmath>
#include <cstdint>

namespace JellygridPowerNode {

static constexpr float OVERLOAD_THRESHOLD = 50.0f;
static constexpr float ROLLING_WINDOW = 5.0f;
static constexpr float SHUTDOWN_DURATION = 8.0f;
static constexpr float BASE_KW_PER_ARRIVAL = 0.12f;
static constexpr float SYNC_BONUS_MAX = 0.8f;
static constexpr float DECAY_RATE = 0.04f;
static constexpr int WINDOW_SAMPLES = 512;

struct Sample {
	float t = 0.0f;
	float kw = 0.0f;
};

struct State {
	std::array<Sample, WINDOW_SAMPLES> samples{};
	int sample_head = 0;
	float time = 0.0f;
	float current_kw = 0.0f;
	float total_kwh = 0.0f;
	float shutdown_timer = 0.0f;
	bool overloaded = false;
};

inline float rolling_sum(const State &s) {
	float cutoff = s.time - ROLLING_WINDOW;
	float sum = 0.0f;
	for (auto &sample : s.samples) {
		if (sample.t >= cutoff) {
			sum += sample.kw;
		}
	}
	return sum;
}

// Returns kW generated; 0 if overloaded.
inline float receive_jellyfish(State &s, float sync_phase) {
	if (s.overloaded) {
		return 0.0f;
	}

	float sync = 0.5f + 0.5f * std::sin(sync_phase);
	float kw = BASE_KW_PER_ARRIVAL * (1.0f + sync * SYNC_BONUS_MAX);

	s.current_kw += kw;
	s.total_kwh += kw / 3600.0f;
	s.samples[s.sample_head % WINDOW_SAMPLES] = { s.time, kw };
	++s.sample_head;

	if (rolling_sum(s) >= OVERLOAD_THRESHOLD) {
		s.overloaded = true;
		s.shutdown_timer = SHUTDOWN_DURATION;
		s.current_kw = 0.0f;
	}
	return kw;
}

inline void tick(State &s, float delta) {
	s.time += delta;
	if (s.overloaded) {
		s.shutdown_timer -= delta;
		if (s.shutdown_timer <= 0.0f) {
			s.overloaded = false;
			s.shutdown_timer = 0.0f;
		}
		return;
	}
	s.current_kw -= s.current_kw * DECAY_RATE * delta;
	if (s.current_kw < 0.0f) {
		s.current_kw = 0.0f;
	}
}

inline void reset(State &s) {
	s = {};
}

} // namespace JellygridPowerNode
