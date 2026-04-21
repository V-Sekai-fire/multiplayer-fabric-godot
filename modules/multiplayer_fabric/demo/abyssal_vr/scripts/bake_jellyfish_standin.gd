@tool
extends EditorScript

# Run once via Godot editor: Scene → Run Script
# Produces res://scenes/jellyfish_standin.scn — a baked-mesh jellyfish bell+tentacles.
# Upload that file to Uro /storage and paste the returned UUID into jellyfish_asset_loader.gd.

const OUTPUT_PATH := "res://scenes/jellyfish_standin.scn"

func _run() -> void:
	var root := Node3D.new()
	root.name = "JellyfishStandin"

	# Bell — flattened sphere
	var bell := CSGSphere3D.new()
	bell.name = "Bell"
	bell.radius = 0.4
	bell.rings = 8
	bell.radial_segments = 12
	bell.scale = Vector3(1.0, 0.55, 1.0)
	root.add_child(bell)
	bell.owner = root

	# Tentacles — 6 thin cylinders hanging below
	for i in 6:
		var angle := TAU * i / 6.0
		var t := CSGCylinder3D.new()
		t.name = "Tentacle%d" % i
		t.radius = 0.025
		t.height = 0.7
		t.sides = 5
		t.position = Vector3(cos(angle) * 0.25, -0.55, sin(angle) * 0.25)
		root.add_child(t)
		t.owner = root

	# Bake CSG → ArrayMesh
	var csg := CSGCombiner3D.new()
	csg.name = "Combiner"
	# Re-parent shapes into combiner for bake
	var bake_root := Node3D.new()
	bake_root.name = "BakeRoot"
	var bell2 := bell.duplicate() as CSGSphere3D
	bake_root.add_child(bell2)
	bell2.owner = bake_root
	for i in 6:
		var t2 := root.get_child(i + 1).duplicate() as CSGCylinder3D
		bake_root.add_child(t2)
		t2.owner = bake_root

	# Add to scene tree temporarily so CSG can process
	EditorInterface.get_edited_scene_root().add_child(bake_root)
	await EditorInterface.get_edited_scene_root().get_tree().process_frame
	await EditorInterface.get_edited_scene_root().get_tree().process_frame

	var meshes := bake_root.get_child(0).get_meshes() if bake_root.get_child_count() > 0 else []
	var array_mesh: ArrayMesh = null

	# Collect all CSG meshes via get_meshes() on each shape
	for child in bake_root.get_children():
		if child is CSGShape3D:
			var m := child.get_meshes()
			if m.size() >= 2 and m[1] is ArrayMesh:
				array_mesh = m[1]
				break

	bake_root.queue_free()

	# Build output scene
	var out := Node3D.new()
	out.name = "JellyfishStandin"

	if array_mesh:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = array_mesh
		out.add_child(mi)
		mi.owner = out
		print("bake_jellyfish_standin: baked mesh — %d surfaces" % array_mesh.get_surface_count())
	else:
		# Fallback: keep the CSG nodes if bake didn't work (editor may need a frame)
		print("bake_jellyfish_standin: bake returned no mesh, saving CSG tree as fallback")
		for child in root.get_children():
			var c := child.duplicate()
			out.add_child(c)
			c.owner = out

	var packed := PackedScene.new()
	packed.pack(out)
	var err := ResourceSaver.save(packed, OUTPUT_PATH)
	if err == OK:
		print("bake_jellyfish_standin: saved → ", OUTPUT_PATH)
		print("Upload to Uro:  curl -X POST <URO>/storage -F file=@<export_path>/jellyfish_standin.scn")
	else:
		push_error("bake_jellyfish_standin: save failed — error %d" % err)
