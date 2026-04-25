/**************************************************************************/
/*  taskweft_planner.cpp                                                  */
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

// Taskweft HTN planner + HRR holographic memory — godot-sandbox RISC-V ELF guest.
// Godot host loads a domain JSON string; guest plans and returns JSON.
// HRR algebra exposed for host-side similarity search and state encoding.
// Build with the RISC-V toolchain (see build.sh).
#include "../../../../../modules/taskweft/standalone/tw_hrr.hpp"
#include "../../../../../modules/taskweft/standalone/tw_loader.hpp"
#include "../../../../../modules/taskweft/standalone/tw_planner.hpp"

#include <api.hpp>

static TwLoader::TwLoaded g_loaded;

// Load a JSON-LD domain (full file contents as a string from the host).
static Variant api_load_domain(String json) {
	std::string s(json.utf8().ptr());
	g_loaded = TwLoader::load_json(s);
	return Nil;
}

// Plan using the pre-loaded domain's default task list. Returns JSON string.
static Variant api_plan() {
	auto plan = tw_plan(g_loaded.state, g_loaded.tasks, g_loaded.domain);
	std::string result = plan ? TwLoader::plan_to_json(*plan) : "null";
	return String(result.c_str());
}

// Plan an explicit task list (JSON array of arrays). Returns JSON string.
static Variant api_plan_tasks(String tasks_json) {
	std::string s(tasks_json.utf8().ptr());
	TwValue tasks_val = TwLoader::parse_json_str(s);
	std::vector<TwTask> tasks;
	if (tasks_val.is_array()) {
		for (auto &t : tasks_val.as_array()) {
			if (!t.is_array() || t.as_array().empty()) {
				continue;
			}
			TwCall call;
			call.name = t.as_array()[0].as_string();
			for (size_t i = 1; i < t.as_array().size(); ++i) {
				call.args.push_back(t.as_array()[i]);
			}
			tasks.push_back(std::move(call));
		}
	}
	auto plan = tw_plan(g_loaded.state, tasks, g_loaded.domain);
	std::string result = plan ? TwLoader::plan_to_json(*plan) : "null";
	return String(result.c_str());
}

// ---- HRR holographic memory API -------------------------------------------

// Encode a word → phase vector serialized as base64-like hex string.
// Returns JSON array of floats (the phase vector).
static Variant api_hrr_encode_atom(String word, int dim) {
	auto phases = TwHRR::encode_atom(std::string(word.utf8().ptr()), dim);
	std::string result = "[";
	for (size_t i = 0; i < phases.size(); ++i) {
		if (i) {
			result += ",";
		}
		char buf[32];
		snprintf(buf, sizeof(buf), "%.8f", phases[i]);
		result += buf;
	}
	result += "]";
	return String(result.c_str());
}

// similarity(a_json, b_json) → float. a_json/b_json are JSON float arrays.
static Variant api_hrr_similarity(String a_json, String b_json) {
	auto parse_vec = [](const std::string &s) -> TwHRR::PhaseVec {
		TwValue v = TwLoader::parse_json_str(s);
		TwHRR::PhaseVec phases;
		if (v.is_array()) {
			for (auto &x : v.as_array()) {
				phases.push_back(x.as_number());
			}
		}
		return phases;
	};
	auto a = parse_vec(std::string(a_json.utf8().ptr()));
	auto b = parse_vec(std::string(b_json.utf8().ptr()));
	return (float)TwHRR::similarity(a, b);
}

// encode_text(text, dim) → JSON float array
static Variant api_hrr_encode_text(String text, int dim) {
	auto phases = TwHRR::encode_text(std::string(text.utf8().ptr()), dim);
	std::string result = "[";
	for (size_t i = 0; i < phases.size(); ++i) {
		if (i) {
			result += ",";
		}
		char buf[32];
		snprintf(buf, sizeof(buf), "%.8f", phases[i]);
		result += buf;
	}
	result += "]";
	return String(result.c_str());
}

int main() {
	ADD_API_FUNCTION(api_load_domain, "void", "String json");
	ADD_API_FUNCTION(api_plan, "String", "");
	ADD_API_FUNCTION(api_plan_tasks, "String", "String tasks_json");
	ADD_API_FUNCTION(api_hrr_encode_atom, "String", "String word, int dim");
	ADD_API_FUNCTION(api_hrr_encode_text, "String", "String text, int dim");
	ADD_API_FUNCTION(api_hrr_similarity, "float", "String a_json, String b_json");
	halt();
}
