extends Node
# WebTransport client for browser/Playwright end-to-end testing.
# Attach to a Node in the main scene. Connects to echo server, sends a
# datagram, verifies the echo. Writes JSON beacons to window.__wt_beacons.

const MSG := "Hello Godot WebTransport"
const TIMEOUT_MS := 10000

var peer: WebTransportPeer
var host := "127.0.0.1"
var port := 54370
var path := "/wt"
var sent := false
var t0 := 0

func _ready() -> void:
	if OS.has_feature("web"):
		host = str(JavaScriptBridge.eval("window.WT_HOST || '127.0.0.1'"))
		port = int(JavaScriptBridge.eval("window.WT_PORT || 54370"))
	else:
		host = OS.get_environment("WT_HOST") if OS.get_environment("WT_HOST") != "" else host
		var env_port := OS.get_environment("WT_PORT")
		if env_port != "":
			port = int(env_port)

	_beacon({"event": "init", "host": host, "port": port})

	peer = WebTransportPeer.new()
	var err := peer.create_client(host, port, path)
	if err != OK:
		_beacon({"event": "fail", "reason": "create_client error %d" % err})
		get_tree().quit(1)
		return
	t0 = Time.get_ticks_msec()
	_beacon({"event": "connecting"})

func _process(_delta: float) -> void:
	if not peer:
		return
	peer.poll()

	if Time.get_ticks_msec() - t0 > TIMEOUT_MS:
		_beacon({"event": "fail", "reason": "timeout"})
		get_tree().quit(1)
		return

	var state := peer.get_connection_status()

	if state == MultiplayerPeer.CONNECTION_CONNECTED and not sent:
		sent = true
		peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		peer.put_packet(MSG.to_utf8_buffer())
		_beacon({"event": "sent", "msg": MSG})

	if state == MultiplayerPeer.CONNECTION_CONNECTED and sent:
		while peer.get_available_packet_count() > 0:
			var echo := peer.get_packet().get_string_from_utf8()
			if echo == MSG:
				_beacon({"event": "pass", "echo": echo})
				peer.close()
				get_tree().quit(0)
			else:
				_beacon({"event": "fail", "reason": "echo mismatch", "got": echo})
				peer.close()
				get_tree().quit(1)

	if state == MultiplayerPeer.CONNECTION_DISCONNECTED and sent:
		_beacon({"event": "fail", "reason": "disconnected before echo"})
		get_tree().quit(1)

func _beacon(data: Dictionary) -> void:
	var json := JSON.stringify(data)
	print(json)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"window.__wt_beacons = window.__wt_beacons || []; window.__wt_beacons.push(%s)" % json
		)
