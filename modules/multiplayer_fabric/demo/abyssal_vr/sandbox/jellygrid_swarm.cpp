// Jellyfish swarm — sandboxed guest program (RISC-V ELF).
// Logic lives in jellygrid_swarm_sim.hpp; this file is the api.hpp wrapper.
// Build with: RISC-V C++ toolchain, -I path pointing at modules/multiplayer_fabric_mmog

#include <api.hpp>
// jellygrid_swarm_sim.hpp has no Godot or api.hpp dependency — pure C++.
#include "jellygrid_swarm_sim.hpp"

using namespace JellygridSwarm;

static State g_state;
static float g_bloom_ttl  = BLOOM_TTL;
static float g_base_speed = BASE_SPEED;

static Variant api_tick(float delta)                         { tick(g_state, delta); return Nil; }
static Variant api_apply_current(float x, float y, float z) { apply_current(g_state, x, z, x, z); return Nil; }
static Variant api_inject_rip_current(float ox, float oz)   { inject_rip_current(g_state, ox, oz); return Nil; }
static Variant api_add_predator(float x, float y, float z)  { add_predator(g_state, x, y, z); return Nil; }
static Variant api_spawn_jellyfish(int id)                   { spawn(g_state, id); return Nil; }
static Variant api_jellyfish_reached_node(int id)            { return jellyfish_reached_node(g_state, id); }
static Variant api_get_alive_count()                         { return g_state.alive_count; }
static Variant api_get_power_output()                        { return g_state.power_tick_kw; }

int main() {
	ADD_API_FUNCTION(api_tick,                   "void",  "float delta");
	ADD_API_FUNCTION(api_apply_current,          "void",  "float x, float y, float z");
	ADD_API_FUNCTION(api_inject_rip_current,     "void",  "float origin_x, float origin_z");
	ADD_API_FUNCTION(api_add_predator,           "void",  "float x, float y, float z");
	ADD_API_FUNCTION(api_spawn_jellyfish,        "void",  "int id");
	ADD_API_FUNCTION(api_jellyfish_reached_node, "void",  "int id");
	ADD_API_FUNCTION(api_get_alive_count,        "int",   "");
	ADD_API_FUNCTION(api_get_power_output,       "float", "");
	ADD_PROPERTY(g_bloom_ttl,  Variant::FLOAT);
	ADD_PROPERTY(g_base_speed, Variant::FLOAT);
	halt();
}
