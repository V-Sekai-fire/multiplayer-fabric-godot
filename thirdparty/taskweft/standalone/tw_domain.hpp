// Taskweft domain, goal, and task types — pure C++20, no Godot dependency.
#pragma once
#include "tw_state.hpp"
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>

// Primitive or compound task call: [name, arg1, arg2, ...]
struct TwCall {
    std::string          name;
    std::vector<TwValue> args;
};

// One binding in a conjunctive goal: state[var][key] == desired.
// Matches JSON Pointer "/var/key" with an eq condition.
struct TwGoalBinding {
    std::string var;
    std::string key;
    TwValue     desired;
};

// Conjunctive goal: a list of (var, key, desired) bindings.
// The planner keeps it in the task list until every binding is satisfied,
// trying each unsatisfied binding as a subtask (with backtracking over ordering).
struct TwGoal {
    std::vector<TwGoalBinding> bindings;

    bool is_satisfied(const TwState &state) const {
        for (auto &b : bindings)
            if (state.get_nested(b.var, TwValue(b.key)) != b.desired) return false;
        return true;
    }

    std::vector<TwGoalBinding> unsatisfied(const TwState &state) const {
        std::vector<TwGoalBinding> unmet;
        for (auto &b : bindings)
            if (state.get_nested(b.var, TwValue(b.key)) != b.desired) unmet.push_back(b);
        return unmet;
    }
};

// A task list item is either a task call or a conjunctive goal.
using TwTask = std::variant<TwCall, TwGoal>;

// Action: (state_copy, args) → new_state | nullptr
using TwActionFn =
    std::function<std::shared_ptr<TwState>(std::shared_ptr<TwState>, std::vector<TwValue>)>;

// Task method: (state, args) → subtask_list | nullopt
using TwMethodFn =
    std::function<std::optional<std::vector<TwTask>>(std::shared_ptr<TwState>, std::vector<TwValue>)>;

// Goal method: (state, args=[key, desired]) → subtask_list | nullopt.
// Same signature as TwMethodFn — called with [key, desired] as args.
using TwGoalMethodFn = TwMethodFn;

struct TwDomain {
    std::unordered_map<std::string, TwActionFn>              actions;
    std::unordered_map<std::string, std::vector<TwMethodFn>> task_methods;
    std::unordered_map<std::string, std::vector<TwGoalMethodFn>> goal_methods;

    bool has_action(const std::string &n) const { return actions.count(n) > 0; }
    bool has_task(const std::string &n)   const { return task_methods.count(n) > 0; }
    bool has_goal(const std::string &n)   const { return goal_methods.count(n) > 0; }
};
