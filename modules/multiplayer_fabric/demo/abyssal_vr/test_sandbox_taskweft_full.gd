extends SceneTree

const ELF_DEFAULT := "res://sandbox/taskweft_planner.elf"
const DOMAINS_DIR := "res://taskweft_domains/domains/"

func _init() -> void:
	var elf_path := ELF_DEFAULT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--elf="):
			elf_path = arg.substr(6)

	var bytes := FileAccess.get_file_as_bytes(elf_path)
	if bytes.is_empty():
		push_error("Cannot read ELF: " + elf_path)
		quit(1)
		return

	var sandbox := Sandbox.new()
	sandbox.load_buffer(bytes)
	if not sandbox.has_program_loaded():
		push_error("Sandbox failed to load ELF")
		quit(1)
		return

	sandbox.set_unboxed_arguments(true)

	var plan_domain_fn: Callable = sandbox.vmcallable("api_plan_domain")
	var hrr_encode_fn:  Callable = sandbox.vmcallable("api_hrr_encode_atom")
	var hrr_sim_fn:     Callable = sandbox.vmcallable("api_hrr_similarity")

	var passed := 0
	var failed := 0

	# ── Domain planning tests ────────────────────────────────────────────────
	var domains := [
		"simple_travel.jsonld",
		"blocks_world.jsonld",
		"rescue.jsonld",
		"healthcare.jsonld",
		"job_shop_scheduling.jsonld",
		"robosub.jsonld",
	]

	for fname in domains:
		var json := FileAccess.get_file_as_string(DOMAINS_DIR + fname)
		if json.is_empty():
			print("SKIP %s (file not found)" % fname)
			continue
		var result: String = str(plan_domain_fn.call(json))
		var ok := result != "null" and not result.is_empty()
		if ok:
			print("PASS plan %s: %s" % [fname.get_basename(), result.left(80)])
			passed += 1
		else:
			print("FAIL plan %s: returned null" % fname.get_basename())
			failed += 1

	# ── HRR encode + similarity ──────────────────────────────────────────────
	var dim := 64
	var a_json: String = str(hrr_encode_fn.call("cat", dim))
	var b_json: String = str(hrr_encode_fn.call("dog", dim))
	var c_json: String = str(hrr_encode_fn.call("cat", dim))

	if a_json.begins_with("[") and b_json.begins_with("["):
		var sim_ab: float = hrr_sim_fn.call(a_json, b_json)
		var sim_ac: float = hrr_sim_fn.call(a_json, c_json)
		# cat vs cat should be more similar than cat vs dog
		if sim_ac > sim_ab and absf(sim_ac - 1.0) < 0.001:
			print("PASS hrr: sim(cat,cat)=%.4f > sim(cat,dog)=%.4f" % [sim_ac, sim_ab])
			passed += 1
		else:
			print("FAIL hrr: sim(cat,cat)=%.4f sim(cat,dog)=%.4f" % [sim_ac, sim_ab])
			failed += 1
	else:
		print("FAIL hrr_encode: unexpected output: %s" % a_json.left(40))
		failed += 1

	print("\n%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
