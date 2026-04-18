# The Infinite Aquarium: A Social/UGC Bioluminescent Ocean

The Infinite Aquarium is a social world and UGC platform. Players design their own bioluminescent jellyfish and release them into a shared neon ocean built from other players' creations. The goal is to make something beautiful and watch it swim alongside everyone else's. Comparable positioned titles: VRChat, Roblox, s&box (Garry's Mod successor).

---

## The Core Loop

1. Create: use in-world tools to design a jellyfish (body shape, color palette, tentacle pattern, bioluminescent pulse rhythm).
2. Release: send it into the Abyss, where it joins the ocean shared by all players.
3. Explore: swim through zones populated by other players' creations. No two visits look the same.
4. Remix: pick up another player's jellyfish as a template and iterate on it.

The ocean has no score and no failure state. The content is what players build and leave behind.

---

## System Architecture

The Abyss is a persistent, zone-sharded ocean built on:

- Hilbert-coded zone boundaries for seamless cross-zone movement
- Distributed simulation handling thousands of player-uploaded jellyfish simultaneously
- Uro content-addressed store for all player-created assets (meshes, shaders, pulse scripts)
- Godot-sandbox (RISC-V ELF) for safe execution of per-jellyfish behavior scripts
- VR-first interface with flat-screen fallback
- Self-hostable: operators can run private Abyss instances with their own communities

---

## Core Components

### 1. The Jellyfish Creator

Players build jellyfish entirely in-world, with no external tools required. The creator has four parts:

- Body sculptor: CSG-based bell shape with sliders for radius, flare, and dome height
- Tentacle editor: count, length, curl, and trailing-fin arrangement
- Bioluminescent painter: per-region color, emission intensity, and pulse waveform (sine, strobe, heartbeat, ripple)
- Behavior script: sandboxed ELF program (compiled from C++ or Rust) controlling swim pattern, flock response, and light sync

Every jellyfish carries its creator's name and release timestamp.

### 2. The Abyss (Zone Infrastructure)

The shared ocean divides into Hilbert-coded zones. Each zone runs as a separate server process, sharing entity state via Multiplayer Fabric, and uses Area of Interest bands so players only receive data for nearby jellyfish. Zone crossings are seamless; `MIGRATION_HEADROOM = 400` absorbs swarm spikes. Performance target: 511+ jellyfish across a 3-zone loop without data loss.

### 3. UGC Asset Pipeline (Uro)

Every player-created jellyfish is a content-addressed asset bundle stored in Uro. The bundle packs a `.glb` mesh and material alongside a sandboxed behavior ELF and pulse waveform data. Clients fetch by chunk hash at runtime and only download jellyfish within their AOI. The manifest endpoint (`/storage/:uuid/manifest`) resolves the full asset list in one round trip. Chunks are cached on disk, so repeat visits to a familiar zone cost no bandwidth. ReBAC permissions give creators control over who can remix or export their designs.

### 4. Sandboxed Behavior Scripts

Each jellyfish carries an optional sandboxed program (RISC-V ELF via godot-sandbox) that controls swim path, flock attraction/repulsion, and responses to nearby jellyfish. The program runs isolated from the host with no filesystem or network access. Uploading a new script version via Uro reloads live instances without a zone restart. Shared sim headers (`jellygrid_swarm_sim.hpp`) expose the physics primitives scripts can call.

### 5. Environmental Layer

The Abyss has ambient physics keeping every zone active:

- Currents: slow, wide drift patterns that carry jellyfish between zones organically
- Rip events: occasional surge currents that scatter swarms and produce dramatic visual moments
- Depth lighting: deeper zones are darker; bioluminescence is the only light source below the thermocline
- Bloom dynamics: jellyfish that go unobserved for 30 seconds fade out, self-pruning the ocean

---

## UGC Moderation

Behavior scripts run in godot-sandbox, so resource exhaustion is bounded by the host. Mesh and texture assets are scanned at upload time via Uro's ACL layer. Creators can flag remixes; operators can tombstone an asset hash across the entire content store. Players can favorite jellyfish, surfacing popular designs in the spawn pool.

---

## Implementation Status

| Component             | Status      | Implementation Notes                                       |
| --------------------- | ----------- | ---------------------------------------------------------- |
| Zone networking       | Working     | fabric_zone.cpp                                            |
| Entity migration      | Working     | SCENARIO_JELLYFISH_ZONE_CROSSING                           |
| VR interface          | Testing     | Hand-based current placement                               |
| Asset streaming       | In progress | jellyfish_asset_loader.gd -> FabricMMOGAsset -> uro manifest |
| Swarm physics         | Sandbox     | sandbox/jellygrid_swarm.cpp (ELF guest program)            |
| Current routing       | Sandbox     | sandbox/jellygrid_current.cpp (ELF guest program)          |
| Power/pulse sim       | Sandbox     | sandbox/jellygrid_power_node.cpp (ELF guest program)       |
| Jellyfish creator UI  | Not started | In-world CSG sculptor + pulse editor                       |
| Behavior script tools | Not started | In-world Rust/C++ compiler -> ELF upload                   |
| Remix system          | Not started | Clone asset bundle, fork provenance chain                  |
| Moderation layer      | Not started | Uro ACL + operator tombstone endpoint                      |
| Current visuals       | Not started | Procedural generation                                      |

---

## Test Scenarios

### 1. First Release

- Objective: A new player designs and releases a jellyfish in under 10 minutes
- Method: Creator UI -> Uro upload -> spawn into live zone
- Pass: jellyfish appears in the Abyss, visible to other players in the same zone

### 2. Crowded Abyss

- Objective: 1,000 player-uploaded jellyfish coexist in a 3-zone ocean
- Method: 1,000-entity stress run with varied behavior scripts
- Pass: no zone exceeds CPU budget; AOI streaming keeps per-client bandwidth under target

### 3. Cross-Zone Bloom

- Objective: 144 jellyfish migrate from Zone A to Zone B simultaneously
- Method: choke_point population burst (entity IDs 256-399)
- Pass: no snap, no duplicate, no loss; receiving zone pre-allocates via Predictive BVH

### 4. Remix Chain

- Objective: Player B remixes Player A's jellyfish; provenance reflects both creators
- Method: clone asset bundle, edit pulse waveform, re-upload to Uro
- Pass: new UUID registered, original creator attributed, ReBAC relation updated

### 5. Moderation Tombstone

- Objective: Operator removes a flagged asset from all zones instantly
- Method: tombstone chunk hash in Uro; running instances receive eviction signal
- Pass: jellyfish disappears from all active zones within one AOI broadcast cycle

---

## Reference Documents

- CONCEPT_MMOG_SPONSORS.md -- sponsorship and operator tiers
- CONCEPT_MMOG_ZONES.md -- zone architecture details
- TODO_MMOG.md -- sequenced implementation queue
- Uro streaming integration
