// Power node — sandboxed guest program (RISC-V ELF).
// Logic lives in jellygrid_power_node_sim.hpp; this file is the api.hpp wrapper.

#include <api.hpp>
#include "jellygrid_power_node_sim.hpp"

using namespace JellygridPowerNode;

static State  g_state;
static float  g_overload_threshold = OVERLOAD_THRESHOLD;
static float  g_shutdown_duration  = SHUTDOWN_DURATION;

static Variant api_receive_jellyfish(int entity_id, float sync_phase) { return receive_jellyfish(g_state, sync_phase); }
static Variant api_tick(float delta)       { tick(g_state, delta); return Nil; }
static Variant api_get_power_kw()          { return g_state.current_kw; }
static Variant api_get_total_kwh()         { return g_state.total_kwh; }
static Variant api_is_overloaded()         { return g_state.overloaded; }
static Variant api_reset()                 { reset(g_state); return Nil; }

int main() {
	ADD_API_FUNCTION(api_receive_jellyfish, "float", "int entity_id, float sync_phase");
	ADD_API_FUNCTION(api_tick,             "void",  "float delta");
	ADD_API_FUNCTION(api_get_power_kw,     "float", "");
	ADD_API_FUNCTION(api_get_total_kwh,    "float", "");
	ADD_API_FUNCTION(api_is_overloaded,    "bool",  "");
	ADD_API_FUNCTION(api_reset,            "void",  "");
	ADD_PROPERTY(g_overload_threshold, Variant::FLOAT);
	ADD_PROPERTY(g_shutdown_duration,  Variant::FLOAT);
	halt();
}
