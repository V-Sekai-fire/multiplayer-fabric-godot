/**************************************************************************/
/*  jellygrid_current.cpp                                                 */
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

// Current routing — sandboxed guest program (RISC-V ELF).
// Logic lives in jellygrid_current_sim.hpp; this file is the api.hpp wrapper.

#include "jellygrid_current_sim.hpp"

#include <api.hpp>

using namespace JellygridCurrent;

static State g_state;
static float g_emitter_sigma = EMITTER_SIGMA;
static float g_decay_rate = DECAY;

static Variant api_place_current(float x, float z, float dx, float dz, float s) {
	return place_current(g_state, x, z, dx, dz, s);
}
static Variant api_remove_current(int slot) {
	remove_current(g_state, slot);
	return Nil;
}
static Variant api_inject_rip_current(float ox, float oz, float intensity) {
	inject_rip_current(g_state, ox, oz, intensity);
	return Nil;
}
static Variant api_tick(float delta) {
	tick(g_state, delta);
	return Nil;
}
static Variant api_sample_flow_x(float x, float z) {
	return sample_flow_x(g_state, x, z);
}
static Variant api_sample_flow_z(float x, float z) {
	return sample_flow_z(g_state, x, z);
}
static Variant api_get_emitter_count() {
	return g_state.emitter_count;
}

int main() {
	ADD_API_FUNCTION(api_place_current, "int", "float x, float z, float dir_x, float dir_z, float strength");
	ADD_API_FUNCTION(api_remove_current, "void", "int slot");
	ADD_API_FUNCTION(api_inject_rip_current, "void", "float origin_x, float origin_z, float intensity");
	ADD_API_FUNCTION(api_tick, "void", "float delta");
	ADD_API_FUNCTION(api_sample_flow_x, "float", "float x, float z");
	ADD_API_FUNCTION(api_sample_flow_z, "float", "float x, float z");
	ADD_API_FUNCTION(api_get_emitter_count, "int", "");
	ADD_PROPERTY(g_emitter_sigma, Variant::FLOAT);
	ADD_PROPERTY(g_decay_rate, Variant::FLOAT);
	halt();
}
