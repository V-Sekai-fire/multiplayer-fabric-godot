// Taskweft planning state — pure C++20, no Godot dependency.
#pragma once
#include "tw_value.hpp"
#include <memory>
#include <string>
#include <unordered_map>

struct TwState {
    std::unordered_map<std::string, TwValue> vars;

    void set_var(const std::string &key, TwValue val) { vars[key] = std::move(val); }

    TwValue get_var(const std::string &key) const {
        auto it = vars.find(key);
        return it != vars.end() ? it->second : TwValue{};
    }

    bool has_var(const std::string &key) const { return vars.count(key) > 0; }

    // set_nested always creates a new Dict entry so copies share nothing.
    void set_nested(const std::string &var, const TwValue &key, TwValue val) {
        TwValue::Dict dict;
        if (vars.count(var) && vars.at(var).is_dict())
            dict = vars.at(var).as_dict();
        dict[key.to_string()] = std::move(val);
        vars[var] = TwValue(std::move(dict));
    }

    TwValue get_nested(const std::string &var, const TwValue &key) const {
        auto it = vars.find(var);
        if (it == vars.end() || !it->second.is_dict()) return TwValue{};
        auto &d = it->second.as_dict();
        auto kit = d.find(key.to_string());
        return kit != d.end() ? kit->second : TwValue{};
    }

    bool has_nested(const std::string &var, const TwValue &key) const {
        auto it = vars.find(var);
        if (it == vars.end() || !it->second.is_dict()) return false;
        return it->second.as_dict().count(key.to_string()) > 0;
    }

    // Deep copy — TwValue copy constructor handles nested data.
    std::shared_ptr<TwState> copy() const {
        auto c = std::make_shared<TwState>();
        c->vars = vars;
        return c;
    }
};
