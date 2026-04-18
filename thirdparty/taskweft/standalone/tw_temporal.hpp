// RECTGTN 'T' — Temporal: ISO 8601 duration parsing, STN consistency, plan timing.
// Mirrors Python ipyhop/temporal/stn.py and temporal_metadata.py.
#pragma once
#include "tw_domain.hpp"
#include <cmath>
#include <limits>
#include <string>
#include <unordered_map>
#include <vector>

// Parse ISO 8601 time-duration string (PTxHxMxS) → total seconds.
// Only handles the time part (PT prefix); day/year/month not supported.
// Returns -1.0 on parse failure.
inline double tw_parse_duration(const std::string &dur) {
    if (dur.size() < 2 || dur[0] != 'P') return -1.0;
    size_t i = 1;
    // Skip optional 'T' time designator
    if (i < dur.size() && dur[i] == 'T') ++i;
    double total = 0.0;
    while (i < dur.size()) {
        double val = 0.0;
        bool has_digit = false;
        // Integer part
        while (i < dur.size() && std::isdigit((unsigned char)dur[i])) {
            has_digit = true;
            val = val * 10.0 + (dur[i++] - '0');
        }
        // Fractional part
        if (i < dur.size() && dur[i] == '.') {
            ++i;
            double frac = 0.1;
            while (i < dur.size() && std::isdigit((unsigned char)dur[i])) {
                val += (dur[i++] - '0') * frac;
                frac *= 0.1;
            }
        }
        if (!has_digit || i >= dur.size()) break;
        char unit = dur[i++];
        if      (unit == 'H') total += val * 3600.0;
        else if (unit == 'M') total += val * 60.0;
        else if (unit == 'S') total += val;
    }
    return total;
}

// Format total seconds → ISO 8601 duration string (PTxHxMxS).
inline std::string tw_format_duration(double seconds) {
    if (seconds < 0.0) seconds = 0.0;
    int h = (int)(seconds / 3600.0);
    seconds -= h * 3600.0;
    int m = (int)(seconds / 60.0);
    seconds -= m * 60.0;

    std::string s = "PT";
    if (h > 0) s += std::to_string(h) + "H";
    if (m > 0) s += std::to_string(m) + "M";
    if (seconds > 0.0 || (h == 0 && m == 0)) {
        if (seconds == (double)(int)seconds)
            s += std::to_string((int)seconds) + "S";
        else {
            char buf[32];
            std::snprintf(buf, sizeof(buf), "%.6gS", seconds);
            s += buf;
        }
    }
    return s;
}

// STN is an implementation detail — hidden from callers.
// Public interface: TwTemporalStep, TwTemporalResult, tw_check_temporal().
namespace tw_detail {
struct STN {
    static constexpr double INF = std::numeric_limits<double>::infinity();

    std::vector<std::string>                points;
    std::unordered_map<std::string, size_t> idx;
    std::vector<std::vector<double>>        dist;

    void add_point(const std::string &p) {
        if (idx.count(p)) return;
        size_t n = points.size();
        idx[p] = n;
        points.push_back(p);
        for (auto &row : dist) row.push_back(INF);
        dist.push_back(std::vector<double>(n + 1, INF));
        dist[n][n] = 0.0;
    }

    void add_constraint(const std::string &from, const std::string &to,
                        double lo, double hi) {
        add_point(from); add_point(to);
        size_t fi = idx.at(from), ti = idx.at(to);
        if (hi  < dist[fi][ti]) dist[fi][ti] = hi;
        if (-lo < dist[ti][fi]) dist[ti][fi] = -lo;
    }

    bool consistent() const {
        size_t n = points.size();
        if (n == 0) return true;
        std::vector<std::vector<double>> d = dist;
        for (size_t k = 0; k < n; ++k)
            for (size_t i = 0; i < n; ++i) {
                if (d[i][k] == INF) continue;
                for (size_t j = 0; j < n; ++j) {
                    if (d[k][j] == INF) continue;
                    double via = d[i][k] + d[k][j];
                    if (via < d[i][j]) d[i][j] = via;
                }
            }
        for (size_t i = 0; i < n; ++i)
            if (d[i][i] < 0.0) return false;
        return true;
    }
};
} // namespace tw_detail

// Per-step temporal annotation — all time values are ISO 8601 strings.
struct TwTemporalStep {
    std::string action_name;
    std::string duration_iso;   // ISO 8601 duration (e.g. "PT10M"), empty if none
    std::string start_iso;      // ISO 8601 duration from origin (e.g. "PT0S")
    std::string end_iso;        // ISO 8601 duration from origin (e.g. "PT10M")
};

// Result of temporal analysis on a plan — all time in ISO 8601.
struct TwTemporalResult {
    bool        consistent;    // STN consistency check passed
    std::string total_iso;     // total plan duration as ISO 8601 (e.g. "PT20M")
    std::string origin_iso;    // origin offset supplied by caller (default "PT0S")
    std::vector<TwTemporalStep> steps;
};

// Build a sequential STN from a plan and return temporal metadata.
// Sequential assumption: each action starts exactly when the previous ends.
// Actions with no duration entry are treated as PT0S.
// origin_iso: ISO 8601 duration string for the plan start offset (default "PT0S").
// All start_iso/end_iso values are durations measured from the same zero reference.
inline TwTemporalResult tw_check_temporal(
        const std::vector<TwCall> &plan,
        const TwDomain            &domain,
        const std::string         &origin_iso = "PT0S") {
    TwTemporalResult r;
    r.consistent = true;
    r.origin_iso = origin_iso;

    double origin_s = tw_parse_duration(origin_iso);
    if (origin_s < 0.0) origin_s = 0.0;

    if (plan.empty()) {
        r.total_iso = "PT0S";
        return r;
    }

    tw_detail::STN stn;
    stn.add_point("t0");
    std::string prev_end = "t0";
    double current_s     = origin_s;
    double total_s       = 0.0;

    for (size_t i = 0; i < plan.size(); ++i) {
        const std::string &name = plan[i].name;

        double dur_s = 0.0;
        std::string dur_iso;
        std::unordered_map<std::string, std::string>::const_iterator dit =
            domain.action_durations.find(name);
        if (dit != domain.action_durations.end()) {
            dur_iso = dit->second;
            double parsed = tw_parse_duration(dur_iso);
            if (parsed >= 0.0) dur_s = parsed;
        }

        TwTemporalStep step;
        step.action_name  = name;
        step.duration_iso = dur_iso.empty() ? "PT0S" : dur_iso;
        step.start_iso    = tw_format_duration(current_s);
        step.end_iso      = tw_format_duration(current_s + dur_s);
        r.steps.push_back(std::move(step));

        current_s += dur_s;
        total_s   += dur_s;

        std::string a_start = "a" + std::to_string(i) + "_start";
        std::string a_end   = "a" + std::to_string(i) + "_end";
        stn.add_constraint(prev_end, a_start, 0.0, 0.0);
        stn.add_constraint(a_start,  a_end,   dur_s, dur_s);
        prev_end = a_end;
    }

    r.consistent = stn.consistent();
    r.total_iso  = tw_format_duration(total_s);
    return r;
}
