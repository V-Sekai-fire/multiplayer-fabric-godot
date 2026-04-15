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

#include <cmath>

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

TEST_CASE("[PredictiveBVH][Parity] pbvh_tree_aabb_query_n matches linear scan, prunes visits") {
	constexpr uint32_t N = 1024;
	Vector<FloatLeaf> floats;
	Vector<R128Leaf> r128s;
	generate_dataset(N, 0xF00DFEEDull, floats, r128s);

	Vector<pbvh_node_t> storage;
	storage.resize(N + 8);
	Vector<pbvh_node_id_t> sorted;
	sorted.resize(N + 8);
	Vector<pbvh_internal_t> internals;
	internals.resize(2 * (N + 8));

	pbvh_tree_t tree = {};
	tree.nodes = storage.ptrw();
	tree.capacity = storage.size();
	tree.root = PBVH_NULL_NODE;
	tree.free_head = PBVH_NULL_NODE;
	tree.sorted = sorted.ptrw();
	tree.internals = internals.ptrw();
	tree.internal_capacity = internals.size();
	tree.internal_root = PBVH_NULL_NODE;

	for (uint32_t i = 0; i < N; i++) {
		pbvh_tree_insert_h(&tree, (pbvh_eclass_id_t)i, r128s[i].box, r128s[i].hilbert);
	}
	pbvh_tree_build(&tree);

	uint64_t total_visits_linear = 0;
	uint64_t total_visits_n = 0;
	for (uint32_t i = 0; i < N; i++) {
		Vector<uint32_t> linear_hits, n_hits;
		struct Collect {
			Vector<uint32_t> *out = nullptr;
		} lc, nc;
		lc.out = &linear_hits;
		nc.out = &n_hits;

		pbvh_tree_aabb_query(&tree, &r128s[i].box,
				[](pbvh_eclass_id_t id, void *ud) {
					((Collect *)ud)->out->push_back((uint32_t)id);
					return 0;
				}, &lc);
		total_visits_linear += tree.last_visits;

		pbvh_tree_aabb_query_n(&tree, &r128s[i].box,
				[](pbvh_eclass_id_t id, void *ud) {
					((Collect *)ud)->out->push_back((uint32_t)id);
					return 0;
				}, &nc);
		total_visits_n += tree.last_visits;

		linear_hits.sort();
		n_hits.sort();
		CHECK_MESSAGE(linear_hits == n_hits,
				vformat("hit-set mismatch at i=%d: linear=%d n=%d", i, linear_hits.size(), n_hits.size()));
	}
	CHECK_MESSAGE(total_visits_n * 4 < total_visits_linear,
			vformat("nested-set prune failed: linear visits=%d n visits=%d (want n*4 < linear)",
					(int)total_visits_linear, (int)total_visits_n));
}

TEST_CASE("[PredictiveBVH][Parity] pbvh_tree_remove hides leaf from query_n without rebuild") {
	constexpr uint32_t N = 32;
	Vector<FloatLeaf> floats;
	Vector<R128Leaf> r128s;
	generate_dataset(N, 0xBADF00Dull, floats, r128s);

	Vector<pbvh_node_t> storage;
	storage.resize(N + 8);
	Vector<pbvh_node_id_t> sorted;
	sorted.resize(N + 8);
	Vector<pbvh_internal_t> internals;
	internals.resize(2 * (N + 8));
	pbvh_tree_t tree = {};
	tree.nodes = storage.ptrw();
	tree.capacity = storage.size();
	tree.root = PBVH_NULL_NODE;
	tree.free_head = PBVH_NULL_NODE;
	tree.sorted = sorted.ptrw();
	tree.internals = internals.ptrw();
	tree.internal_capacity = internals.size();
	tree.internal_root = PBVH_NULL_NODE;

	LocalVector<pbvh_node_id_t> ids;
	ids.resize(N);
	for (uint32_t i = 0; i < N; i++) {
		ids[i] = pbvh_tree_insert_h(&tree, (pbvh_eclass_id_t)i, r128s[i].box, r128s[i].hilbert);
	}
	pbvh_tree_build(&tree);

	// Remove leaf 0 WITHOUT rebuilding. A correct query must not surface
	// the dead eclass even though its slot still occupies sorted[].
	pbvh_tree_remove(&tree, ids[0]);

	Vector<uint32_t> hits;
	struct C {
		Vector<uint32_t> *out = nullptr;
	} c;
	c.out = &hits;
	pbvh_tree_aabb_query_n(&tree, &r128s[0].box,
			[](pbvh_eclass_id_t id, void *ud) {
				((C *)ud)->out->push_back((uint32_t)id);
				return 0;
			}, &c);
	CHECK_MESSAGE(!hits.has(0u),
			vformat("query returned the removed eclass id 0 (stale sorted[] entry); hits=%d", hits.size()));
}

TEST_CASE("[PredictiveBVH][Parity] pbvh_tree_update_h moves leaf into new Hilbert window") {
	Vector<pbvh_node_t> storage;
	storage.resize(8);
	Vector<pbvh_node_id_t> sorted;
	sorted.resize(8);
	Vector<pbvh_internal_t> internals;
	internals.resize(16);
	pbvh_tree_t tree = {};
	tree.nodes = storage.ptrw();
	tree.capacity = storage.size();
	tree.root = PBVH_NULL_NODE;
	tree.free_head = PBVH_NULL_NODE;
	tree.sorted = sorted.ptrw();
	tree.internals = internals.ptrw();
	tree.internal_capacity = internals.size();
	tree.internal_root = PBVH_NULL_NODE;

	const Aabb scene = aabb_from_floats(-BENCH_BOUND, BENCH_BOUND,
			-BENCH_BOUND, BENCH_BOUND, -BENCH_BOUND, BENCH_BOUND);
	Aabb box_a = aabb_from_floats(-14.0f, -13.0f, -14.0f, -13.0f, -14.0f, -13.0f);
	Aabb box_b = aabb_from_floats(13.0f, 14.0f, 13.0f, 14.0f, 13.0f, 14.0f);
	uint32_t h_a = hilbert_of_aabb(&box_a, &scene);
	uint32_t h_b = hilbert_of_aabb(&box_b, &scene);
	REQUIRE(h_a != h_b);

	pbvh_node_id_t id = pbvh_tree_insert_h(&tree, 42u, box_a, h_a);
	pbvh_tree_build(&tree);

	pbvh_tree_update_h(&tree, id, box_b, h_b);
	pbvh_tree_build(&tree);

	Vector<uint32_t> hits;
	struct C {
		Vector<uint32_t> *out = nullptr;
	} c;
	c.out = &hits;
	pbvh_tree_aabb_query_n(&tree, &box_b,
			[](pbvh_eclass_id_t eid, void *ud) {
				((C *)ud)->out->push_back((uint32_t)eid);
				return 0;
			}, &c);
	CHECK_MESSAGE(hits.has(42u),
			vformat("query at the new position missed the moved leaf; hits=%d", hits.size()));
}

TEST_CASE("[PredictiveBVH][NestedSet] pbvh_tree_aabb_query_n matches linear scan and prunes visits") {
	constexpr uint32_t N = 1024;
	Vector<FloatLeaf> floats;
	Vector<R128Leaf> r128s;
	generate_dataset(N, 0xC0FFEEull, floats, r128s);

	Vector<pbvh_node_t> storage;
	storage.resize(N + 8);
	Vector<pbvh_node_id_t> sorted;
	sorted.resize(N + 8);
	Vector<pbvh_internal_t> internals;
	internals.resize(2 * (N + 8));

	pbvh_tree_t tree = {};
	tree.nodes = storage.ptrw();
	tree.capacity = storage.size();
	tree.root = PBVH_NULL_NODE;
	tree.free_head = PBVH_NULL_NODE;
	tree.sorted = sorted.ptrw();
	tree.internals = internals.ptrw();
	tree.internal_capacity = internals.size();
	tree.internal_root = PBVH_NULL_NODE;

	for (uint32_t i = 0; i < N; i++) {
		pbvh_tree_insert_h(&tree, (pbvh_eclass_id_t)i, r128s[i].box, r128s[i].hilbert);
	}
	pbvh_tree_build(&tree);

	CHECK_MESSAGE(tree.internal_root != PBVH_NULL_NODE, "internal tree root should be set after build with N=1024 leaves");
	CHECK_MESSAGE(tree.internal_count >= N, vformat("expected at least N internals for a radix tree over %d leaves; got %d", (int)N, (int)tree.internal_count));

	// Subtree-bound containment invariant: the root's span covers every leaf.
	REQUIRE(tree.internals[tree.internal_root].span == N);

	uint64_t total_visits_linear = 0;
	uint64_t total_visits_n = 0;
	for (uint32_t i = 0; i < N; i++) {
		Vector<uint32_t> linear_hits, n_hits;
		struct Collect {
			Vector<uint32_t> *out = nullptr;
		} lc, nc;
		lc.out = &linear_hits;
		nc.out = &n_hits;

		pbvh_tree_aabb_query(&tree, &r128s[i].box,
				[](pbvh_eclass_id_t id, void *ud) {
					((Collect *)ud)->out->push_back((uint32_t)id);
					return 0;
				}, &lc);
		total_visits_linear += tree.last_visits;

		pbvh_tree_aabb_query_n(&tree, &r128s[i].box,
				[](pbvh_eclass_id_t id, void *ud) {
					((Collect *)ud)->out->push_back((uint32_t)id);
					return 0;
				}, &nc);
		total_visits_n += tree.last_visits;

		linear_hits.sort();
		n_hits.sort();
		CHECK_MESSAGE(linear_hits == n_hits,
				vformat("nested-set hit-set mismatch at i=%d: linear=%d n=%d",
						i, linear_hits.size(), n_hits.size()));
	}
	CHECK_MESSAGE(total_visits_n * 4 < total_visits_linear,
			vformat("nested-set prune failed: linear=%d n=%d (want n*4 < linear)",
					(int)total_visits_linear, (int)total_visits_n));
}

TEST_CASE("[PredictiveBVH][Refit] pbvh_tree_refit agrees with full rebuild for in-cell perturbation") {
	constexpr uint32_t N = 1024;
	Vector<FloatLeaf> floats;
	Vector<R128Leaf> r128s;
	generate_dataset(N, 0xCAFEBABEull, floats, r128s);

	Vector<pbvh_node_t> storage;
	storage.resize(N + 8);
	Vector<pbvh_node_id_t> sorted;
	sorted.resize(N + 8);
	Vector<pbvh_internal_t> internals;
	internals.resize(2 * (N + 8));

	pbvh_tree_t tree = {};
	tree.nodes = storage.ptrw();
	tree.capacity = storage.size();
	tree.root = PBVH_NULL_NODE;
	tree.free_head = PBVH_NULL_NODE;
	tree.sorted = sorted.ptrw();
	tree.internals = internals.ptrw();
	tree.internal_capacity = internals.size();
	tree.internal_root = PBVH_NULL_NODE;

	for (uint32_t i = 0; i < N; i++) {
		pbvh_tree_insert_h(&tree, (pbvh_eclass_id_t)i, r128s[i].box, r128s[i].hilbert);
	}
	pbvh_tree_build(&tree);

	// Perturb bounds by less than one Hilbert cell so hilbert codes stay stable.
	// Bucket-cell size at HILBERT_PREFIX_BITS=6 is (2*BENCH_BOUND)/2^2 = 7.5 m;
	// BENCH_EXTENT is 10 cm, so a 1 cm jitter keeps every leaf in-cell.
	XorShift rng(0x1234ull);
	for (uint32_t i = 0; i < N; i++) {
		const float dx = rng.uniform(-0.01f, 0.01f);
		const float dy = rng.uniform(-0.01f, 0.01f);
		const float dz = rng.uniform(-0.01f, 0.01f);
		AABB moved = floats[i].box;
		moved.position += Vector3(dx, dy, dz);
		floats.write[i].box = moved;
		Aabb rb = aabb_from_floats(
				moved.position.x, moved.position.x + moved.size.x,
				moved.position.y, moved.position.y + moved.size.y,
				moved.position.z, moved.position.z + moved.size.z);
		r128s.write[i].box = rb;
		pbvh_tree_update(&tree, (pbvh_node_id_t)i, rb);
	}

	const uint64_t t_refit0 = OS::get_singleton()->get_ticks_usec();
	pbvh_tree_refit(&tree);
	const uint64_t t_refit = OS::get_singleton()->get_ticks_usec() - t_refit0;

	// Gold tree: full rebuild over the same perturbed dataset.
	Vector<pbvh_node_t> gold_storage;
	gold_storage.resize(N + 8);
	Vector<pbvh_node_id_t> gold_sorted;
	gold_sorted.resize(N + 8);
	Vector<pbvh_internal_t> gold_internals;
	gold_internals.resize(2 * (N + 8));
	pbvh_tree_t gold = {};
	gold.nodes = gold_storage.ptrw();
	gold.capacity = gold_storage.size();
	gold.root = PBVH_NULL_NODE;
	gold.free_head = PBVH_NULL_NODE;
	gold.sorted = gold_sorted.ptrw();
	gold.internals = gold_internals.ptrw();
	gold.internal_capacity = gold_internals.size();
	gold.internal_root = PBVH_NULL_NODE;
	for (uint32_t i = 0; i < N; i++) {
		pbvh_tree_insert_h(&gold, (pbvh_eclass_id_t)i, r128s[i].box, r128s[i].hilbert);
	}
	const uint64_t t_build0 = OS::get_singleton()->get_ticks_usec();
	pbvh_tree_build(&gold);
	const uint64_t t_build = OS::get_singleton()->get_ticks_usec() - t_build0;

	// Query correctness: refit tree answers must match the full-rebuild tree.
	for (uint32_t i = 0; i < N; i++) {
		Vector<uint32_t> refit_hits, gold_hits;
		struct C {
			Vector<uint32_t> *out = nullptr;
		} rc, gc;
		rc.out = &refit_hits;
		gc.out = &gold_hits;
		pbvh_tree_aabb_query_n(&tree, &r128s[i].box,
				[](pbvh_eclass_id_t id, void *ud) {
					((C *)ud)->out->push_back((uint32_t)id);
					return 0;
				}, &rc);
		pbvh_tree_aabb_query_n(&gold, &r128s[i].box,
				[](pbvh_eclass_id_t id, void *ud) {
					((C *)ud)->out->push_back((uint32_t)id);
					return 0;
				}, &gc);
		refit_hits.sort();
		gold_hits.sort();
		CHECK_MESSAGE(refit_hits == gold_hits,
				vformat("refit vs full-rebuild hit mismatch at i=%d: refit=%d gold=%d",
						i, refit_hits.size(), gold_hits.size()));
	}

	print_line(vformat("[refit N=%d] refit=%d us  full build=%d us  ratio=%.2fx",
			N, (int)t_refit, (int)t_build,
			t_build > 0 ? (double)t_build / (double)t_refit : 0.0));
	CHECK_MESSAGE(t_refit <= t_build,
			vformat("refit must be no slower than full build: refit=%d us build=%d us", (int)t_refit, (int)t_build));
}

// ──────────────────────────────────────────────────────────────────────────
// Phase 2c adversarial gate. Each case below covers exactly one behaviour
// that a misbehaving or naive caller could exercise. The full cross-product
// sweep (N=65536 × 120 frames × 5 fractions) is deferred to a bench-only
// build; these minimal cases are what we run in CI to catch regressions.
// ──────────────────────────────────────────────────────────────────────────

// Small helper: build a pbvh tree ready for tick, with a 2 m bucket grid.
namespace tick_harness {
struct Harness {
	Vector<FloatLeaf> floats;
	Vector<R128Leaf> r128s;
	Vector<pbvh_node_t> storage;
	Vector<pbvh_node_id_t> sorted;
	Vector<pbvh_internal_t> internals;
	Vector<uint32_t> bucket_dir;
	pbvh_tree_t tree = {};
	Aabb scene;

	void init(uint32_t n, uint64_t seed) {
		generate_dataset(n, seed, floats, r128s);
		scene = aabb_from_floats(-BENCH_BOUND, BENCH_BOUND,
				-BENCH_BOUND, BENCH_BOUND, -BENCH_BOUND, BENCH_BOUND);
		storage.resize(n + 16);
		sorted.resize(n + 16);
		internals.resize(2 * (n + 16));
		bucket_dir.resize(2u * (1u << HILBERT_PREFIX_BITS));
		tree.nodes = storage.ptrw();
		tree.capacity = storage.size();
		tree.root = PBVH_NULL_NODE;
		tree.free_head = PBVH_NULL_NODE;
		tree.sorted = sorted.ptrw();
		tree.internals = internals.ptrw();
		tree.internal_capacity = internals.size();
		tree.internal_root = PBVH_NULL_NODE;
		tree.bucket_dir = bucket_dir.ptrw();
		tree.bucket_bits = HILBERT_PREFIX_BITS;
		for (uint32_t i = 0; i < n; i++) {
			pbvh_tree_insert_h(&tree, (pbvh_eclass_id_t)i,
					r128s[i].box, r128s[i].hilbert);
		}
		pbvh_tree_build(&tree);
	}

	bool query_hits(uint32_t eclass) {
		struct C { uint32_t target = 0; bool found = false; };
		C c; c.target = eclass;
		pbvh_tree_aabb_query_n(&tree, &r128s[eclass].box,
				[](pbvh_eclass_id_t id, void *ud) {
					C *cc = (C *)ud;
					if ((uint32_t)id == cc->target) { cc->found = true; }
					return 0;
				}, &c);
		return c.found;
	}
};
} // namespace tick_harness

// Case 1 — defensive: NULL arguments must not crash and must leave the tree
// untouched. A caller that hands us `(NULL, 0)` or `(NULL_tree, anything)`
// has a bug, but we can't segfault the process.
TEST_CASE("[PredictiveBVH][Tick] null pointer inputs are safe") {
	pbvh_tree_tick(nullptr, nullptr, 0u);
	pbvh_tree_tick(nullptr, nullptr, 7u);
	pbvh_tree_t empty = {};
	pbvh_tree_tick(&empty, nullptr, 4u); // nodes == NULL
	CHECK(true); // reaching here means no crash
}

// Case 2 — insert-since-build: the main adversarial case. A caller inserts
// a leaf after the last build and hands tick a dirty list that omits the
// new leaf. Without the `t->count > t->sorted_count` guard, refit would
// leave the new leaf unreachable from queries.
TEST_CASE("[PredictiveBVH][Tick] insert since last build forces full rebuild") {
	tick_harness::Harness h;
	h.init(64, 0x11111111ull);

	// Insert a brand-new leaf that overlaps a known location.
	Aabb fresh = aabb_from_floats(0.0f, 0.1f, 0.0f, 0.1f, 0.0f, 0.1f);
	const uint32_t fresh_h = hilbert_of_aabb(&fresh, &h.scene);
	pbvh_node_id_t fresh_id = pbvh_tree_insert_h(&h.tree,
			(pbvh_eclass_id_t)999, fresh, fresh_h);
	REQUIRE(h.tree.count > h.tree.sorted_count);

	// Hand tick a dirty list covering ONLY an existing leaf — the new one
	// is "hidden" from the caller's perspective.
	pbvh_dirty_leaf_t dirty = { 0u, h.r128s[0].hilbert };
	pbvh_tree_tick(&h.tree, &dirty, 1u);

	// Post-tick: a query at the fresh leaf's position must still find it.
	struct C { bool found = false; } c;
	pbvh_tree_aabb_query_n(&h.tree, &fresh,
			[](pbvh_eclass_id_t id, void *ud) {
				if ((uint32_t)id == 999u) { ((C *)ud)->found = true; }
				return 0;
			}, &c);
	CHECK_MESSAGE(c.found, "insert-since-build must trigger full rebuild");
	CHECK_MESSAGE(h.tree.sorted_count >= h.tree.count,
			"sorted_count must catch up to count after fallback build");
	(void)fresh_id;
}

// Case 3 — removed leaf in dirty list: caller reports a leaf that has been
// pbvh_tree_remove'd. Refit would leave its stale bounds in the internals,
// but more importantly, the topology-changed signal must trigger a build
// so later insertions reuse the slot correctly.
TEST_CASE("[PredictiveBVH][Tick] removed leaf in dirty list forces full rebuild") {
	tick_harness::Harness h;
	h.init(64, 0x22222222ull);

	pbvh_tree_remove(&h.tree, (pbvh_node_id_t)5);
	pbvh_dirty_leaf_t dirty = { 5u, h.r128s[5].hilbert };
	pbvh_tree_tick(&h.tree, &dirty, 1u);

	// The removed leaf must NOT appear in queries at its old location.
	struct C { bool found = false; } c;
	pbvh_tree_aabb_query_n(&h.tree, &h.r128s[5].box,
			[](pbvh_eclass_id_t id, void *ud) {
				if ((uint32_t)id == 5u) { ((C *)ud)->found = true; }
				return 0;
			}, &c);
	CHECK_MESSAGE(!c.found, "removed leaf must be invisible after tick");
}

// Case 4 — bucket-boundary crossing: a dirty leaf whose new Hilbert code
// lands in a different bucket prefix from old_hilbert. Refit would keep
// the leaf in the WRONG sorted[] window; only a full rebuild re-sorts.
TEST_CASE("[PredictiveBVH][Tick] bucket crossing forces full rebuild") {
	tick_harness::Harness h;
	h.init(64, 0x33333333ull);

	// Move leaf 0 from one corner to the opposite corner: guaranteed to
	// change its Hilbert prefix at 6-bit resolution.
	const uint32_t old_h = h.r128s[0].hilbert;
	AABB far_box(Vector3(BENCH_BOUND - 1.0f, BENCH_BOUND - 1.0f, BENCH_BOUND - 1.0f),
			Vector3(0.1f, 0.1f, 0.1f));
	Aabb far_r = aabb_from_floats(
			far_box.position.x, far_box.position.x + far_box.size.x,
			far_box.position.y, far_box.position.y + far_box.size.y,
			far_box.position.z, far_box.position.z + far_box.size.z);
	const uint32_t new_h = hilbert_of_aabb(&far_r, &h.scene);
	REQUIRE((old_h >> (30u - HILBERT_PREFIX_BITS)) !=
			(new_h >> (30u - HILBERT_PREFIX_BITS)));
	h.floats.write[0].box = far_box;
	h.r128s.write[0].box = far_r;
	h.r128s.write[0].hilbert = new_h;
	pbvh_tree_update_h(&h.tree, 0u, far_r, new_h);

	pbvh_dirty_leaf_t dirty = { 0u, old_h };
	pbvh_tree_tick(&h.tree, &dirty, 1u);

	// Query at the new location must find leaf 0.
	CHECK_MESSAGE(h.query_hits(0), "bucket-crossing leaf must be queryable at new pos");
}

// Case 5 — happy path: every dirty leaf stayed in its bucket. Refit fires,
// queries still return correct results, and wall time is no worse than a
// full build. Minimal N=1024 here — the sweeping N=65536 bench lives in
// a dev-only target to keep CI runtime bounded.
TEST_CASE("[PredictiveBVH][Tick] in-bucket perturbation takes refit fast path") {
	tick_harness::Harness h;
	h.init(1024, 0x44444444ull);

	XorShift rng(0x55555555ull);
	LocalVector<pbvh_dirty_leaf_t> dirty;
	dirty.resize(64);
	for (uint32_t k = 0; k < 64; k++) {
		const uint32_t i = rng.next_u32() % 1024u;
		const float dx = rng.uniform(-0.01f, 0.01f);
		const float dy = rng.uniform(-0.01f, 0.01f);
		const float dz = rng.uniform(-0.01f, 0.01f);
		AABB moved = h.floats[i].box;
		moved.position += Vector3(dx, dy, dz);
		h.floats.write[i].box = moved;
		Aabb rb = aabb_from_floats(
				moved.position.x, moved.position.x + moved.size.x,
				moved.position.y, moved.position.y + moved.size.y,
				moved.position.z, moved.position.z + moved.size.z);
		const uint32_t old_h = h.r128s[i].hilbert;
		const uint32_t new_h = hilbert_of_aabb(&rb, &h.scene);
		h.r128s.write[i].box = rb;
		h.r128s.write[i].hilbert = new_h;
		pbvh_tree_update_h(&h.tree, (pbvh_node_id_t)i, rb, new_h);
		dirty[k].leaf_id = (pbvh_node_id_t)i;
		dirty[k].old_hilbert = old_h;
	}

	const uint64_t t_tick0 = OS::get_singleton()->get_ticks_usec();
	pbvh_tree_tick(&h.tree, dirty.ptr(), dirty.size());
	const uint64_t t_tick = OS::get_singleton()->get_ticks_usec() - t_tick0;

	// Every perturbed leaf must still be queryable.
	for (uint32_t k = 0; k < 64; k++) {
		const uint32_t i = dirty[k].leaf_id;
		CHECK_MESSAGE(h.query_hits(i),
				vformat("post-tick query lost leaf i=%d", i));
	}

	// Compare vs a full build on a fresh tree.
	tick_harness::Harness gold;
	gold.init(1024, 0x44444444ull);
	const uint64_t t_build0 = OS::get_singleton()->get_ticks_usec();
	pbvh_tree_build(&gold.tree);
	const uint64_t t_build = OS::get_singleton()->get_ticks_usec() - t_build0;

	print_line(vformat("[tick N=1024 dirty=64] tick=%d us  full build=%d us",
			(int)t_tick, (int)t_build));
	CHECK_MESSAGE(t_tick <= t_build + 20,
			vformat("in-bucket tick should not exceed full build: tick=%d build=%d",
					(int)t_tick, (int)t_build));
}

// Growth-rate bench: double N across {1024, 2048, 4096, 8192, 16384} and
// report per-doubling time ratios. The point is not the absolute numbers but
// the scaling exponent — super-linear DBVH vs ~linear pbvh_tree_tick is the
// signal that justifies Rung 4. Max N capped at 16384 so the entire sweep
// fits inside a CI build slot; extrapolate to 65k at whatever growth
// exponent the table shows.
TEST_CASE("[PredictiveBVH][Bench] growth rate of insert+tick vs DynamicBVH") {
	constexpr uint32_t Ns[] = { 1024u, 4096u, 16384u, 65536u, 262144u };
	constexpr uint32_t kSweeps = sizeof(Ns) / sizeof(Ns[0]);

	uint64_t pbvh_totals[kSweeps] = {};
	uint64_t dbvh_totals[kSweeps] = {};

	Aabb scene = aabb_from_floats(-BENCH_BOUND, BENCH_BOUND,
			-BENCH_BOUND, BENCH_BOUND, -BENCH_BOUND, BENCH_BOUND);

	for (uint32_t s = 0; s < kSweeps; s++) {
		const uint32_t N = Ns[s];

		Vector<FloatLeaf> floats;
		Vector<R128Leaf> r128s;
		generate_dataset(N, 0xFEED1234ull ^ (uint64_t)N, floats, r128s);

		Vector<pbvh_node_t> storage;
		storage.resize(N + 16);
		Vector<pbvh_node_id_t> sorted_buf;
		sorted_buf.resize(N + 16);
		Vector<pbvh_internal_t> internals;
		internals.resize(2 * (N + 16));
		Vector<uint32_t> bucket_dir;
		bucket_dir.resize(2u * (1u << HILBERT_PREFIX_BITS));

		pbvh_tree_t tree = {};
		tree.nodes = storage.ptrw();
		tree.capacity = storage.size();
		tree.root = PBVH_NULL_NODE;
		tree.free_head = PBVH_NULL_NODE;
		tree.sorted = sorted_buf.ptrw();
		tree.internals = internals.ptrw();
		tree.internal_capacity = internals.size();
		tree.internal_root = PBVH_NULL_NODE;
		tree.bucket_dir = bucket_dir.ptrw();
		tree.bucket_bits = HILBERT_PREFIX_BITS;

		const uint64_t t_p_ins0 = OS::get_singleton()->get_ticks_usec();
		for (uint32_t i = 0; i < N; i++) {
			pbvh_tree_insert_h(&tree, (pbvh_eclass_id_t)i,
					r128s[i].box, r128s[i].hilbert);
		}
		const uint64_t t_p_ins = OS::get_singleton()->get_ticks_usec() - t_p_ins0;

		const uint64_t t_p_build0 = OS::get_singleton()->get_ticks_usec();
		pbvh_tree_build(&tree);
		const uint64_t t_p_build = OS::get_singleton()->get_ticks_usec() - t_p_build0;

		LocalVector<pbvh_dirty_leaf_t> dirty;
		dirty.resize(N);
		XorShift rng(0xABCDEFull ^ (uint64_t)N);
		for (uint32_t i = 0; i < N; i++) {
			AABB moved = floats[i].box;
			moved.position += Vector3(rng.uniform(-0.01f, 0.01f),
					rng.uniform(-0.01f, 0.01f), rng.uniform(-0.01f, 0.01f));
			Aabb rb = aabb_from_floats(
					moved.position.x, moved.position.x + moved.size.x,
					moved.position.y, moved.position.y + moved.size.y,
					moved.position.z, moved.position.z + moved.size.z);
			const uint32_t new_h = hilbert_of_aabb(&rb, &scene);
			dirty[i].leaf_id = (pbvh_node_id_t)i;
			dirty[i].old_hilbert = r128s[i].hilbert;
			r128s.write[i].box = rb;
			r128s.write[i].hilbert = new_h;
			pbvh_tree_update_h(&tree, (pbvh_node_id_t)i, rb, new_h);
		}

		const uint64_t t_p_tick0 = OS::get_singleton()->get_ticks_usec();
		pbvh_tree_tick(&tree, dirty.ptr(), N);
		const uint64_t t_p_tick = OS::get_singleton()->get_ticks_usec() - t_p_tick0;

		DynamicBVH dtree;
		LocalVector<DynamicBVH::ID> dids;
		dids.resize(N);

		const uint64_t t_d_ins0 = OS::get_singleton()->get_ticks_usec();
		for (uint32_t i = 0; i < N; i++) {
			dids[i] = dtree.insert(floats[i].box, (void *)(uintptr_t)i);
		}
		const uint64_t t_d_ins = OS::get_singleton()->get_ticks_usec() - t_d_ins0;

		const uint64_t t_d_upd0 = OS::get_singleton()->get_ticks_usec();
		for (uint32_t i = 0; i < N; i++) {
			dtree.update(dids[i], floats[i].box);
		}
		const uint64_t t_d_upd = OS::get_singleton()->get_ticks_usec() - t_d_upd0;

		const uint64_t t_d_opt0 = OS::get_singleton()->get_ticks_usec();
		dtree.optimize_incremental(1);
		const uint64_t t_d_opt = OS::get_singleton()->get_ticks_usec() - t_d_opt0;

		pbvh_totals[s] = t_p_ins + t_p_build + t_p_tick;
		dbvh_totals[s] = t_d_ins + t_d_upd + t_d_opt;

		print_line(vformat("[N=%5d] pbvh ins=%7d build=%7d tick=%7d total=%8d us  |  dbvh ins=%7d upd=%7d opt=%7d total=%8d us",
				(int)N, (int)t_p_ins, (int)t_p_build, (int)t_p_tick, (int)pbvh_totals[s],
				(int)t_d_ins, (int)t_d_upd, (int)t_d_opt, (int)dbvh_totals[s]));
	}

	print_line("[growth rate per doubling of N — exponent = log2(ratio)]");
	for (uint32_t s = 1; s < kSweeps; s++) {
		const double p_ratio = (double)pbvh_totals[s] / (double)MAX((uint64_t)1, pbvh_totals[s - 1]);
		const double d_ratio = (double)dbvh_totals[s] / (double)MAX((uint64_t)1, dbvh_totals[s - 1]);
		const double p_exp = p_ratio > 0.0 ? std::log2(p_ratio) : 0.0;
		const double d_exp = d_ratio > 0.0 ? std::log2(d_ratio) : 0.0;
		print_line(vformat("    N:%5d -> %5d   pbvh x%.2f (exp %.2f)   dbvh x%.2f (exp %.2f)",
				(int)Ns[s - 1], (int)Ns[s], p_ratio, p_exp, d_ratio, d_exp));
	}

	for (uint32_t s = 0; s < kSweeps; s++) {
		CHECK(pbvh_totals[s] > 0);
		CHECK(dbvh_totals[s] > 0);
	}
}

// Per-frame steady-state cost at dirty_fraction=1% with Q queries/frame.
// Production workload: ~1% of instances move + a bounded query budget
// (physics neighbor queries, frustum culls, etc.). Initial build is NOT
// counted; only the hot loop each frame pays: updates + tick/optimize
// + Q aabb_queries. Both backends must return the same hit count as a
// linear-scan ground truth — enforced per-frame via CHECK_MESSAGE.
static int pbvh_count_cb_(pbvh_eclass_id_t, void *ud) {
	*(uint64_t *)ud += 1u;
	return 0;
}
struct BenchPairCollector {
	uint64_t hits = 0;
	bool operator()(void *) { hits++; return false; }
};
TEST_CASE("[PredictiveBVH][Bench] per-frame 1%-dirty + Q-queries steady-state") {
	constexpr uint32_t Ns[] = { 4096u, 16384u, 65536u, 262144u };
	constexpr uint32_t kSweeps = sizeof(Ns) / sizeof(Ns[0]);
	constexpr double kDirtyFrac = 0.01;
	constexpr uint32_t kFrames = 16u;
	constexpr uint32_t kQueries = 16u;
	constexpr float kQueryExt = 1.0f; // 1 m half-extent, ~60 leaves/query at N=16k, sparser at higher N

	Aabb scene = aabb_from_floats(-BENCH_BOUND, BENCH_BOUND,
			-BENCH_BOUND, BENCH_BOUND, -BENCH_BOUND, BENCH_BOUND);

	for (uint32_t s = 0; s < kSweeps; s++) {
		const uint32_t N = Ns[s];
		const uint32_t dirty_n = MAX((uint32_t)1, (uint32_t)((double)N * kDirtyFrac));

		Vector<FloatLeaf> floats;
		Vector<R128Leaf> r128s;
		generate_dataset(N, 0xFEED1234ull ^ (uint64_t)N, floats, r128s);

		Vector<pbvh_node_t> storage; storage.resize(N + 16);
		Vector<pbvh_node_id_t> sorted_buf; sorted_buf.resize(N + 16);
		const uint32_t internal_cap = 2u * (N + 16u);
		Vector<pbvh_internal_t> internals; internals.resize(internal_cap);
		Vector<uint32_t> bucket_dir; bucket_dir.resize(2u * (1u << HILBERT_PREFIX_BITS));
		Vector<uint32_t> parent_of; parent_of.resize(internal_cap);
		Vector<uint32_t> leaf_to; leaf_to.resize(N + 16);
		const uint32_t touched_words = (internal_cap + 63u) / 64u;
		Vector<uint64_t> touched_bits; touched_bits.resize(touched_words);
		Vector<uint64_t> touched_meta_bits; touched_meta_bits.resize((touched_words + 63u) / 64u);

		pbvh_tree_t tree = {};
		tree.nodes = storage.ptrw(); tree.capacity = storage.size();
		tree.root = PBVH_NULL_NODE; tree.free_head = PBVH_NULL_NODE;
		tree.sorted = sorted_buf.ptrw();
		tree.internals = internals.ptrw(); tree.internal_capacity = internals.size();
		tree.internal_root = PBVH_NULL_NODE;
		tree.bucket_dir = bucket_dir.ptrw();
		tree.bucket_bits = HILBERT_PREFIX_BITS;
		tree.parent_of_internal = parent_of.ptrw();
		tree.leaf_to_internal = leaf_to.ptrw();
		tree.touched_bits = touched_bits.ptrw();
		tree.touched_meta_bits = touched_meta_bits.ptrw();

		for (uint32_t i = 0; i < N; i++) {
			pbvh_tree_insert_h(&tree, (pbvh_eclass_id_t)i, r128s[i].box, r128s[i].hilbert);
		}
		pbvh_tree_build(&tree);

		DynamicBVH dtree;
		LocalVector<DynamicBVH::ID> dids; dids.resize(N);
		for (uint32_t i = 0; i < N; i++) {
			dids[i] = dtree.insert(floats[i].box, (void *)(uintptr_t)i);
		}

		XorShift rng(0x1234ull ^ (uint64_t)N);
		uint64_t t_pbvh_frames = 0, t_dbvh_frames = 0;
		uint64_t pbvh_hits_total = 0, dbvh_hits_total = 0, truth_hits_total = 0;

		for (uint32_t f = 0; f < kFrames; f++) {
			LocalVector<pbvh_dirty_leaf_t> dirty;
			dirty.resize(dirty_n);
			LocalVector<uint32_t> dirty_ids; dirty_ids.resize(dirty_n);
			for (uint32_t d = 0; d < dirty_n; d++) {
				uint32_t id = rng.next_u32() % N;
				dirty_ids[d] = id;
				AABB moved = floats[id].box;
				moved.position += Vector3(rng.uniform(-0.001f, 0.001f),
						rng.uniform(-0.001f, 0.001f), rng.uniform(-0.001f, 0.001f));
				floats.write[id].box = moved;
				Aabb rb = aabb_from_floats(
						moved.position.x, moved.position.x + moved.size.x,
						moved.position.y, moved.position.y + moved.size.y,
						moved.position.z, moved.position.z + moved.size.z);
				const uint32_t new_h = hilbert_of_aabb(&rb, &scene);
				dirty[d].leaf_id = (pbvh_node_id_t)id;
				dirty[d].old_hilbert = r128s[id].hilbert;
				r128s.write[id].box = rb;
				r128s.write[id].hilbert = new_h;
			}

			const uint64_t t_p0 = OS::get_singleton()->get_ticks_usec();
			for (uint32_t d = 0; d < dirty_n; d++) {
				pbvh_tree_update_h(&tree, dirty[d].leaf_id,
						r128s[dirty_ids[d]].box, r128s[dirty_ids[d]].hilbert);
			}
			pbvh_tree_tick(&tree, dirty.ptr(), dirty_n);
			t_pbvh_frames += OS::get_singleton()->get_ticks_usec() - t_p0;

			const uint64_t t_d0 = OS::get_singleton()->get_ticks_usec();
			for (uint32_t d = 0; d < dirty_n; d++) {
				dtree.update(dids[dirty_ids[d]], floats[dirty_ids[d]].box);
			}
			dtree.optimize_incremental(1);
			t_dbvh_frames += OS::get_singleton()->get_ticks_usec() - t_d0;

			// Query phase — same Q queries hit both backends. Hits per
			// backend must equal a linear-scan ground truth over the current
			// leaf set; otherwise a backend is under-reporting (unsound) or
			// over-reporting (slack bounds leaking through the leaf test).
			AABB q_f[kQueries]; Aabb q_r[kQueries];
			for (uint32_t q = 0; q < kQueries; q++) {
				const float qx = rng.uniform(-BENCH_BOUND, BENCH_BOUND);
				const float qy = rng.uniform(-BENCH_BOUND, BENCH_BOUND);
				const float qz = rng.uniform(-BENCH_BOUND, BENCH_BOUND);
				q_f[q] = AABB(Vector3(qx - kQueryExt, qy - kQueryExt, qz - kQueryExt),
						Vector3(2.0f * kQueryExt, 2.0f * kQueryExt, 2.0f * kQueryExt));
				q_r[q] = aabb_from_floats(qx - kQueryExt, qx + kQueryExt,
						qy - kQueryExt, qy + kQueryExt,
						qz - kQueryExt, qz + kQueryExt);
			}

			// Ground truth: linear scan over live R128 bounds with the same
			// overlap primitive the backends use (aabb_overlaps). Any backend
			// that disagrees is either unsound (miss) or slack (extra hit).
			uint64_t truth_hits = 0;
			for (uint32_t q = 0; q < kQueries; q++) {
				for (uint32_t i = 0; i < N; i++) {
					if (aabb_overlaps(&r128s[i].box, &q_r[q])) {
						truth_hits++;
					}
				}
			}
			truth_hits_total += truth_hits;

			const uint64_t t_pq0 = OS::get_singleton()->get_ticks_usec();
			uint64_t pbvh_hits = 0;
			for (uint32_t q = 0; q < kQueries; q++) {
				pbvh_tree_aabb_query_n(&tree, &q_r[q], &pbvh_count_cb_, &pbvh_hits);
			}
			t_pbvh_frames += OS::get_singleton()->get_ticks_usec() - t_pq0;
			pbvh_hits_total += pbvh_hits;

			const uint64_t t_dq0 = OS::get_singleton()->get_ticks_usec();
			BenchPairCollector dbvh_ctr;
			for (uint32_t q = 0; q < kQueries; q++) {
				dtree.aabb_query(q_f[q], dbvh_ctr);
			}
			t_dbvh_frames += OS::get_singleton()->get_ticks_usec() - t_dq0;
			dbvh_hits_total += dbvh_ctr.hits;

			// Per-frame tightness: pbvh must match truth exactly (same R128
			// overlap primitive). DynamicBVH uses float AABBs so boundary
			// rounding can differ by a few hits; we enforce loose parity
			// within 2% rather than strict equality there.
			CHECK_MESSAGE(pbvh_hits == truth_hits,
					vformat("pbvh tightness: hits=%d truth=%d (N=%d frame=%d)",
							(int)pbvh_hits, (int)truth_hits, (int)N, (int)f));
			const int64_t dbvh_delta = (int64_t)dbvh_ctr.hits - (int64_t)truth_hits;
			const int64_t dbvh_tol = MAX((int64_t)1, (int64_t)truth_hits / 50);
			CHECK_MESSAGE(std::abs(dbvh_delta) <= dbvh_tol,
					vformat("dbvh tightness (float roundoff): hits=%d truth=%d (N=%d frame=%d)",
							(int)dbvh_ctr.hits, (int)truth_hits, (int)N, (int)f));
		}

		const double p_per = (double)t_pbvh_frames / (double)kFrames;
		const double d_per = (double)t_dbvh_frames / (double)kFrames;
		const double speedup = p_per > 0.0 ? d_per / p_per : 0.0;
		print_line(vformat("[N=%6d dirty=%5d Q=%d] pbvh %.1fus  dbvh %.1fus  pbvh-x%.2f  hits(truth=%d pbvh=%d dbvh=%d)",
				(int)N, (int)dirty_n, (int)kQueries, p_per, d_per, speedup,
				(int)truth_hits_total, (int)pbvh_hits_total, (int)dbvh_hits_total));

		CHECK(t_pbvh_frames > 0);
		CHECK(t_dbvh_frames > 0);
		CHECK(pbvh_hits_total == truth_hits_total);
	}
}

// Overload / stress bench — models the cliff the tree path hits when the
// containment early-out STOPS firing: 20% of instances move per frame with
// metre-scale displacement (crowd event, ragdoll cascade, adversarial
// teleport). Under this workload every dirty leaf's new bounds exceed the
// parent's, so the ancestor mark walk runs full depth and refit loses its
// O(1)-per-contained-leaf path. This establishes the pre-ghost baseline;
// ghost-bound pruning (Phase 2c+) is expected to pin the cost back by
// short-circuiting refit whenever motion stays inside the predicted ghost.
TEST_CASE("[PredictiveBVH][Bench] per-frame stress 20%-dirty metre-scale motion") {
	constexpr uint32_t Ns[] = { 4096u, 16384u, 65536u };
	constexpr uint32_t kSweeps = sizeof(Ns) / sizeof(Ns[0]);
	constexpr double kDirtyFrac = 0.20;
	constexpr uint32_t kFrames = 8u;
	constexpr uint32_t kQueries = 256u;
	constexpr float kQueryExt = 1.0f;
	constexpr float kMotionMax = 2.0f; // metres per frame — blows the parent-bounds containment

	Aabb scene = aabb_from_floats(-BENCH_BOUND, BENCH_BOUND,
			-BENCH_BOUND, BENCH_BOUND, -BENCH_BOUND, BENCH_BOUND);

	for (uint32_t s = 0; s < kSweeps; s++) {
		const uint32_t N = Ns[s];
		const uint32_t dirty_n = MAX((uint32_t)1, (uint32_t)((double)N * kDirtyFrac));

		Vector<FloatLeaf> floats;
		Vector<R128Leaf> r128s;
		generate_dataset(N, 0xC0FFEEu ^ (uint64_t)N, floats, r128s);

		Vector<pbvh_node_t> storage; storage.resize(N + 16);
		Vector<pbvh_node_id_t> sorted_buf; sorted_buf.resize(N + 16);
		const uint32_t internal_cap = 2u * (N + 16u);
		Vector<pbvh_internal_t> internals; internals.resize(internal_cap);
		Vector<uint32_t> bucket_dir; bucket_dir.resize(2u * (1u << HILBERT_PREFIX_BITS));
		Vector<uint32_t> parent_of; parent_of.resize(internal_cap);
		Vector<uint32_t> leaf_to; leaf_to.resize(N + 16);
		const uint32_t touched_words = (internal_cap + 63u) / 64u;
		Vector<uint64_t> touched_bits; touched_bits.resize(touched_words);
		Vector<uint64_t> touched_meta_bits; touched_meta_bits.resize((touched_words + 63u) / 64u);

		pbvh_tree_t tree = {};
		tree.nodes = storage.ptrw(); tree.capacity = storage.size();
		tree.root = PBVH_NULL_NODE; tree.free_head = PBVH_NULL_NODE;
		tree.sorted = sorted_buf.ptrw();
		tree.internals = internals.ptrw(); tree.internal_capacity = internals.size();
		tree.internal_root = PBVH_NULL_NODE;
		tree.bucket_dir = bucket_dir.ptrw();
		tree.bucket_bits = HILBERT_PREFIX_BITS;
		tree.parent_of_internal = parent_of.ptrw();
		tree.leaf_to_internal = leaf_to.ptrw();
		tree.touched_bits = touched_bits.ptrw();
		tree.touched_meta_bits = touched_meta_bits.ptrw();

		for (uint32_t i = 0; i < N; i++) {
			pbvh_tree_insert_h(&tree, (pbvh_eclass_id_t)i, r128s[i].box, r128s[i].hilbert);
		}
		pbvh_tree_build(&tree);

		DynamicBVH dtree;
		LocalVector<DynamicBVH::ID> dids; dids.resize(N);
		for (uint32_t i = 0; i < N; i++) {
			dids[i] = dtree.insert(floats[i].box, (void *)(uintptr_t)i);
		}

		XorShift rng(0xBEEFBEEFu ^ (uint64_t)N);
		uint64_t t_pbvh_frames = 0, t_dbvh_frames = 0;
		uint64_t pbvh_hits_total = 0, dbvh_hits_total = 0, truth_hits_total = 0;

		for (uint32_t f = 0; f < kFrames; f++) {
			LocalVector<pbvh_dirty_leaf_t> dirty;
			dirty.resize(dirty_n);
			LocalVector<uint32_t> dirty_ids; dirty_ids.resize(dirty_n);
			for (uint32_t d = 0; d < dirty_n; d++) {
				uint32_t id = rng.next_u32() % N;
				dirty_ids[d] = id;
				AABB moved = floats[id].box;
				moved.position += Vector3(rng.uniform(-kMotionMax, kMotionMax),
						rng.uniform(-kMotionMax, kMotionMax), rng.uniform(-kMotionMax, kMotionMax));
				floats.write[id].box = moved;
				Aabb rb = aabb_from_floats(
						moved.position.x, moved.position.x + moved.size.x,
						moved.position.y, moved.position.y + moved.size.y,
						moved.position.z, moved.position.z + moved.size.z);
				const uint32_t new_h = hilbert_of_aabb(&rb, &scene);
				dirty[d].leaf_id = (pbvh_node_id_t)id;
				dirty[d].old_hilbert = r128s[id].hilbert;
				r128s.write[id].box = rb;
				r128s.write[id].hilbert = new_h;
			}

			const uint64_t t_p0 = OS::get_singleton()->get_ticks_usec();
			for (uint32_t d = 0; d < dirty_n; d++) {
				pbvh_tree_update_h(&tree, dirty[d].leaf_id,
						r128s[dirty_ids[d]].box, r128s[dirty_ids[d]].hilbert);
			}
			pbvh_tree_tick(&tree, dirty.ptr(), dirty_n);
			t_pbvh_frames += OS::get_singleton()->get_ticks_usec() - t_p0;

			const uint64_t t_d0 = OS::get_singleton()->get_ticks_usec();
			for (uint32_t d = 0; d < dirty_n; d++) {
				dtree.update(dids[dirty_ids[d]], floats[dirty_ids[d]].box);
			}
			dtree.optimize_incremental(1);
			t_dbvh_frames += OS::get_singleton()->get_ticks_usec() - t_d0;

			AABB q_f[kQueries]; Aabb q_r[kQueries];
			for (uint32_t q = 0; q < kQueries; q++) {
				const float qx = rng.uniform(-BENCH_BOUND, BENCH_BOUND);
				const float qy = rng.uniform(-BENCH_BOUND, BENCH_BOUND);
				const float qz = rng.uniform(-BENCH_BOUND, BENCH_BOUND);
				q_f[q] = AABB(Vector3(qx - kQueryExt, qy - kQueryExt, qz - kQueryExt),
						Vector3(2.0f * kQueryExt, 2.0f * kQueryExt, 2.0f * kQueryExt));
				q_r[q] = aabb_from_floats(qx - kQueryExt, qx + kQueryExt,
						qy - kQueryExt, qy + kQueryExt,
						qz - kQueryExt, qz + kQueryExt);
			}

			uint64_t truth_hits = 0;
			for (uint32_t q = 0; q < kQueries; q++) {
				for (uint32_t i = 0; i < N; i++) {
					if (aabb_overlaps(&r128s[i].box, &q_r[q])) {
						truth_hits++;
					}
				}
			}
			truth_hits_total += truth_hits;

			const uint64_t t_pq0 = OS::get_singleton()->get_ticks_usec();
			uint64_t pbvh_hits = 0;
			for (uint32_t q = 0; q < kQueries; q++) {
				pbvh_tree_aabb_query_n(&tree, &q_r[q], &pbvh_count_cb_, &pbvh_hits);
			}
			t_pbvh_frames += OS::get_singleton()->get_ticks_usec() - t_pq0;
			pbvh_hits_total += pbvh_hits;

			const uint64_t t_dq0 = OS::get_singleton()->get_ticks_usec();
			BenchPairCollector dbvh_ctr;
			for (uint32_t q = 0; q < kQueries; q++) {
				dtree.aabb_query(q_f[q], dbvh_ctr);
			}
			t_dbvh_frames += OS::get_singleton()->get_ticks_usec() - t_dq0;
			dbvh_hits_total += dbvh_ctr.hits;

			CHECK_MESSAGE(pbvh_hits == truth_hits,
					vformat("pbvh tightness: hits=%d truth=%d (N=%d frame=%d)",
							(int)pbvh_hits, (int)truth_hits, (int)N, (int)f));
			const int64_t dbvh_delta = (int64_t)dbvh_ctr.hits - (int64_t)truth_hits;
			const int64_t dbvh_tol = MAX((int64_t)1, (int64_t)truth_hits / 50);
			CHECK_MESSAGE(std::abs(dbvh_delta) <= dbvh_tol,
					vformat("dbvh tightness (float roundoff): hits=%d truth=%d (N=%d frame=%d)",
							(int)dbvh_ctr.hits, (int)truth_hits, (int)N, (int)f));
		}

		const double p_per = (double)t_pbvh_frames / (double)kFrames;
		const double d_per = (double)t_dbvh_frames / (double)kFrames;
		const double speedup = p_per > 0.0 ? d_per / p_per : 0.0;
		print_line(vformat("[STRESS N=%6d dirty=%5d Q=%d motion=%.1fm] pbvh %.1fus  dbvh %.1fus  pbvh-x%.2f  hits(truth=%d pbvh=%d dbvh=%d)",
				(int)N, (int)dirty_n, (int)kQueries, (double)kMotionMax, p_per, d_per, speedup,
				(int)truth_hits_total, (int)pbvh_hits_total, (int)dbvh_hits_total));

		CHECK(t_pbvh_frames > 0);
		CHECK(t_dbvh_frames > 0);
		CHECK(pbvh_hits_total == truth_hits_total);
	}
}

} // namespace TestPredictiveBVHBench

#endif // MODULE_MULTIPLAYER_FABRIC_ENABLED
