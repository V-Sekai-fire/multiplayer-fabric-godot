// Current routing — sandboxed guest program (RISC-V ELF).
// Logic lives in jellygrid_current_sim.hpp; this file is the api.hpp wrapper.

#include <api.hpp>
#include "jellygrid_current_sim.hpp"

using namespace JellygridCurrent;

static State g_state;
static float g_emitter_sigma = EMITTER_SIGMA;
static float g_decay_rate    = DECAY;

static Variant api_place_current(float x, float z, float dx, float dz, float s) { return place_current(g_state, x, z, dx, dz, s); }
static Variant api_remove_current(int slot)                                       { remove_current(g_state, slot); return Nil; }
static Variant api_inject_rip_current(float ox, float oz, float intensity)        { inject_rip_current(g_state, ox, oz, intensity); return Nil; }
static Variant api_tick(float delta)                                               { tick(g_state, delta); return Nil; }
static Variant api_sample_flow_x(float x, float z)                                { return sample_flow_x(g_state, x, z); }
static Variant api_sample_flow_z(float x, float z)                                { return sample_flow_z(g_state, x, z); }
static Variant api_get_emitter_count()                                             { return g_state.emitter_count; }

int main() {
	ADD_API_FUNCTION(api_place_current,      "int",   "float x, float z, float dir_x, float dir_z, float strength");
	ADD_API_FUNCTION(api_remove_current,     "void",  "int slot");
	ADD_API_FUNCTION(api_inject_rip_current, "void",  "float origin_x, float origin_z, float intensity");
	ADD_API_FUNCTION(api_tick,               "void",  "float delta");
	ADD_API_FUNCTION(api_sample_flow_x,      "float", "float x, float z");
	ADD_API_FUNCTION(api_sample_flow_z,      "float", "float x, float z");
	ADD_API_FUNCTION(api_get_emitter_count,  "int",   "");
	ADD_PROPERTY(g_emitter_sigma, Variant::FLOAT);
	ADD_PROPERTY(g_decay_rate,    Variant::FLOAT);
	halt();
}
