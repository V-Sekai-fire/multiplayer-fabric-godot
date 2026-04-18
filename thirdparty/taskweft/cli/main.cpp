// Taskweft CLI — load a JSON-LD domain and print the plan.
// Usage:
//   taskweft <domain.jsonld>                           plan from self-contained file
//   taskweft --problem <domain> <problem>              plan from split domain + problem files
//   taskweft --temporal <domain> [problem]             plan + STN temporal analysis (JSON)
//   taskweft --simulate <domain> [problem]             simulate plan execution (JSON)
//   taskweft --replan <fail_step> <domain> [problem]   replan after action failure (JSON)
//   taskweft --hrr <word> [dim]                        print HRR atom phases for a word
#include "../standalone/tw_loader.hpp"
#include "../standalone/tw_planner.hpp"
#include "../standalone/tw_temporal.hpp"
#include "../standalone/tw_replan.hpp"
#include "../standalone/tw_hrr.hpp"
#include <iostream>
#include <sstream>
#include <string>

// Emit a plan as JSON (reused in multiple modes).
static void print_plan_json(const std::vector<TwCall> &plan) {
    std::cout << TwLoader::plan_to_json(plan) << "\n";
}

// Emit a TwTemporalResult as JSON.
static void print_temporal_json(const std::vector<TwCall> &plan,
                                const TwTemporalResult &tr) {
    std::cout << "{\n";
    std::cout << "  \"plan\": " << TwLoader::plan_to_json(plan) << ",\n";
    std::cout << "  \"temporal\": {\n";
    std::cout << "    \"consistent\": " << (tr.consistent ? "true" : "false") << ",\n";
    std::cout << "    \"total_seconds\": " << tr.total_seconds << ",\n";
    std::cout << "    \"total_iso\": \"" << tr.total_iso << "\",\n";
    std::cout << "    \"steps\": [";
    for (size_t i = 0; i < tr.steps.size(); ++i) {
        if (i) std::cout << ", ";
        std::cout << "{\"action\": \"" << tr.steps[i].action_name
                  << "\", \"seconds\": " << tr.steps[i].duration_seconds;
        if (!tr.steps[i].duration_iso.empty())
            std::cout << ", \"iso\": \"" << tr.steps[i].duration_iso << "\"";
        std::cout << "}";
    }
    std::cout << "]\n";
    std::cout << "  }\n";
    std::cout << "}\n";
}

int main(int argc, char **argv) {
    // HRR sub-command
    if (argc >= 3 && std::string(argv[1]) == "--hrr") {
        int dim = argc >= 4 ? std::stoi(argv[3]) : 16;
        auto phases = TwHRR::encode_atom(argv[2], dim);
        std::cout << "[";
        for (int i = 0; i < (int)phases.size(); ++i) {
            if (i) std::cout << ", ";
            std::cout << phases[i];
        }
        std::cout << "]\n";
        double snr = TwHRR::snr_estimate(dim, 1);
        std::cout << "SNR(dim=" << dim << ", 1 item): " << snr << "\n";
        return 0;
    }

    // --temporal: plan + STN temporal analysis
    if (argc >= 3 && std::string(argv[1]) == "--temporal") {
        TwLoader::TwLoaded loaded;
        if (argc >= 4)
            loaded = TwLoader::load_file_pair(argv[2], argv[3]);
        else
            loaded = TwLoader::load_file(argv[2]);
        if (!loaded.state) {
            std::cerr << "taskweft: cannot read file(s)\n";
            return 1;
        }
        auto plan = tw_plan(loaded.state, loaded.tasks, loaded.domain);
        if (!plan) { std::cout << "null\n"; return 1; }
        TwTemporalResult tr = tw_check_temporal(*plan, loaded.domain);
        print_temporal_json(*plan, tr);
        return 0;
    }

    // --simulate: apply plan step-by-step, report failure point
    if (argc >= 3 && std::string(argv[1]) == "--simulate") {
        TwLoader::TwLoaded loaded;
        if (argc >= 4)
            loaded = TwLoader::load_file_pair(argv[2], argv[3]);
        else
            loaded = TwLoader::load_file(argv[2]);
        if (!loaded.state) {
            std::cerr << "taskweft: cannot read file(s)\n";
            return 1;
        }
        auto plan = tw_plan(loaded.state, loaded.tasks, loaded.domain);
        if (!plan) { std::cout << "null\n"; return 1; }
        TwSimulateResult sr = tw_simulate(loaded.state, *plan, loaded.domain);
        std::cout << "{\n";
        std::cout << "  \"plan\": " << TwLoader::plan_to_json(*plan) << ",\n";
        std::cout << "  \"completed_steps\": " << sr.completed_steps << ",\n";
        std::cout << "  \"fail_step\": " << sr.fail_step << ",\n";
        std::cout << "  \"success\": " << (sr.fail_step < 0 ? "true" : "false") << "\n";
        std::cout << "}\n";
        return 0;
    }

    // --replan N: inject failure at step N, then replan
    if (argc >= 4 && std::string(argv[1]) == "--replan") {
        int fail_step = std::stoi(argv[2]);
        TwLoader::TwLoaded loaded;
        if (argc >= 5)
            loaded = TwLoader::load_file_pair(argv[3], argv[4]);
        else
            loaded = TwLoader::load_file(argv[3]);
        if (!loaded.state) {
            std::cerr << "taskweft: cannot read file(s)\n";
            return 1;
        }
        auto plan = tw_plan(loaded.state, loaded.tasks, loaded.domain);
        if (!plan) { std::cout << "null\n"; return 1; }
        TwReplanResult rr = tw_replan(loaded.state, *plan, loaded.tasks,
                                      loaded.domain, fail_step);
        std::cout << "{\n";
        std::cout << "  \"original_plan\": " << TwLoader::plan_to_json(*plan) << ",\n";
        std::cout << "  \"fail_step\": " << fail_step << ",\n";
        std::cout << "  \"completed_steps\": " << rr.simulate.completed_steps << ",\n";
        std::cout << "  \"recovered\": " << (rr.recovered ? "true" : "false") << ",\n";
        if (rr.recovered)
            std::cout << "  \"new_plan\": " << TwLoader::plan_to_json(*rr.new_plan) << "\n";
        else
            std::cout << "  \"new_plan\": null\n";
        std::cout << "}\n";
        return 0;
    }

    // Default: plan and print
    TwLoader::TwLoaded loaded;
    if (argc >= 4 && std::string(argv[1]) == "--problem") {
        loaded = TwLoader::load_file_pair(argv[2], argv[3]);
        if (!loaded.state) {
            std::cerr << "taskweft: cannot read domain=" << argv[2]
                      << " or problem=" << argv[3] << "\n";
            return 1;
        }
    } else if (argc >= 2) {
        loaded = TwLoader::load_file(argv[1]);
        if (!loaded.state) {
            std::cerr << "taskweft: cannot read " << argv[1] << "\n";
            return 1;
        }
    } else {
        std::ostringstream oss;
        oss << std::cin.rdbuf();
        loaded = TwLoader::load_json(oss.str());
    }

    auto plan = tw_plan(loaded.state, loaded.tasks, loaded.domain);
    if (!plan) {
        std::cout << "null\n";
        return 1;
    }

    std::cout << TwLoader::plan_to_json(*plan) << "\n";
    return 0;
}
