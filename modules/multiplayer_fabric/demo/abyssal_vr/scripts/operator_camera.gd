# operator_camera.gd
# Interactive operator camera following 20260425-operator-camera-2-5d.md.
#
# Rotation is expressed as twist/swing in [0, 1] per axis — same decomposition
# as TransformUtil.swing_twist in the humanoid project.
#
#   Twist (yaw around world Y): snaps to {0.0, 0.25, 0.5, 0.75} in Survey mode.
#   Swing (elevation pitch):     fixed at SWING_ELEVATION (55° down), never changes.
#
# Survey mode  — Q/E snap twist, scroll zoom, WASD pan.
# Follow mode  — F on entity; CameraRig lerps to target, twist locked.
# Tab          — toggle PROJECTION_ORTHOGONAL / PROJECTION_PERSPECTIVE.

extends Node3D

const SWING_ELEVATION := 0.153   # 55 / 360 — fixed pitch, never written at runtime
const SNAP_STEP       := 0.25    # one cardinal step in [0, 1]
const ZOOM_MIN        := 10.0
const ZOOM_MAX        := 60.0
const PAN_SPEED_SCALE := 0.5     # world-units per zoom-unit per second
const LERP_SPEED      := 8.0     # twist lerp rate (rad/s feel)
const FOLLOW_LERP     := 4.0     # entity follow lerp rate

enum Mode { SURVEY, FOLLOW }

@export var entities_root: NodePath
@export var zone_count: int = 3

var _mode: Mode = Mode.SURVEY
var _twist: float = 0.0          # current twist, [0, 1]
var _target_twist: float = 0.0   # snap target
var _zoom: float = 40.0
var _follow_target: Node3D = null

@onready var _pivot:  Node3D    = $CameraPivot
@onready var _arm:    SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D  = $CameraPivot/SpringArm3D/Camera3D
@onready var _entities: Node3D  = get_node_or_null(entities_root) if entities_root != NodePath() else null

func _ready() -> void:
	_arm.spring_length = _zoom
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _zoom
	_camera.current = true
	_apply_swing_twist(0.0)

func _process(delta: float) -> void:
	match _mode:
		Mode.SURVEY:
			_handle_survey_input(delta)
		Mode.FOLLOW:
			_handle_follow(delta)
	_apply_swing_twist(delta)
	_export_state_to_js()

func _handle_survey_input(delta: float) -> void:
	# Twist — Q/E snap
	if Input.is_action_just_pressed("cam_rotate_left"):
		_target_twist = fmod(_target_twist - SNAP_STEP + 1.0, 1.0)
	if Input.is_action_just_pressed("cam_rotate_right"):
		_target_twist = fmod(_target_twist + SNAP_STEP, 1.0)

	# Zoom — scroll wheel
	if Input.is_action_just_pressed("cam_zoom_in"):
		_zoom = clampf(_zoom - 5.0, ZOOM_MIN, ZOOM_MAX)
		_arm.spring_length = _zoom
		_camera.size = _zoom
	if Input.is_action_just_pressed("cam_zoom_out"):
		_zoom = clampf(_zoom + 5.0, ZOOM_MIN, ZOOM_MAX)
		_arm.spring_length = _zoom
		_camera.size = _zoom

	# Pan — WASD, speed proportional to zoom
	var move := Vector2(
		Input.get_axis("cam_pan_left", "cam_pan_right"),
		Input.get_axis("cam_pan_fwd",  "cam_pan_back")
	)
	if move.length_squared() > 0.0:
		var speed := _zoom * PAN_SPEED_SCALE * delta
		var fwd := -_pivot.global_transform.basis.z * move.y
		var rgt :=  _pivot.global_transform.basis.x * move.x
		position += (fwd + rgt) * speed

func _apply_swing_twist(delta: float) -> void:
	# Lerp current twist toward snapped target (shortest path in [0,1] space).
	var diff := fmod(_target_twist - _twist + 1.5, 1.0) - 0.5
	_twist = fmod(_twist + diff * clampf(LERP_SPEED * delta, 0.0, 1.0) + 1.0, 1.0)

	# Build orientation via swing-twist decomposition.
	# Both components expressed in [0, 1] of a full turn.
	#
	#   twist_q  : yaw around world Y  — _twist         in [0, 1]
	#   swing_q  : pitch around local X — SWING_ELEVATION in [0, 1]
	#
	# Multiplication order: twist_q * swing_q
	#   = apply swing first in local frame, then rotate that frame by twist.
	# This matches TransformUtil.swing_twist: twist axis is world Y;
	# swing is the perpendicular component in the twisted X-Z plane.
	var twist_q := Quaternion(Vector3.UP, _twist * TAU)
	var swing_q := Quaternion(Vector3.RIGHT, -SWING_ELEVATION * TAU)
	_pivot.quaternion = twist_q * swing_q

func _handle_follow(delta: float) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		_exit_follow()
		return
	position = position.lerp(_follow_target.global_position, clampf(FOLLOW_LERP * delta, 0.0, 1.0))
	# Twist is frozen — _apply_twist not called.

func _input(event: InputEvent) -> void:
	# Tab — toggle projection
	if event.is_action_pressed("cam_toggle_projection"):
		if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		else:
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL

	# F — enter Follow mode on nearest entity
	if event.is_action_pressed("cam_follow"):
		_enter_follow()

	# Escape — exit Follow mode
	if event.is_action_pressed("ui_cancel") and _mode == Mode.FOLLOW:
		_exit_follow()

func _enter_follow() -> void:
	if _entities == null:
		return
	var nearest: Node3D = null
	var best_sq := INF
	for child in _entities.get_children():
		var n := child as Node3D
		if n == null:
			continue
		var d := position.distance_squared_to(n.global_position)
		if d < best_sq:
			best_sq = d
			nearest = n
	if nearest == null:
		return
	_follow_target = nearest
	_mode = Mode.FOLLOW

func _exit_follow() -> void:
	_follow_target = null
	_mode = Mode.SURVEY

func _export_state_to_js() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"window.__camera_state = {mode:'%s',twist:%f,zoom:%f,projection:'%s'};" % [
			"survey" if _mode == Mode.SURVEY else "follow",
			_twist,
			_zoom,
			"orthographic" if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "perspective"
		]
	)
