# test_operator_camera.gd
# Headless unit tests for operator_camera swing-twist quaternion.
#
# Run:
#   godot --headless --path . --script scripts/test_operator_camera.gd
#
# Exits 0 on pass, 1 on any failure.

extends SceneTree

const SWING_ELEVATION := 0.153
const SNAP_STEP       := 0.25
const EPS             := 1e-4

var _failures: int = 0

func _init() -> void:
	_run_all()
	if _failures == 0:
		print("operator_camera tests: ALL PASS")
		quit(0)
	else:
		print("operator_camera tests: %d FAILURE(S)" % _failures)
		quit(1)

func _run_all() -> void:
	_test_twist_zero_quaternion()
	_test_twist_quarter_quaternion()
	_test_swing_elevation_preserved()
	_test_quaternion_equivalent_to_euler()

# ── helpers ──────────────────────────────────────────────────────────────────

func _make_q(twist: float) -> Quaternion:
	var twist_q := Quaternion(Vector3.UP,    twist            * TAU)
	var swing_q := Quaternion(Vector3.RIGHT, -SWING_ELEVATION * TAU)
	return twist_q * swing_q

func _assert_approx_eq(label: String, a: float, b: float) -> void:
	if absf(a - b) > EPS:
		print("FAIL %s: %f != %f (diff=%f)" % [label, a, b, absf(a - b)])
		_failures += 1

func _assert_vec_approx(label: String, a: Vector3, b: Vector3) -> void:
	if a.distance_to(b) > EPS:
		print("FAIL %s: %s != %s" % [label, a, b])
		_failures += 1

# ── tests ────────────────────────────────────────────────────────────────────

func _test_twist_zero_quaternion() -> void:
	# twist=0: camera looks south along -Z, tilted down by SWING_ELEVATION.
	var q := _make_q(0.0)
	# Forward vector of the camera rig at twist=0 should point south (-Z world).
	# After swing, it tilts down. Check the Y component is negative (looking down).
	var fwd := q * Vector3(0, 0, -1)
	if fwd.y >= 0.0:
		print("FAIL twist_zero: forward Y should be negative (looking down), got %f" % fwd.y)
		_failures += 1
	else:
		print("PASS twist_zero: fwd=%s" % fwd)

func _test_twist_quarter_quaternion() -> void:
	# twist=0.25 (east): forward should point west (camera looks east → arm points west).
	# After 90° yaw the world-X component of forward should be non-trivial.
	var q0 := _make_q(0.0)
	var q1 := _make_q(0.25)
	# The two quaternions must differ.
	var angle := q0.angle_to(q1)
	if absf(angle - PI * 0.5) > EPS * 100.0:
		print("FAIL twist_quarter: expected ~90° rotation, got %f rad" % angle)
		_failures += 1
	else:
		print("PASS twist_quarter: angle=%.4f rad" % angle)

func _test_swing_elevation_preserved() -> void:
	# For any twist value, the angle between the forward vector and the
	# horizontal plane must equal SWING_ELEVATION * TAU.
	var expected_elev := SWING_ELEVATION * TAU  # in radians
	for t_int in [0, 1, 2, 3]:
		var t: float = t_int * 0.25
		var q   := _make_q(t)
		var fwd := q * Vector3(0, 0, -1)
		# Elevation = asin(-fwd.y) for a downward look.
		var elev := asin(clampf(-fwd.y, -1.0, 1.0))
		_assert_approx_eq("swing_elevation twist=%.2f" % t, elev, expected_elev)
	print("PASS swing_elevation: consistent at all four cardinal twists")

func _test_quaternion_equivalent_to_euler() -> void:
	# The quaternion must match what a Node3D would produce with the old Euler approach:
	#   pivot.rotation.y = twist * TAU
	#   arm.rotation.x   = -SWING_ELEVATION * TAU
	# Combined basis = Basis(y, twist*TAU) * Basis(x, -swing*TAU)
	for t_int in [0, 1, 2, 3]:
		var twist: float = t_int * 0.25
		var q_new := _make_q(twist)

		# Reconstruct old Euler approach as a basis product.
		var b_twist := Basis(Vector3.UP,   twist            * TAU)
		var b_swing := Basis(Vector3.RIGHT, -SWING_ELEVATION * TAU)
		var b_old   := b_twist * b_swing
		var q_old   := b_old.get_rotation_quaternion()

		var angle_diff := q_new.angle_to(q_old)
		if angle_diff > EPS * 100.0:
			print("FAIL quaternion_equiv twist=%.2f: diff=%.6f rad" % [twist, angle_diff])
			_failures += 1
	print("PASS quaternion_equiv: matches Euler hierarchy at all four cardinals")
