extends SceneTree

var _frames: int = 0
var client: Node = null

func _init() -> void:
    print("[HeadlessObserver] Initializing headless diagnostic observer...")

    # We must instantiate FabricClient directly to bypass the faulty observer.tscn
    client = preload("res://scripts/fabric_client.gd").new()
    client.zone_host = "127.0.0.1"
    client.zone_port = 17500
    root.add_child(client)

    process_frame.connect(_on_frame)

func _on_frame() -> void:
    _frames += 1
    if _frames % 60 == 0:
        print("\n--- [HeadlessObserver Diagnostic @ Frame ", _frames, "] ---")
        if client:
            var status = client._peer.get_connection_status() if client.get("_peer") else -1
            print("Client status (0:Disconnected, 1:Connecting, 2:Connected): ", status)
            if "_entity_nodes" in client:
                var ents = client.get("_entity_nodes")
                print("Total Entities Tracked (Visuals): ", ents.size())
                var keys = ents.keys()
                keys.sort()
                for i in range(min(15, keys.size())):
                    var k = keys[i]
                    var node = ents[k]
                    if is_instance_valid(node):
                        print("  > Entity ID: ", k, " | Pos: ", node.global_position)
                    else:
                        print("  > Entity ID: ", k, " | Node Invalid (Queue Freed?)")
        else:
            print("Client node not found.")

    if _frames >= 600:
        print("[HeadlessObserver] Diagnostic complete. Shutdown.")
        quit(0)
