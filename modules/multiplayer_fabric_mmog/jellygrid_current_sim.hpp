/**************************************************************************/
/*  jellygrid_current_sim.hpp                                             */
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

namespace JellygridCurrent {

static constexpr int GRID = 16;
static constexpr float SIM_BOUND = 15.0f;
static constexpr float CELL = SIM_BOUND * 2.0f / GRID;
static constexpr float DECAY = 0.08f;
static constexpr float EMITTER_SIGMA = 3.5f;
static constexpr int MAX_EMITTERS = 32;

struct FlowCell {
	float vx = 0.0f, vz = 0.0f;
};

struct Emitter {
	bool active = false;
	float x = 0.0f, z = 0.0f;
	float dir_x = 0.0f, dir_z = 0.0f;
	float strength = 0.0f;
};

struct State {
	std::array<FlowCell, GRID * GRID> field{};
	std::array<Emitter, MAX_EMITTERS> emitters{};
	int emitter_count = 0;
};

inline int cell_idx(float x, float z) {
	int gx = (int)((x + SIM_BOUND) / CELL);
	int gz = (int)((z + SIM_BOUND) / CELL);
	gx = gx < 0 ? 0 : (gx >= GRID ? GRID - 1 : gx);
	gz = gz < 0 ? 0 : (gz >= GRID ? GRID - 1 : gz);
	return gz * GRID + gx;
}

inline void _splat(State &s, const Emitter &e) {
	for (int gi = 0; gi < GRID; ++gi) {
		for (int gj = 0; gj < GRID; ++gj) {
			float cx = -SIM_BOUND + (gi + 0.5f) * CELL;
			float cz = -SIM_BOUND + (gj + 0.5f) * CELL;
			float dx = cx - e.x, dz = cz - e.z;
			float w = std::exp(-(dx * dx + dz * dz) / (2.0f * EMITTER_SIGMA * EMITTER_SIGMA));
			s.field[gj * GRID + gi].vx += e.dir_x * e.strength * w;
			s.field[gj * GRID + gi].vz += e.dir_z * e.strength * w;
		}
	}
}

inline void rebuild(State &s) {
	for (auto &c : s.field) {
		c = {};
	}
	for (auto &e : s.emitters) {
		if (e.active) {
			_splat(s, e);
		}
	}
}

// Returns slot index, or -1 if full.
inline int place_current(State &s, float x, float z, float dir_x, float dir_z, float strength) {
	float len = std::sqrt(dir_x * dir_x + dir_z * dir_z) + 1e-6f;
	dir_x /= len;
	dir_z /= len;
	for (int i = 0; i < MAX_EMITTERS; ++i) {
		if (!s.emitters[i].active) {
			s.emitters[i] = { true, x, z, dir_x, dir_z, strength };
			++s.emitter_count;
			rebuild(s);
			return i;
		}
	}
	return -1;
}

inline void remove_current(State &s, int slot) {
	if (slot < 0 || slot >= MAX_EMITTERS || !s.emitters[slot].active) {
		return;
	}
	s.emitters[slot].active = false;
	--s.emitter_count;
	rebuild(s);
}

inline void inject_rip_current(State &s, float origin_x, float origin_z, float intensity) {
	for (int gi = 0; gi < GRID; ++gi) {
		for (int gj = 0; gj < GRID; ++gj) {
			float cx = -SIM_BOUND + (gi + 0.5f) * CELL;
			float cz = -SIM_BOUND + (gj + 0.5f) * CELL;
			float dx = cx - origin_x, dz = cz - origin_z;
			float dist = std::sqrt(dx * dx + dz * dz) + 0.001f;
			float mag = intensity / (1.0f + dist * 0.4f);
			s.field[gj * GRID + gi].vx += (dx / dist) * mag;
			s.field[gj * GRID + gi].vz += (dz / dist) * mag;
		}
	}
}

inline void tick(State &s, float delta) {
	float keep = 1.0f - DECAY * delta;
	for (auto &c : s.field) {
		c.vx *= keep;
		c.vz *= keep;
	}
	for (auto &e : s.emitters) {
		if (e.active) {
			_splat(s, e);
		}
	}
}

inline float sample_flow_x(const State &s, float x, float z) {
	return s.field[cell_idx(x, z)].vx;
}
inline float sample_flow_z(const State &s, float x, float z) {
	return s.field[cell_idx(x, z)].vz;
}

} // namespace JellygridCurrent
