// Taskweft HTN planner — pure C++20, no Godot dependency.
// Depth-first search over method decompositions, porting IPyHOP's seek_plan().
#pragma once
#include "tw_domain.hpp"
#include <optional>
#include <unordered_map>
#include <vector>

static constexpr int TW_MAX_DEPTH = 256;

inline std::optional<std::vector<TwCall>> tw_seek_plan(
        std::shared_ptr<TwState> state,
        std::vector<TwTask>      tasks,
        const TwDomain           &domain,
        int                      depth = 0) {

    if (depth > TW_MAX_DEPTH) return std::nullopt;
    if (tasks.empty()) return std::vector<TwCall>{};

    std::vector<TwTask> remaining(tasks.begin() + 1, tasks.end());

    // --- Conjunctive goal (unigoal) ---
    if (TwGoal *goal = std::get_if<TwGoal>(&tasks[0])) {
        if (goal->is_satisfied(*state))
            return tw_seek_plan(state, remaining, domain, depth + 1);

        std::vector<TwGoalBinding> unmet = goal->unsatisfied(*state);
        if (unmet.empty()) return std::nullopt;

        // Pick first unsatisfied binding; try all goal methods for its var.
        const TwGoalBinding &b = unmet[0];
        std::unordered_map<std::string, std::vector<TwGoalMethodFn>>::const_iterator git =
            domain.goal_methods.find(b.var);
        if (git == domain.goal_methods.end()) return std::nullopt;

        std::vector<TwValue> goal_args = {TwValue(b.key), b.desired};
        for (const TwGoalMethodFn &method : git->second) {
            std::optional<std::vector<TwTask>> subs = method(state, goal_args);
            if (!subs) continue;
            std::vector<TwTask> new_tasks;
            new_tasks.insert(new_tasks.end(), subs->begin(), subs->end());
            new_tasks.push_back(*goal);
            new_tasks.insert(new_tasks.end(), remaining.begin(), remaining.end());
            std::optional<std::vector<TwCall>> result = tw_seek_plan(state, new_tasks, domain, depth + 1);
            if (result) return result;
        }
        return std::nullopt;
    }

    // --- Multigoal (RECTGTN 'N'): backtrack over which binding to satisfy first ---
    if (TwMultiGoal *mg = std::get_if<TwMultiGoal>(&tasks[0])) {
        if (mg->is_satisfied(*state))
            return tw_seek_plan(state, remaining, domain, depth + 1);

        std::vector<TwGoalBinding> unmet = mg->unsatisfied(*state);
        if (unmet.empty()) return std::nullopt;

        // Try each unsatisfied binding as the next thing to satisfy (IPyHOP _mg).
        for (size_t idx = 0; idx < unmet.size(); ++idx) {
            TwGoal sub_goal;
            sub_goal.bindings = {unmet[idx]};

            std::vector<TwTask> new_tasks;
            new_tasks.push_back(sub_goal);
            new_tasks.push_back(*mg);
            new_tasks.insert(new_tasks.end(), remaining.begin(), remaining.end());
            std::optional<std::vector<TwCall>> result = tw_seek_plan(state, new_tasks, domain, depth + 1);
            if (result) return result;
        }
        return std::nullopt;
    }

    // --- Primitive action or compound task ---
    TwCall &call = std::get<TwCall>(tasks[0]);

    // Primitive action
    std::unordered_map<std::string, TwActionFn>::const_iterator ait =
        domain.actions.find(call.name);
    if (ait != domain.actions.end()) {
        std::shared_ptr<TwState> new_state = ait->second(state->copy(), call.args);
        if (!new_state) return std::nullopt;
        std::optional<std::vector<TwCall>> sub = tw_seek_plan(new_state, remaining, domain, depth + 1);
        if (!sub) return std::nullopt;
        std::vector<TwCall> plan = {call};
        plan.insert(plan.end(), sub->begin(), sub->end());
        return plan;
    }

    // Compound task: try each method in order
    std::unordered_map<std::string, std::vector<TwMethodFn>>::const_iterator mit =
        domain.task_methods.find(call.name);
    if (mit != domain.task_methods.end()) {
        for (const TwMethodFn &method : mit->second) {
            std::optional<std::vector<TwTask>> subs = method(state, call.args);
            if (!subs) continue;
            std::vector<TwTask> new_tasks;
            new_tasks.insert(new_tasks.end(), subs->begin(), subs->end());
            new_tasks.insert(new_tasks.end(), remaining.begin(), remaining.end());
            std::optional<std::vector<TwCall>> result = tw_seek_plan(state, new_tasks, domain, depth + 1);
            if (result) return result;
        }
        return std::nullopt;
    }

    return std::nullopt;
}

inline std::optional<std::vector<TwCall>> tw_plan(
        std::shared_ptr<TwState> state,
        std::vector<TwTask>      tasks,
        const TwDomain           &domain) {
    return tw_seek_plan(std::move(state), std::move(tasks), domain, 0);
}
