extends SceneTree

const Loader = preload("res://scripts/taskweft_domain_loader.gd")

func _init() -> void:
	var results := {}

	# --- simple_travel: alice walks or takes a taxi to park (loc 2) ---
	var r = Loader.load_file(
		"res://taskweft_domains/domains/simple_travel.jsonld")
	if r.is_empty():
		print("FAIL simple_travel: load returned empty")
	else:
		var planner := Taskweft.new()
		planner.set_domain(r.domain)
		var plan = planner.plan(r.state, r.tasks)
		if plan == null:
			print("FAIL simple_travel: plan returned null")
		else:
			print("PASS simple_travel: plan has %d steps: %s" % [plan.size(), plan])
		results["simple_travel"] = plan != null

	# --- blocks_world ---
	r = Loader.load_file(
		"res://taskweft_domains/domains/blocks_world.jsonld")
	if r.is_empty():
		print("FAIL blocks_world: load returned empty")
	else:
		var planner := Taskweft.new()
		planner.set_domain(r.domain)
		var plan = planner.plan(r.state, r.tasks)
		if plan == null:
			print("FAIL blocks_world: plan returned null")
		else:
			print("PASS blocks_world: plan has %d steps" % plan.size())
		results["blocks_world"] = plan != null

	# --- rescue ---
	r = Loader.load_file(
		"res://taskweft_domains/domains/rescue.jsonld")
	if r.is_empty():
		print("FAIL rescue: load returned empty")
	else:
		var planner := Taskweft.new()
		planner.set_domain(r.domain)
		var plan = planner.plan(r.state, r.tasks)
		if plan == null:
			print("FAIL rescue: plan returned null")
		else:
			print("PASS rescue: plan has %d steps" % plan.size())
		results["rescue"] = plan != null

	# --- robosub ---
	r = Loader.load_file(
		"res://taskweft_domains/domains/robosub.jsonld")
	if r.is_empty():
		print("FAIL robosub: load returned empty")
	else:
		var planner := Taskweft.new()
		planner.set_domain(r.domain)
		var plan = planner.plan(r.state, r.tasks)
		if plan == null:
			print("FAIL robosub: plan returned null")
		else:
			print("PASS robosub: plan has %d steps" % plan.size())
		results["robosub"] = plan != null

	# --- healthcare ---
	r = Loader.load_file(
		"res://taskweft_domains/domains/healthcare.jsonld")
	if r.is_empty():
		print("FAIL healthcare: load returned empty")
	else:
		var planner := Taskweft.new()
		planner.set_domain(r.domain)
		var plan = planner.plan(r.state, r.tasks)
		if plan == null:
			print("FAIL healthcare: plan returned null")
		else:
			print("PASS healthcare: plan has %d steps" % plan.size())
		results["healthcare"] = plan != null

	# --- job_shop_scheduling ---
	r = Loader.load_file(
		"res://taskweft_domains/domains/job_shop_scheduling.jsonld")
	if r.is_empty():
		print("FAIL job_shop: load returned empty")
	else:
		var planner := Taskweft.new()
		planner.set_domain(r.domain)
		var plan = planner.plan(r.state, r.tasks)
		if plan == null:
			print("FAIL job_shop: plan returned null")
		else:
			print("PASS job_shop: plan has %d steps" % plan.size())
		results["job_shop"] = plan != null

	var passed := results.values().filter(func(v): return v == true).size()
	print("\n%d / %d domains passed" % [passed, results.size()])

	quit(0 if passed == results.size() else 1)
