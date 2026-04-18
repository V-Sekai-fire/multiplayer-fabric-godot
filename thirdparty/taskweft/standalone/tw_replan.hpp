// RECTGTN 'R' — Replan: simulate plan execution and recover from action failure.
// Mirrors Python plan_jsonld.py _do_simulate() and _do_replan(), and
// IPyHOP planner.blacklist_command() for command-vs-action distinction.
#pragma once
#include "tw_domain.hpp"
#include "tw_planner.hpp"
#include <memory>
#include <optional>
#include <string>
#include <vector>

// Result of simulating a plan step-by-step.
struct TwSimulateResult {
    int completed_steps;             // number of actions successfully applied
    int fail_step;                   // index of the failed action, or -1 if all succeeded
    std::string fail_action;         // name of the failed action, or ""
    std::shared_ptr<TwState> state;  // state after completed_steps actions
};

// Apply plan actions one by one, stopping at the first failure.
// Mirrors _do_simulate() in plan_jsonld.py.
inline TwSimulateResult tw_simulate(
        std::shared_ptr<TwState> init_state,
        const std::vector<TwCall> &plan,
        const TwDomain &domain) {
    TwSimulateResult r;
    r.completed_steps = 0;
    r.fail_step       = -1;

    std::shared_ptr<TwState> cur = init_state->copy();
    for (int i = 0; i < (int)plan.size(); ++i) {
        std::unordered_map<std::string, TwActionFn>::const_iterator it =
            domain.actions.find(plan[i].name);
        if (it == domain.actions.end()) {
            r.fail_step   = i;
            r.fail_action = plan[i].name;
            r.state       = cur;
            return r;
        }
        std::shared_ptr<TwState> next = it->second(cur, plan[i].args);
        if (!next) {
            r.fail_step   = i;
            r.fail_action = plan[i].name;
            r.state       = cur;
            return r;
        }
        cur = next;
        r.completed_steps = i + 1;
    }
    r.state = cur;
    return r;
}

// Result of a replan operation.
struct TwReplanResult {
    TwSimulateResult simulate;        // how far the original plan ran
    std::optional<std::vector<TwCall>> new_plan;  // recovered plan, or nullopt
    bool recovered;                   // true if new_plan was found
    TwBlacklist blacklist;            // commands blacklisted for this replan
};

// Simulate original_plan up to fail_step (or until first failure if fail_step < 0).
// Then replan from the state at failure using the original task list.
//
// The failed command is blacklisted (mirrors IPyHOP blacklist_command): the planner
// will not re-select the exact same (action, args) instance that failed at runtime,
// forcing it to find an alternative.  This is the key command-vs-action distinction:
//   action  = the function definition (TwActionFn)
//   command = a specific instantiation with concrete args (TwCall) that can be
//             individually blacklisted when it fails at execution time.
inline TwReplanResult tw_replan(
        std::shared_ptr<TwState> init_state,
        const std::vector<TwCall> &original_plan,
        const std::vector<TwTask> &original_tasks,
        const TwDomain &domain,
        int fail_step = -1) {
    TwReplanResult r;

    // Simulate to determine state at failure.
    if (fail_step < 0 || fail_step >= (int)original_plan.size()) {
        r.simulate = tw_simulate(init_state, original_plan, domain);
    } else {
        // Simulate only up to the specified fail_step to get pre-failure state.
        std::vector<TwCall> prefix(original_plan.begin(),
                                   original_plan.begin() + fail_step);
        TwSimulateResult partial = tw_simulate(init_state, prefix, domain);
        r.simulate.completed_steps = fail_step;
        r.simulate.fail_step       = fail_step;
        r.simulate.fail_action     = original_plan[fail_step].name;
        r.simulate.state           = partial.state;
    }

    std::shared_ptr<TwState> replan_state =
        r.simulate.state ? r.simulate.state : init_state;

    // Blacklist the specific command that failed at runtime so the replanner
    // is forced to find an alternative path (not just retry the same step).
    if (r.simulate.fail_step >= 0 && r.simulate.fail_step < (int)original_plan.size())
        r.blacklist.insert(tw_call_key(original_plan[r.simulate.fail_step]));

    r.new_plan  = tw_plan(replan_state, original_tasks, domain, &r.blacklist);
    r.recovered = r.new_plan.has_value();
    return r;
}
