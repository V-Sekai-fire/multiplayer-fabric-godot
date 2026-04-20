# jellyfish_asset_loader.gd
# Proximity-driven mesh streaming via FabricMMOGAsset → uro.
# Attach to a Node3D. Call update_observer(pos) each frame from fabric_client.gd.
# Meshes within NEAR_RADIUS load high-detail; beyond FAR_RADIUS assets are freed.

extends Node3D

const NEAR_RADIUS   := 8.0    # m — load high-detail jellyfish mesh
const FAR_RADIUS    := 24.0   # m — unload; switch to procedural stand-in
const CHUNK_CACHE   := "user://jellygrid_cache"
const OUTPUT_DIR    := "user://jellygrid_assets"

# Asset UUIDs registered in uro /storage/:id/manifest.
# These map to .glb meshes uploaded via the content-addressable store.
const ASSET_UUIDS := {
	"jellyfish_hd"   : "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
	"jellyfish_pred" : "b2c3d4e5-f6a7-8901-bcde-f12345678901",
	"power_node"     : "c3d4e5f6-a7b8-9012-cdef-123456789012",
	"biome_reef"     : "d4e5f6a7-b8c9-0123-defa-234567890123",
}

var _uro_base_url: String = ""
var _asset       : FabricMMOGAsset = null
var _loaded_meshes: Dictionary = {}   # uuid → MeshInstance3D


func _ready() -> void:
	_asset = FabricMMOGAsset.new()
	DirAccess.make_dir_recursive_absolute(CHUNK_CACHE)
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)


func configure(uro_base_url: String) -> void:
	_uro_base_url = uro_base_url


func update_observer(observer_pos: Vector3) -> void:
	if _uro_base_url.is_empty():
		return

	for entity_node in get_children():
		if not entity_node is Node3D:
			continue
		var dist: float = observer_pos.distance_to(entity_node.global_position)
		var uuid: String = entity_node.get_meta("asset_uuid", "")
		if uuid.is_empty():
			continue

		if dist < NEAR_RADIUS and uuid not in _loaded_meshes:
			_stream_asset(uuid, entity_node)
		elif dist > FAR_RADIUS and uuid in _loaded_meshes:
			_unload_asset(uuid, entity_node)


func request_jellyfish_mesh(entity_id: int, node: Node3D) -> void:
	var uuid := ASSET_UUIDS["jellyfish_hd"] if entity_id < 256 \
		else ASSET_UUIDS["jellyfish_pred"]
	node.set_meta("asset_uuid", uuid)


func request_power_node_mesh(node: Node3D) -> void:
	node.set_meta("asset_uuid", ASSET_UUIDS["power_node"])


func request_biome(biome_name: String, node: Node3D) -> void:
	var uuid := ASSET_UUIDS.get("biome_" + biome_name, "")
	if not uuid.is_empty():
		node.set_meta("asset_uuid", uuid)


# ── Internal ──────────────────────────────────────────────────────────────────

func _stream_asset(uuid: String, parent: Node3D) -> void:
	# Run blocking fetch off the main thread via WorkerThreadPool.
	WorkerThreadPool.add_task(_fetch_and_attach.bind(uuid, parent))


func _fetch_and_attach(uuid: String, parent: Node3D) -> void:
	var index_url := _uro_base_url + "/storage/" + uuid + "/manifest"
	var local_path := _asset.fetch_asset(
		FabricMMOGAsset.DEFAULT_STORE_URL,
		index_url,
		OUTPUT_DIR,
		CHUNK_CACHE
	)
	if local_path.is_empty():
		push_warning("jellyfish_asset_loader: fetch failed for " + uuid)
		return
	call_deferred("_attach_mesh", uuid, local_path, parent)


func _attach_mesh(uuid: String, path: String, parent: Node3D) -> void:
	if not FileAccess.file_exists(path):
		return
	var scene: Resource = ResourceLoader.load(path)
	if scene == null:
		return
	var mi: Node = scene.instantiate() if scene is PackedScene else MeshInstance3D.new()
	parent.add_child(mi)
	_loaded_meshes[uuid] = mi


func _unload_asset(uuid: String, parent: Node3D) -> void:
	if uuid in _loaded_meshes:
		_loaded_meshes[uuid].queue_free()
		_loaded_meshes.erase(uuid)
