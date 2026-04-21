/**************************************************************************/
/*  jellygrid_power_node.cpp                                              */
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

// Power node — sandboxed guest program (RISC-V ELF).
// Logic lives in jellygrid_power_node_sim.hpp; this file is the api.hpp wrapper.

#include "jellygrid_power_node_sim.hpp"

#include <api.hpp>

using namespace JellygridPowerNode;

static State g_state;
static float g_overload_threshold = OVERLOAD_THRESHOLD;
static float g_shutdown_duration = SHUTDOWN_DURATION;

static Variant api_receive_jellyfish(int entity_id, float sync_phase) {
	return receive_jellyfish(g_state, sync_phase);
}
static Variant api_tick(float delta) {
	tick(g_state, delta);
	return Nil;
}
static Variant api_get_power_kw() {
	return g_state.current_kw;
}
static Variant api_get_total_kwh() {
	return g_state.total_kwh;
}
static Variant api_is_overloaded() {
	return g_state.overloaded;
}
static Variant api_reset() {
	reset(g_state);
	return Nil;
}

int main() {
	ADD_API_FUNCTION(api_receive_jellyfish, "float", "int entity_id, float sync_phase");
	ADD_API_FUNCTION(api_tick, "void", "float delta");
	ADD_API_FUNCTION(api_get_power_kw, "float", "");
	ADD_API_FUNCTION(api_get_total_kwh, "float", "");
	ADD_API_FUNCTION(api_is_overloaded, "bool", "");
	ADD_API_FUNCTION(api_reset, "void", "");
	ADD_PROPERTY(g_overload_threshold, Variant::FLOAT);
	ADD_PROPERTY(g_shutdown_duration, Variant::FLOAT);
	halt();
}
