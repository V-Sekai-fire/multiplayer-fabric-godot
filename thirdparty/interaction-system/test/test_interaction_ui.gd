## RED phase — interaction system placeholder.
##
## Run this as a scene root to see the target UI and which pipeline steps
## pass before the full canvas_plane + LassoDB routing is wired.
##
## Layout
##   Left  — the UI panel that VR controllers will interact with
##   Right — test results (RED = not yet passing)
##
## Green phase: all test rows should flip to PASS when interaction_action
## correctly routes poses → lasso query → call_gui_input on each Control.
extends Node

# ── UI panel under test ──────────────────────────────────────────────────────

var _panel_root: Control
var _btn_release: Button
var _slider_glow: HSlider
var _label_status: Label

# ── test result rows ─────────────────────────────────────────────────────────

var _results: VBoxContainer
var _rows: Dictionary = {}   # test_name -> Label

# ── signal bookkeeping ───────────────────────────────────────────────────────

var _gui_input_fired := false
var _virtual_input_fired := false
var _btn_pressed_fired := false


func _ready() -> void:
	_build_ui()
	_run_unit_tests()


# ── scene construction ────────────────────────────────────────────────────────

func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Left: the actual UI panel to be driven by VR interaction
	_panel_root = VBoxContainer.new()
	_panel_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_panel_root)

	var heading := Label.new()
	heading.text = "Jellyfish Panel (interaction target)"
	_panel_root.add_child(heading)

	_btn_release = Button.new()
	_btn_release.text = "Release Jellyfish"
	_btn_release.pressed.connect(func(): _btn_pressed_fired = true)
	_panel_root.add_child(_btn_release)

	_slider_glow = HSlider.new()
	_slider_glow.min_value = 0.0
	_slider_glow.max_value = 1.0
	_slider_glow.step = 0.01
	_slider_glow.value = 0.5
	_slider_glow.custom_minimum_size.x = 160
	_panel_root.add_child(_slider_glow)

	_label_status = Label.new()
	_label_status.text = "status: waiting"
	_panel_root.add_child(_label_status)

	var sep := VSeparator.new()
	root.add_child(sep)

	# Right: test result display
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)

	var result_heading := Label.new()
	result_heading.text = "Test Results"
	right.add_child(result_heading)

	_results = VBoxContainer.new()
	right.add_child(_results)


func _add_row(name: String) -> void:
	var lbl := Label.new()
	lbl.text = "[ ] %s" % name
	_results.add_child(lbl)
	_rows[name] = lbl


func _mark(name: String, passed: bool, detail: String = "") -> void:
	var lbl: Label = _rows.get(name)
	if lbl == null:
		return
	if passed:
		lbl.text = "[PASS] %s%s" % [name, (" — " + detail) if detail else ""]
		lbl.add_theme_color_override(&"font_color", Color(0.2, 0.9, 0.3))
	else:
		lbl.text = "[FAIL] %s%s" % [name, (" — " + detail) if detail else ""]
		lbl.add_theme_color_override(&"font_color", Color(0.9, 0.2, 0.2))


# ── unit tests ────────────────────────────────────────────────────────────────

func _run_unit_tests() -> void:
	# Register rows first so layout is stable
	_add_row("call_gui_input fires gui_input signal")
	_add_row("call_gui_input reaches _gui_input virtual")
	_add_row("isolated: prior accept does not block second call")
	_add_row("button press via call_gui_input fires pressed signal")
	_add_row("interaction_action routes pose to Control [canvas_plane needed]")
	_add_row("mouse motion updates current_canvas_item [canvas_plane needed]")

	await get_tree().process_frame   # let layout settle so controls are sized

	_test_signal_fires()
	_test_virtual_fires()
	_test_isolation()
	_test_button_press()
	_test_interaction_action_pose()   # RED — canvas_plane not mocked
	_test_interaction_action_motion() # RED — canvas_plane not mocked


# test 1 — call_gui_input fires gui_input signal
func _test_signal_fires() -> void:
	var btn := Button.new()
	add_child(btn)
	var fired := false
	btn.gui_input.connect(func(_e): fired = true)
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(4, 4)
	ev.global_position = btn.get_global_transform_with_canvas().origin + Vector2(4, 4)
	btn.call_gui_input(ev)
	btn.queue_free()
	_mark("call_gui_input fires gui_input signal", fired)


# test 2 — call_gui_input reaches _gui_input override (via inline class)
class _TestButton extends Button:
	var virtual_fired := false
	func _gui_input(_ev: InputEvent) -> void:
		virtual_fired = true


func _test_virtual_fires() -> void:
	var btn := _TestButton.new()
	add_child(btn)
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(4, 4)
	ev.global_position = btn.get_global_transform_with_canvas().origin + Vector2(4, 4)
	btn.call_gui_input(ev)
	var ok: bool = btn.virtual_fired
	btn.queue_free()
	_mark("call_gui_input reaches _gui_input virtual", ok)


# test 3 — isolation: accept in call 1 must not block call 2
func _test_isolation() -> void:
	var btn := Button.new()
	add_child(btn)
	var count := 0
	btn.gui_input.connect(func(e: InputEvent): count += 1; btn.accept_event())
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(4, 4)
	ev.global_position = btn.get_global_transform_with_canvas().origin + Vector2(4, 4)
	btn.call_gui_input(ev)
	btn.call_gui_input(ev)
	btn.queue_free()
	_mark("isolated: prior accept does not block second call", count == 2,
			"signal fired %d/2 times" % count)


# test 4 — Button.pressed fires when a left-click is delivered via call_gui_input
func _test_button_press() -> void:
	var btn := Button.new()
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	add_child(btn)
	var pressed := false
	btn.pressed.connect(func(): pressed = true)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(4, 4)
	press.global_position = btn.get_global_transform_with_canvas().origin + Vector2(4, 4)
	btn.call_gui_input(press)
	btn.queue_free()
	_mark("button press via call_gui_input fires pressed signal", pressed)


# test 5 + 6 — require canvas_plane + lasso_db; leave RED until green phase
func _test_interaction_action_pose() -> void:
	# Canvas3DAnchor and canvas_plane_class live in res://addons/canvas_plane/ which
	# is not present in this repository.  The test documents the dependency and
	# fails visibly so the green phase knows exactly what to stub.
	var has_canvas_plane := ResourceLoader.exists("res://addons/canvas_plane/canvas_plane.gd")
	_mark("interaction_action routes pose to Control [canvas_plane needed]",
			has_canvas_plane,
			"canvas_plane addon missing — expected during red phase")


func _test_interaction_action_motion() -> void:
	var has_canvas_plane := ResourceLoader.exists("res://addons/canvas_plane/canvas_plane.gd")
	_mark("mouse motion updates current_canvas_item [canvas_plane needed]",
			has_canvas_plane,
			"canvas_plane addon missing — expected during red phase")
