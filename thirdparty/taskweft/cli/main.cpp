// Taskweft CLI — load a JSON-LD domain and print the plan.
// Usage:
//   taskweft <domain.jsonld>                     plan from self-contained file
//   taskweft --problem <domain> <problem>        plan from split domain + problem files
//   taskweft --hrr <word> [dim]                  print HRR atom phases for a word
#include "../standalone/tw_loader.hpp"
#include "../standalone/tw_planner.hpp"
#include "../standalone/tw_hrr.hpp"
#include <iostream>
#include <sstream>
#include <string>

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

    TwLoader::TwLoaded loaded;

    if (argc >= 4 && std::string(argv[1]) == "--problem") {
        loaded = TwLoader::load_file_pair(argv[2], argv[3]);
        if (!loaded.state) {
            std::cerr << "taskweft: cannot read domain=" << argv[2] << " or problem=" << argv[3] << "\n";
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
