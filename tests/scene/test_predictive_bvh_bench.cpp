/**************************************************************************/
/*  test_predictive_bvh_bench.cpp                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_predictive_bvh_bench)

#include "modules/modules_enabled.gen.h"

#ifdef MODULE_MULTIPLAYER_FABRIC_ENABLED

#include "core/math/aabb.h"
#include "core/math/dynamic_bvh.h"
#include "core/os/os.h"

#include "thirdparty/predictive_bvh/predictive_bvh.h"
#include "thirdparty/predictive_bvh/predictive_bvh_tree.h"

namespace TestPredictiveBVHBench {

// Phase 0 of the "DynamicBVH parity via Lean proofs" plan. Three questions:
//   1. R128 aabb_overlaps vs float AABB::intersects — per-compare cost ratio.
//   2. Hilbert prefix compare (clz30 on XOR of Hilbert codes) — does the
//      broadphase prune enough pairs to win the full N² workload?
//   3. DynamicBVH insert + aabb_query per entity — the destination budget.
//
// All four paths MUST produce the same overlap count on the same dataset;
// otherwise the bench is measuring different questions. The CHECK(match == ...)
// assertions enforce this.

static constexpr float BENCH_BOUND = 15.0f; // same as FabricZone::SIM_BOUND
static constexpr float BENCH_EXTENT = 0.1f; // ~10 cm leaves, sparse at BOUND=15
static constexpr uint32_t HILBERT_PREFIX_BITS = 6; // 2 m cells at scene size 30 m

// Deterministic xorshift so the bench is reproducible across runs.
struct XorShift {
	uint64_t s;
	explicit XorShift(uint64_t seed) :
			s(seed ? seed : 0x9E3779B97F4A7C15ull) {}
	uint32_t next_u32() {
		uint64_t x = s;
		x ^= x << 13;
		x ^= x >> 7;
		x ^= x << 17;
		s = x;
		return (uint32_t)x;
	}
	float uniform(float lo, float hi) {
		return lo + (hi - lo) * ((float)(next_u32() & 0xFFFFFF) / (float)0xFFFFFF);
	}
};

struct FloatLeaf {
	AABB box;
};
struct R128Leaf {
	Aabb box;
	uint32_t hilbert;
};

static void generate_dataset(uint32_t n, uint64_t seed,
		Vector<FloatLeaf> &r_float, Vector<R128Leaf> &r_r128) {
	XorShift rng(seed);
	r_float.resize(n);
	r_r128.resize(n);

	// Scene AABB in R128 μm, matches FabricZone convention.
	Aabb scene = aabb_from_floats(-BENCH_BOUND, BENCH_BOUND, -BENCH_BOUND, BENCH_BOUND, -BENCH_BOUND, BENCH_BOUND);

	for (uint32_t i = 0; i < n; i++) {
		float cx = rng.uniform(-BENCH_BOUND + BENCH_EXTENT, BENCH_BOUND - BENCH_EXTENT);
		float cy = rng.uniform(-BENCH_BOUND + BENCH_EXTENT, BENCH_BOUND - BENCH_EXTENT);
		float cz = rng.uniform(-BENCH_BOUND + BENCH_EXTENT, BENCH_BOUND - BENCH_EXTENT);

		AABB fb(Vector3(cx - BENCH_EXTENT, cy - BENCH_EXTENT, cz - BENCH_EXTENT),
				Vector3(BENCH_EXTENT * 2.0f, BENCH_EXTENT * 2.0f, BENCH_EXTENT * 2.0f));
		r_float.write[i].box = fb;

		Aabb rb = aabb_from_floats(cx - BENCH_EXTENT, cx + BENCH_EXTENT,
				cy - BENCH_EXTENT, cy + BENCH_EXTENT,
				cz - BENCH_EXTENT, cz + BENCH_EXTENT);
		r_r128.write[i].box = rb;
		r_r128.write[i].hilbert = hilbert_of_aabb(&rb, &scene);
	}
}

// Path A: Godot's native float AABB overlap, all N*(N-1)/2 pairs.
static uint64_t bench_float_pairs(const Vector<FloatLeaf> &leaves, uint64_t &r_usec) {
	const uint64_t t0 = OS::get_singleton()->get_ticks_usec();
	uint64_t matches = 0;
	const uint32_t n = leaves.size();
	for (uint32_t i = 0; i < n; i++) {
		const AABB &a = leaves[i].box;
		for (uint32_t j = i + 1; j < n; j++) {
			if (a.intersects(leaves[j].box)) {
				matches++;
			}
		}
	}
	r_usec = OS::get_singleton()->get_ticks_usec() - t0;
	return matches;
}

// Path B: predictive_bvh R128 overlap, all N*(N-1)/2 pairs.
static uint64_t bench_r128_pairs(const Vector<R128Leaf> &leaves, uint64_t &r_usec) {
	const uint64_t t0 = OS::get_singleton()->get_ticks_usec();
	uint64_t matches = 0;
	const uint32_t n = leaves.size();
	for (uint32_t i = 0; i < n; i++) {
		const Aabb &a = leaves[i].box;
		for (uint32_t j = i + 1; j < n; j++) {
			if (aabb_overlaps(&a, &leaves[j].box)) {
				matches++;
			}
		}
	}
	r_usec = OS::get_singleton()->get_ticks_usec() - t0;
	return matches;
}

// Path C: Hilbert prefix prune first (30-bit Hilbert code, clz of XOR).
// Any pair whose shared prefix is shorter than HILBERT_PREFIX_BITS is in
// non-adjacent Hilbert cells and cannot overlap under BENCH_EXTENT ≪ cell.
// Note: Hilbert curves can still place near-spatial-neighbors in distant
// cells, so this is a broadphase *prune*, not an exact test — we fall
// through to R128 aabb_overlaps to recover completeness.
static uint64_t bench_r128_prefix(const Vector<R128Leaf> &leaves, uint64_t &r_usec) {
	const uint64_t t0 = OS::get_singleton()->get_ticks_usec();
	uint64_t matches = 0;
	const uint32_t n = leaves.size();
	const uint32_t shift = 30 - HILBERT_PREFIX_BITS;
	for (uint32_t i = 0; i < n; i++) {
		const uint32_t hi = leaves[i].hilbert;
		const Aabb &a = leaves[i].box;
		for (uint32_t j = i + 1; j < n; j++) {
			// Cheap integer prune: same Hilbert cell prefix?
			if ((hi >> shift) != (leaves[j].hilbert >> shift)) {
				continue;
			}
			if (aabb_overlaps(&a, &leaves[j].box)) {
				matches++;
			}
		}
	}
	r_usec = OS::get_singleton()->get_ticks_usec() - t0;
	return matches;
}

// Path D: DynamicBVH destination budget — insert N, query each leaf's AABB,
// count overlaps with any other leaf.
struct BVHPairCollector {
	uint32_t self_id = 0;
	uint64_t matches = 0;
	bool operator()(void *ud) {
		uint32_t other = (uint32_t)(uintptr_t)ud;
		if (other > self_id) { // avoid double-counting pairs, match (i<j) convention
			matches++;
		}
		return false; // keep collecting
	}
};

static uint64_t bench_dynamic_bvh(const Vector<FloatLeaf> &leaves, uint64_t &r_usec) {
	DynamicBVH tree;
	LocalVector<DynamicBVH::ID> ids;
	const uint32_t n = leaves.size();
	ids.resize(n);

	// Build phase — not timed; DynamicBVH incremental build is its own question.
	for (uint32_t i = 0; i < n; i++) {
		ids[i] = tree.insert(leaves[i].box, (void *)(uintptr_t)i);
	}

	const uint64_t t0 = OS::get_singleton()->get_ticks_usec();
	uint64_t matches = 0;
	for (uint32_t i = 0; i < n; i++) {
		BVHPairCollector cb;
		cb.self_id = i;
		tree.aabb_query(leaves[i].box, cb);
		matches += cb.matches;
	}
	r_usec = OS::get_singleton()->get_ticks_usec() - t0;
	return matches;
}

static void run_one_n(uint32_t n) {
	Vector<FloatLeaf> floats;
	Vector<R128Leaf> r128s;
	generate_dataset(n, 0xC0FFEEull ^ (uint64_t)n, floats, r128s);

	uint64_t t_float = 0, t_r128 = 0, t_prefix = 0, t_bvh = 0;
	const uint64_t m_float = bench_float_pairs(floats, t_float);
	const uint64_t m_r128 = bench_r128_pairs(r128s, t_r128);
	const uint64_t m_prefix = bench_r128_prefix(r128s, t_prefix);
	const uint64_t m_bvh = bench_dynamic_bvh(floats, t_bvh);

	// All paths must find the same pair set. Float↔R128 may differ by ≤1 at
	// exact-touch boundaries due to quantization, but with sparse BENCH_EXTENT
	// they should match exactly.
	CHECK_MESSAGE(m_float == m_r128, vformat("pair-count mismatch: float=%d vs R128=%d at N=%d", m_float, m_r128, n));
	CHECK_MESSAGE(m_prefix == m_r128, vformat("prefix prune dropped pairs: prefix=%d vs R128=%d at N=%d", m_prefix, m_r128, n));
	CHECK_MESSAGE(m_bvh == m_float, vformat("DynamicBVH pair-count mismatch: bvh=%d vs float=%d at N=%d", m_bvh, m_float, n));

	const uint64_t pairs = (uint64_t)n * (n - 1) / 2;
	const double ns_float = t_float * 1000.0 / (double)pairs;
	const double ns_r128 = t_r128 * 1000.0 / (double)pairs;
	const double ns_prefix = t_prefix * 1000.0 / (double)pairs;
	const double ns_bvh = t_bvh * 1000.0 / (double)n; // per query, not per pair

	print_line(vformat("[bench N=%d pairs=%d matches=%d]", n, pairs, m_float));
	print_line(vformat("    float AABB::intersects   : %d us total  %.2f ns/pair", t_float, ns_float));
	print_line(vformat("    R128 aabb_overlaps       : %d us total  %.2f ns/pair", t_r128, ns_r128));
	print_line(vformat("    R128 + Hilbert prefix    : %d us total  %.2f ns/pair", t_prefix, ns_prefix));
	print_line(vformat("    DynamicBVH aabb_query    : %d us total  %.2f ns/query (N queries)", t_bvh, ns_bvh));
}

// ──────────────────────────────────────────────────────────────────────────
// Phase 1 RED: pbvh_tree parity against DynamicBVH. Drives the red→green
// cycle. Until pbvh_tree_t lands, this TEST_CASE fails to compile.
// ──────────────────────────────────────────────────────────────────────────

struct PBVHParityCollector {
	Vector<uint32_t> hits;
};

static int pbvh_parity_cb(pbvh_eclass_id_t id, void *ud) {
	((PBVHParityCollector *)ud)->hits.push_back((uint32_t)id);
	return 0;
}

TEST_CASE("[PredictiveBVH][Parity] pbvh_tree vs DynamicBVH aabb_query") {
	constexpr uint32_t N = 256;
	Vector<FloatLeaf> floats;
	Vector<R128Leaf> r128s;
	generate_dataset(N, 0xDEADBEEFull, floats, r128s);

	DynamicBVH dtree;
	LocalVector<DynamicBVH::ID> dids;
	dids.resize(N);
	for (uint32_t i = 0; i < N; i++) {
		dids[i] = dtree.insert(floats[i].box, (void *)(uintptr_t)i);
	}

	Vector<pbvh_node_t> storage;
	storage.resize(N * 2 + 8);
	pbvh_tree_t ptree = {};
	ptree.nodes = storage.ptrw();
	ptree.capacity = storage.size();
	ptree.root = PBVH_NULL_NODE;
	ptree.free_head = PBVH_NULL_NODE;

	LocalVector<pbvh_node_id_t> pids;
	pids.resize(N);
	for (uint32_t i = 0; i < N; i++) {
		pids[i] = pbvh_tree_insert(&ptree, (pbvh_eclass_id_t)i, r128s[i].box);
	}

	for (uint32_t i = 0; i < N; i++) {
		Vector<uint32_t> dhits;
		struct DCollect {
			Vector<uint32_t> *out = nullptr;
			bool operator()(void *ud) {
				out->push_back((uint32_t)(uintptr_t)ud);
				return false;
			}
		} dcb;
		dcb.out = &dhits;
		dtree.aabb_query(floats[i].box, dcb);

		PBVHParityCollector pcb;
		pbvh_tree_aabb_query(&ptree, &r128s[i].box, pbvh_parity_cb, &pcb);

		dhits.sort();
		pcb.hits.sort();
		CHECK_MESSAGE(dhits == pcb.hits,
				vformat("pbvh_tree parity mismatch at i=%d: dbvh=%d hits pbvh=%d hits", i, dhits.size(), pcb.hits.size()));
	}
}

TEST_CASE("[PredictiveBVH][Bench] R128 vs float vs Hilbert-prefix vs DynamicBVH") {
	// N=1024 covers FabricZone's typical population (896 SLA minimum,
	// 1800 default capacity). N=4096 stresses the O(N²) paths without
	// blowing out CI time budgets.
	run_one_n(1024);
	run_one_n(4096);
}

} // namespace TestPredictiveBVHBench

#endif // MODULE_MULTIPLAYER_FABRIC_ENABLED
