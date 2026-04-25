# fabric_player_xr.gd
# Attach to XROrigin3D in observer.tscn.
# Initialises OpenXR when a headset is present; falls back silently for
# desktop operators so the scene works without XR hardware.

extends XROrigin3D


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.initialize():
		return
	get_viewport().use_xr = true
	print("FabricPlayerXR: OpenXR initialised")
