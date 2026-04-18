# The Infinite Aquarium: A Social/UGC Bioluminescent Ocean

A social world and UGC platform. Players design bioluminescent jellyfish and release them into a shared neon ocean built from other players' creations. Comparable positioned titles: VRChat, Roblox, s&box.

---

## Demo Scope (two-hour target)

Fetch a player-uploaded jellyfish asset from Uro by hash, instance it inside the XR grid scene, and have it visible in VR.

1. `jellyfish_asset_loader.gd` resolves the Uro manifest (`/storage/:uuid/manifest`) and downloads the Godot scene.
2. The loaded scene is instanced into the existing xr-grid scene.
3. Player sees the UGC jellyfish appear in VR.
4. Jellyfish bobs and drifts via a GDScript float controller — sine-wave vertical bob, slow random horizontal drift, spring return toward spawn origin.

---

## Zone Infrastructure (implemented)

The Abyss is a persistent, zone-sharded ocean:

- Hilbert-coded zone boundaries for seamless cross-zone movement
- Distributed simulation via Multiplayer Fabric — each zone is a separate server process sharing entity state
- Area of Interest bands so players only receive data for nearby jellyfish
- Zone crossings are seamless; `MIGRATION_HEADROOM = 400` absorbs swarm spikes
- Performance target: 511+ jellyfish across a 3-zone loop without data loss

---

## Jellyfish Creator

Because the asset format is a Godot scene, the creation workflow is:

1. Design with CSG nodes (bell body, tentacle sweeps) directly in the Godot editor or an in-world editor scene.
2. Bake CSG to a static mesh (`CSGShape3D.bake_mesh()`).
3. Save the baked mesh scene to Uro — the content-addressed store assigns a chunk hash.

No external DCC tools required. The baked scene is the canonical asset; clients instance it directly at runtime.

---

## UGC Asset Pipeline (Uro)

Every jellyfish is a content-addressed asset bundle in Uro. The bundle packs a baked Godot mesh scene. Clients fetch by chunk hash at runtime and only download jellyfish within their AOI. The manifest endpoint resolves the full asset list in one round trip. Chunks are cached on disk so repeat visits cost no bandwidth.

---

## Implementation Status

| Component          | Status      | Notes                                             |
| ------------------ | ----------- | ------------------------------------------------- |
| Zone networking    | Working     | fabric_zone.cpp                                   |
| Entity migration   | Working     | SCENARIO_JELLYFISH_ZONE_CROSSING                  |
| Jellyfish creator  | In scope    | CSG design → bake mesh → save Godot scene → Uro   |
| Asset streaming    | In progress | jellyfish_asset_loader.gd → FabricMMOGAsset → Uro |
| VR interface       | Testing     | xr-grid project                                   |
| ReBAC permissions  | Working     | Uro.Acl — creator remix/export control            |
| Float/drift        | In scope    | GDScript: sine-wave bob + slow drift + return-to-origin |
| Behavior scripts   | ~~Tombstoned~~ | godot-sandbox / RISC-V ELF — not in scope      |
| HTN planning       | ~~Tombstoned~~ | taskweft — not in scope                        |
| Swarm physics      | ~~Tombstoned~~ | jellygrid_swarm.cpp sandbox program            |
| Current simulation | ~~Tombstoned~~ | jellygrid_current.cpp sandbox program          |
| Pulse waveform     | ~~Tombstoned~~ | dropped from asset bundle for now              |
| Remix system       | ~~Tombstoned~~ | clone + fork provenance chain                  |
| Moderation layer   | ~~Tombstoned~~ | Uro ACL + operator tombstone endpoint          |
| Environmental FX   | ~~Tombstoned~~ | currents, rip events, bloom dynamics           |

---

## Test Scenario: First Release

- Objective: fetch a jellyfish from Uro and instance it in the XR grid in VR
- Method: `jellyfish_asset_loader.gd` → Uro manifest → Godot scene → xr-grid scene
- Pass: jellyfish appears in the scene, visible to the player in VR
