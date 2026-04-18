# The Infinite Aquarium: A Social/UGC Bioluminescent Ocean

A social world and UGC platform. Players design bioluminescent jellyfish and release them into a shared neon ocean built from other players' creations. Comparable positioned titles: VRChat, Roblox, s&box.

---

## Demo Scope (two-hour target)

Fetch a player-uploaded jellyfish asset from Uro by hash, instance it inside the XR grid scene, and have it visible in VR.

1. `jellyfish_asset_loader.gd` resolves the Uro manifest (`/storage/:uuid/manifest`) and downloads the Godot scene + pulse waveform.
2. The loaded mesh is instanced into the existing xr-grid scene.
3. Player sees the UGC jellyfish appear in VR.

---

## Zone Infrastructure (implemented)

The Abyss is a persistent, zone-sharded ocean:

- Hilbert-coded zone boundaries for seamless cross-zone movement
- Distributed simulation via Multiplayer Fabric — each zone is a separate server process sharing entity state
- Area of Interest bands so players only receive data for nearby jellyfish
- Zone crossings are seamless; `MIGRATION_HEADROOM = 400` absorbs swarm spikes
- Performance target: 511+ jellyfish across a 3-zone loop without data loss

---

## UGC Asset Pipeline (Uro)

Every jellyfish is a content-addressed asset bundle in Uro. The bundle packs a Godot scene alongside a pulse waveform. Clients fetch by chunk hash at runtime and only download jellyfish within their AOI. The manifest endpoint resolves the full asset list in one round trip. Chunks are cached on disk so repeat visits cost no bandwidth. ReBAC permissions give creators control over who can remix or export their designs.

---

## Implementation Status

| Component        | Status      | Notes                                              |
| ---------------- | ----------- | -------------------------------------------------- |
| Zone networking  | Working     | fabric_zone.cpp                                    |
| Entity migration | Working     | SCENARIO_JELLYFISH_ZONE_CROSSING                   |
| Asset streaming  | In progress | jellyfish_asset_loader.gd → FabricMMOGAsset → Uro  |
| VR interface     | Testing     | xr-grid project                                    |

---

## Test Scenario: First Release

- Objective: fetch a jellyfish from Uro and instance it in the XR grid in VR
- Method: `jellyfish_asset_loader.gd` → Uro manifest → Godot scene → xr-grid scene
- Pass: jellyfish appears in the scene, visible to the player in VR
