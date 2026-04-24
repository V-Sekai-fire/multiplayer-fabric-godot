extends SceneTree

const ELF_DEFAULT := "res://sandbox/taskweft_planner.elf"

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

	var domain_json := FileAccess.get_file_as_string(
		"res://taskweft_domains/domains/simple_travel.jsonld")
	if domain_json.is_empty():
		push_error("Cannot read simple_travel.jsonld")
		quit(1)
		return

	var load_fn: Callable = sandbox.vmcallable("api_load_domain")
	var plan_fn: Callable = sandbox.vmcallable("api_plan")

	load_fn.call(domain_json)
	var result: String = str(plan_fn.call())

	if result == "null" or result.is_empty():
		print("FAIL simple_travel: plan returned null")
		quit(1)
		return

	print("PASS simple_travel: ", result)
	quit(0)
