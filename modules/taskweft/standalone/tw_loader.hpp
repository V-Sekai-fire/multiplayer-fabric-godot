// Taskweft JSON-LD domain loader — pure C++20, no Godot dependency.
// Includes a minimal recursive-descent JSON parser and the domain builder.
#pragma once
#include "tw_domain.hpp"
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace TwLoader {

// ---- Minimal JSON parser → TwValue ----------------------------------------

inline void skip_ws(const char *&p, const char *end) {
    while (p < end && std::isspace((unsigned char)*p)) ++p;
}

inline TwValue parse_json(const char *&p, const char *end);

inline TwValue parse_json_string(const char *&p, const char *end) {
    ++p; // skip opening "
    std::string s;
    while (p < end && *p != '"') {
        if (*p == '\\' && p + 1 < end) {
            ++p;
            switch (*p) {
                case '"':  s += '"';  break;
                case '\\': s += '\\'; break;
                case '/':  s += '/';  break;
                case 'n':  s += '\n'; break;
                case 'r':  s += '\r'; break;
                case 't':  s += '\t'; break;
                default:   s += *p;   break;
            }
        } else {
            s += *p;
        }
        ++p;
    }
    if (p < end) ++p; // skip closing "
    return TwValue(std::move(s));
}

inline TwValue parse_json_number(const char *&p, const char *end) {
    const char *start = p;
    bool is_float = false;
    if (*p == '-') ++p;
    while (p < end && std::isdigit((unsigned char)*p)) ++p;
    if (p < end && *p == '.') {
        is_float = true; ++p;
        while (p < end && std::isdigit((unsigned char)*p)) ++p;
    }
    if (p < end && (*p == 'e' || *p == 'E')) {
        is_float = true; ++p;
        if (p < end && (*p == '+' || *p == '-')) ++p;
        while (p < end && std::isdigit((unsigned char)*p)) ++p;
    }
    std::string tok(start, p - start);
    if (is_float) return TwValue(std::stod(tok));
    try { return TwValue((int64_t)std::stoll(tok)); }
    catch (...) { return TwValue(std::stod(tok)); }
}

inline TwValue parse_json(const char *&p, const char *end) {
    skip_ws(p, end);
    if (p >= end) return TwValue{};

    if (*p == '"') return parse_json_string(p, end);

    if (*p == '[') {
        ++p;
        TwValue::Array arr;
        skip_ws(p, end);
        if (p < end && *p == ']') { ++p; return TwValue(std::move(arr)); }
        while (p < end) {
            arr.push_back(parse_json(p, end));
            skip_ws(p, end);
            if (p < end && *p == ',') { ++p; continue; }
            break;
        }
        if (p < end && *p == ']') ++p;
        return TwValue(std::move(arr));
    }

    if (*p == '{') {
        ++p;
        TwValue::Dict dict;
        skip_ws(p, end);
        if (p < end && *p == '}') { ++p; return TwValue(std::move(dict)); }
        while (p < end) {
            skip_ws(p, end);
            auto key = parse_json_string(p, end);
            skip_ws(p, end);
            if (p < end && *p == ':') ++p;
            dict[key.as_string()] = parse_json(p, end);
            skip_ws(p, end);
            if (p < end && *p == ',') { ++p; continue; }
            break;
        }
        if (p < end && *p == '}') ++p;
        return TwValue(std::move(dict));
    }

    if (*p == '-' || std::isdigit((unsigned char)*p)) return parse_json_number(p, end);

    if (p + 4 <= end && std::strncmp(p, "true",  4) == 0) { p += 4; return TwValue(true); }
    if (p + 5 <= end && std::strncmp(p, "false", 5) == 0) { p += 5; return TwValue(false); }
    if (p + 4 <= end && std::strncmp(p, "null",  4) == 0) { p += 4; return TwValue{}; }

    ++p;
    return TwValue{};
}

inline TwValue parse_json_str(const std::string &json) {
    const char *p = json.c_str();
    return parse_json(p, p + json.size());
}

// ---- Expression evaluators -------------------------------------------------

using Params = std::unordered_map<std::string, TwValue>;

// "{name}" → params[name], anything else returned as-is.
inline TwValue resolve_param(const TwValue &val, const Params &params) {
    if (!val.is_string()) return val;
    const auto &s = val.as_string();
    if (s.size() >= 3 && s.front() == '{' && s.back() == '}') {
        std::string name = s.substr(1, s.size() - 2);
        auto it = params.find(name);
        if (it != params.end()) return it->second;
    }
    return val;
}

// "/var/{key}" → {var, resolved_key}. Returns {"", nil} on malformed input.
inline std::pair<std::string, TwValue> parse_pointer(
        const std::string &ptr, const Params &params) {
    std::vector<std::string> parts;
    std::string cur;
    for (char c : ptr) {
        if (c == '/') { parts.push_back(cur); cur.clear(); }
        else cur += c;
    }
    parts.push_back(cur);

    int offset = (!parts.empty() && parts[0].empty()) ? 1 : 0;
    if ((int)parts.size() < offset + 2) return {"", TwValue{}};

    return {parts[offset], resolve_param(TwValue(parts[offset + 1]), params)};
}

// Forward declaration.
inline TwValue eval_expr(const TwValue &expr, const Params &params,
        const TwState &state, const TwValue::Dict &enums);

inline TwValue eval_op(const TwValue::Dict &expr, const Params &params,
        const TwState &state, const TwValue::Dict &enums) {

    auto op_it = expr.find("op");
    if (op_it == expr.end() || !op_it->second.is_string()) return TwValue{};
    const std::string &op = op_it->second.as_string();

    auto get = [&](const char *k) -> TwValue {
        auto it = expr.find(k);
        return it != expr.end() ? eval_expr(it->second, params, state, enums) : TwValue{};
    };

    if (op == "get") {
        auto pit = expr.find("pointer");
        if (pit == expr.end()) return TwValue{};
        auto [var, key] = parse_pointer(pit->second.as_string(), params);
        return var.empty() ? TwValue{} : state.get_nested(var, key);
    }

    TwValue a = get("a"), b = get("b");

    auto num2 = [&](auto fn) -> TwValue {
        if (a.is_int() && b.is_int())
            return TwValue((int64_t)fn(a.as_int(), b.as_int()));
        return TwValue(fn(a.as_number(), b.as_number()));
    };

    if (op == "add")  return num2([](auto x, auto y){ return x + y; });
    if (op == "sub")  return num2([](auto x, auto y){ return x - y; });
    if (op == "mul")  return num2([](auto x, auto y){ return x * y; });
    if (op == "div") {
        if (a.is_int() && b.is_int()) {
            int64_t bi = b.as_int(); return bi ? TwValue(a.as_int() / bi) : TwValue{};
        }
        double bd = b.as_number(); return bd != 0.0 ? TwValue(a.as_number() / bd) : TwValue{};
    }
    if (op == "iadd") return TwValue(a.as_int() + b.as_int());
    if (op == "isub") return TwValue(a.as_int() - b.as_int());
    if (op == "imul") return TwValue(a.as_int() * b.as_int());
    if (op == "idiv") { int64_t bi = b.as_int(); return bi ? TwValue(a.as_int()/bi) : TwValue{}; }
    if (op == "neg")  return a.is_int() ? TwValue(-a.as_int()) : TwValue(-a.as_number());
    if (op == "abs")  return a.is_int() ? TwValue(std::abs(a.as_int())) : TwValue(std::abs(a.as_number()));
    if (op == "min")  return a < b ? a : b;
    if (op == "max")  return a > b ? a : b;
    return TwValue{};
}

inline TwValue eval_expr(const TwValue &expr, const Params &params,
        const TwState &state, const TwValue::Dict &enums) {
    if (expr.is_dict()) {
        const auto &d = expr.as_dict();
        if (d.count("op")) return eval_op(d, params, state, enums);
    }
    return resolve_param(expr, params);
}

// Detect which comparison operator a check step uses.
inline std::string check_op(const TwValue::Dict &step) {
    for (const char *op : {"eq","neq","lt","le","gt","ge","ieq","ilt","ile","igt","ige"})
        if (step.count(op)) return op;
    return "eq";
}

inline bool compare_values(const TwValue &actual, const TwValue &expected,
        const std::string &op) {
    if (op == "eq"  || op == "ieq") {
        if (actual.is_number() && expected.is_number())
            return actual.as_number() == expected.as_number();
        return actual == expected;
    }
    if (op == "neq") return actual != expected;
    if (op == "lt"  || op == "ilt") return actual <  expected;
    if (op == "le"  || op == "ile") return actual <= expected;
    if (op == "gt"  || op == "igt") return actual >  expected;
    if (op == "ge"  || op == "ige") return actual >= expected;
    return false;
}

// ---- Domain building helpers -----------------------------------------------

inline Params build_params(const TwValue::Array &names, const std::vector<TwValue> &args) {
    Params p;
    for (size_t i = 0; i < names.size() && i < args.size(); ++i)
        p[names[i].as_string()] = args[i];
    return p;
}

inline void run_binds(const TwValue::Array &binds, Params &params, const TwState &state) {
    for (auto &bind : binds) {
        if (!bind.is_dict()) continue;
        const auto &bd = bind.as_dict();
        auto name_it = bd.find("name");
        auto ptr_it  = bd.find("pointer");
        if (name_it == bd.end() || ptr_it == bd.end()) continue;
        auto [var, key] = parse_pointer(ptr_it->second.as_string(), params);
        if (!var.empty())
            params[name_it->second.as_string()] = state.get_nested(var, key);
    }
}

inline bool run_checks(const TwValue::Array &checks, const Params &params,
        const TwState &state, const TwValue::Dict &enums) {
    for (auto &step : checks) {
        if (!step.is_dict()) return false;
        const auto &cs = step.as_dict();

        std::pair<std::string, TwValue> ptr;
        auto ptr_it = cs.find("pointer");
        auto var_it = cs.find("var");
        if (ptr_it != cs.end()) {
            ptr = parse_pointer(ptr_it->second.as_string(), params);
        } else if (var_it != cs.end()) {
            auto &raw = var_it->second;
            if (raw.is_string())
                ptr = parse_pointer(raw.as_string(), params);
            else if (raw.is_array() && raw.as_array().size() == 2)
                ptr = {raw.as_array()[0].as_string(),
                       resolve_param(raw.as_array()[1], params)};
            else return false;
        } else return false;

        if (ptr.first.empty()) return false;

        TwValue actual   = state.get_nested(ptr.first, ptr.second);
        std::string op   = check_op(cs);
        auto op_it       = cs.find(op);
        if (op_it == cs.end()) return false;
        TwValue expected = resolve_param(op_it->second, params);

        if (!compare_values(actual, expected, op)) return false;
    }
    return true;
}

inline std::vector<TwTask> expand_subtasks(const TwValue::Array &defs, const Params &params) {
    std::vector<TwTask> tasks;
    for (auto &def : defs) {
        if (!def.is_array() || def.as_array().empty()) continue;
        const auto &arr = def.as_array();
        TwCall call;
        call.name = resolve_param(arr[0], params).as_string();
        for (size_t i = 1; i < arr.size(); ++i)
            call.args.push_back(resolve_param(arr[i], params));
        tasks.push_back(std::move(call));
    }
    return tasks;
}

// ---- Callable builders -----------------------------------------------------

inline TwActionFn build_action(const TwValue::Dict &def, const TwValue::Dict &enums) {
    TwValue::Array param_names, bind_defs, body;
    auto get_arr = [&](const char *k) -> TwValue::Array {
        auto it = def.find(k);
        return (it != def.end() && it->second.is_array()) ? it->second.as_array() : TwValue::Array{};
    };
    param_names = get_arr("params");
    bind_defs   = get_arr("bind");
    body        = get_arr("body");

    return [param_names, bind_defs, body, enums](
            std::shared_ptr<TwState> state, std::vector<TwValue> args)
            -> std::shared_ptr<TwState> {
        Params params = build_params(param_names, args);
        run_binds(bind_defs, params, *state);

        auto new_state = state->copy();

        for (auto &step : body) {
            if (!step.is_dict()) return nullptr;
            const auto &s = step.as_dict();

            auto check_it = s.find("check");
            auto set_it   = s.find("set");

            if (check_it != s.end()) {
                auto [var, key] = parse_pointer(check_it->second.as_string(), params);
                if (var.empty()) return nullptr;
                TwValue actual   = new_state->get_nested(var, key);
                std::string op   = check_op(s);
                auto op_it       = s.find(op);
                if (op_it == s.end()) return nullptr;
                TwValue expected = eval_expr(op_it->second, params, *new_state, enums);
                if (!compare_values(actual, expected, op)) return nullptr;
            } else if (set_it != s.end()) {
                auto [var, key] = parse_pointer(set_it->second.as_string(), params);
                if (var.empty()) return nullptr;
                auto val_it = s.find("value");
                if (val_it == s.end()) return nullptr;
                TwValue value = eval_expr(val_it->second, params, *new_state, enums);
                new_state->set_nested(var, key, std::move(value));
            }
        }
        return new_state;
    };
}

inline TwMethodFn build_method_alt(const TwValue::Array &param_names,
        const TwValue::Dict &alt, const TwValue::Dict &enums) {
    auto get_arr = [&](const char *k) -> TwValue::Array {
        auto it = alt.find(k);
        return (it != alt.end() && it->second.is_array()) ? it->second.as_array() : TwValue::Array{};
    };
    TwValue::Array bind_defs   = get_arr("bind");
    TwValue::Array check_defs  = get_arr("check");
    TwValue::Array subtask_defs = get_arr("subtasks");

    return [param_names, bind_defs, check_defs, subtask_defs, enums](
            std::shared_ptr<TwState> state, std::vector<TwValue> args)
            -> std::optional<std::vector<TwTask>> {
        Params params = build_params(param_names, args);
        run_binds(bind_defs, params, *state);
        if (!run_checks(check_defs, params, *state, enums)) return std::nullopt;
        return expand_subtasks(subtask_defs, params);
    };
}

inline TwGoalMethodFn build_goal_method_alt(const TwValue::Array &goal_param_names,
        const TwValue::Dict &alt, const TwValue::Dict &enums) {
    auto get_arr = [&](const char *k) -> TwValue::Array {
        auto it = alt.find(k);
        return (it != alt.end() && it->second.is_array()) ? it->second.as_array() : TwValue::Array{};
    };
    TwValue::Array bind_defs    = get_arr("bind");
    TwValue::Array check_defs   = get_arr("check");
    TwValue::Array subtask_defs = get_arr("subtasks");

    return [goal_param_names, bind_defs, check_defs, subtask_defs, enums](
            std::shared_ptr<TwState> state, TwValue desired)
            -> std::optional<std::vector<TwTask>> {
        Params params;
        if (!goal_param_names.empty())
            params[goal_param_names[0].as_string()] = desired;
        run_binds(bind_defs, params, *state);
        if (!run_checks(check_defs, params, *state, enums)) return std::nullopt;
        return expand_subtasks(subtask_defs, params);
    };
}

// ---- Main loader -----------------------------------------------------------

struct TwLoaded {
    TwDomain                 domain;
    std::shared_ptr<TwState> state;
    std::vector<TwTask>      tasks;
    TwValue::Dict            enums;
};

inline TwLoaded load_domain(const TwValue &data) {
    TwLoaded result;
    result.state = std::make_shared<TwState>();
    if (!data.is_dict()) return result;
    const auto &d = data.as_dict();

    // Enums
    if (auto it = d.find("enums"); it != d.end() && it->second.is_dict())
        result.enums = it->second.as_dict();
    const auto &enums = result.enums;

    // Variables
    if (auto it = d.find("variables"); it != d.end() && it->second.is_array()) {
        for (auto &var_def : it->second.as_array()) {
            if (!var_def.is_dict()) continue;
            const auto &vd = var_def.as_dict();
            auto name_it = vd.find("name");
            auto init_it = vd.find("init");
            if (name_it == vd.end() || init_it == vd.end()) continue;
            const std::string &var_name = name_it->second.as_string();
            const auto &init = init_it->second;
            if (init.is_dict()) {
                for (auto &[key, val] : init.as_dict())
                    result.state->set_nested(var_name, TwValue(key), val);
            } else {
                result.state->set_var(var_name, init);
            }
        }
    }

    // Actions
    if (auto it = d.find("actions"); it != d.end() && it->second.is_dict()) {
        for (auto &[name, def] : it->second.as_dict()) {
            if (!def.is_dict()) continue;
            result.domain.actions[name] = build_action(def.as_dict(), enums);
        }
    }

    // Task methods
    if (auto it = d.find("methods"); it != d.end() && it->second.is_dict()) {
        for (auto &[task_name, group] : it->second.as_dict()) {
            if (!group.is_dict()) continue;
            const auto &gd = group.as_dict();

            TwValue::Array param_names;
            if (auto pit = gd.find("params"); pit != gd.end() && pit->second.is_array())
                param_names = pit->second.as_array();

            auto alts_it = gd.find("alternatives");
            if (alts_it == gd.end() || !alts_it->second.is_array()) continue;

            std::vector<TwMethodFn> fns;
            for (auto &alt : alts_it->second.as_array()) {
                if (!alt.is_dict()) continue;
                fns.push_back(build_method_alt(param_names, alt.as_dict(), enums));
            }
            result.domain.task_methods[task_name] = std::move(fns);
        }
    }

    // Goal methods
    if (auto it = d.find("goals"); it != d.end() && it->second.is_dict()) {
        for (auto &[goal_var, group] : it->second.as_dict()) {
            if (!group.is_dict()) continue;
            const auto &gd = group.as_dict();

            TwValue::Array goal_params;
            if (auto pit = gd.find("params"); pit != gd.end() && pit->second.is_array())
                goal_params = pit->second.as_array();

            auto alts_it = gd.find("alternatives");
            if (alts_it == gd.end() || !alts_it->second.is_array()) continue;

            std::vector<TwGoalMethodFn> fns;
            for (auto &alt : alts_it->second.as_array()) {
                if (!alt.is_dict()) continue;
                fns.push_back(build_goal_method_alt(goal_params, alt.as_dict(), enums));
            }
            result.domain.goal_methods[goal_var] = std::move(fns);
        }
    }

    // Initial task list
    if (auto it = d.find("tasks"); it != d.end() && it->second.is_array()) {
        for (auto &task_def : it->second.as_array()) {
            if (!task_def.is_array() || task_def.as_array().empty()) continue;
            const auto &arr = task_def.as_array();
            TwCall call;
            call.name = arr[0].as_string();
            for (size_t i = 1; i < arr.size(); ++i) call.args.push_back(arr[i]);
            result.tasks.push_back(std::move(call));
        }
    }

    return result;
}

inline TwLoaded load_json(const std::string &json_str) {
    return load_domain(parse_json_str(json_str));
}

inline TwLoaded load_file(const std::string &path) {
    std::ifstream f(path);
    if (!f) return TwLoaded{};
    std::ostringstream oss;
    oss << f.rdbuf();
    return load_json(oss.str());
}

// Serialise a plan as a JSON array string.
inline std::string plan_to_json(const std::vector<TwCall> &plan) {
    std::ostringstream oss;
    oss << "[";
    for (size_t i = 0; i < plan.size(); ++i) {
        if (i) oss << ", ";
        oss << "[\"" << plan[i].name << "\"";
        for (auto &arg : plan[i].args) oss << ", \"" << arg.to_string() << "\"";
        oss << "]";
    }
    oss << "]";
    return oss.str();
}

} // namespace TwLoader
