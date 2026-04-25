# headless_log_observer.gd
# Headless diagnostic observer for the zone server.
#
# Usage:
#   godot --headless --path . --script scripts/headless_log_observer.gd \
#         -- [--host=HOST] [--port=PORT] [--dump-json=PATH] [--frames=N]
#
# Defaults: host=127.0.0.1 port=7443 frames=600
# Exits 0 when entities are received, 1 on timeout with no entities.

extends SceneTree

var _frames: int = 0
var _max_frames: int = 600
var _dump_path: String = ""
var _host: String = "127.0.0.1"
var _port: int = 7443
var client: Node = null

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--host="):
			_host = arg.split("=")[1]
		elif arg.begins_with("--port="):
			_port = int(arg.split("=")[1])
		elif arg.begins_with("--dump-json="):
			_dump_path = arg.split("=")[1]
		elif arg.begins_with("--frames="):
			_max_frames = int(arg.split("=")[1])

	print("[HeadlessObserver] Connecting to %s:%d" % [_host, _port])

	client = preload("res://scripts/fabric_client.gd").new()
	client.zone_host = _host
	client.zone_port = _port
	root.add_child(client)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	_frames += 1

	if _frames % 60 == 0:
		var entities := _collect_entities()
		print("[HeadlessObserver] frame=%d entities=%d" % [_frames, entities.size()])
		for e in entities.slice(0, 5):
			print("  id=%d pos=%s" % [e.get("id", -1), e.get("pos", Vector3.ZERO)])

		if entities.size() > 0:
			_finish(entities, 0)
			return

	if _frames >= _max_frames:
		print("[HeadlessObserver] Timeout — no entities received.")
		_finish([], 1)

func _collect_entities() -> Array:
	var out := []
	if not client or not "get" in client:
		return out
	var nodes = client.get("_entity_nodes")
	if not nodes:
		return out
	for k in nodes.keys():
		var node := nodes[k] as Node3D
		if node and is_instance_valid(node):
			out.append({"id": k, "pos": node.global_position})
	return out

func _finish(entities: Array, exit_code: int) -> void:
	if _dump_path != "":
		var json := JSON.stringify(entities.map(func(e):
			return {
				"id": e["id"],
				"pos": {"x": e["pos"].x, "y": e["pos"].y, "z": e["pos"].z}
			}
		))
		var f := FileAccess.open(_dump_path, FileAccess.WRITE)
		if f:
			f.store_string(json)
			f.close()
			print("[HeadlessObserver] Wrote %d entities to %s" % [entities.size(), _dump_path])
		else:
			push_error("[HeadlessObserver] Could not write to %s" % _dump_path)

	quit(exit_code)
