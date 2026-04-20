extends SceneTree

var _frames: int = 0

func _init() -> void:
	var packed := load("res://scenes/observer.tscn") as PackedScene
	if packed == null:
		push_error("capture: failed to load observer.tscn")
		quit(1)
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames < 12:
		return
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("screenshots")
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://screenshots/observer_overlay_fix.png")
	quit()
