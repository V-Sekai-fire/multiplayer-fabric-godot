# Todo

Items are sequenced by risk: each step retires one uncertainty before
the next begins.

## Next session punch list (execution order)

Use this as the immediate implementation queue before touching lower-risk
items. Each step is done only when its pass condition is met.

1. Observer HUD anchor fix
  Move `StatusHUD` under `SpectatorRig/SpringArm3D/Camera3D` and set
  offsets so text is readable at default camera distance.
  Pass: launching observer scene shows HUD text pinned to camera and
  readable while orbiting.

2. Observer position marker
  Add a simple pulsing mesh marker at observer world position and ensure
  it updates every frame from authoritative zone position.
  Pass: marker remains visible during camera motion and crosses zone
  boundaries without lagging behind the observer.

3. Zone curtain readability pass
  Raise curtain alpha and add either camera-facing labels or duplicated
  vertical labels so zone names are readable from top-down and orbit.
  Pass: all three zone labels are readable from default spawn view and
  boundary surfaces remain visible at far zoom.

4. Top-down debug camera default
  Add orthographic top-down mode as startup default, keep orbit mode as
  a toggle path, and preserve current controls.
  Pass: boot opens in top-down mode; toggle switches cleanly between
  top-down and orbit with no control lockups.

5. Burst migration smoke run
  Run the 3-zone observer smoke test and capture one screenshot in both
  top-down and orbit modes during the 144-entity crossing burst.
  Pass: no mass rollback, no duplicate flood, and screenshots clearly
  show entities crossing zone boundaries.

6. Minimal regression guard
  Add a short runbook block in this file documenting exact scene,
  command, and expected visual checks for repeating the smoke run.
  Pass: another contributor can execute the runbook without guessing
  hidden setup steps.

## Fix observer overlays so you can tell what is happening

Previous test session: zone boundaries were hard to read, the observer
position was invisible, and the status HUD was unreadable from the
spectator camera. Known problems in `observer.tscn`:

- **StatusHUD is at world origin `(0, 6, 0)`**, not parented to the
  camera. The spectator orbits at 30-80 m — the HUD is a distant speck.
  Fix: reparent StatusHUD under `SpectatorRig/SpringArm3D/Camera3D` so
  it follows the viewport.
- **No observer position marker.** There is nothing showing where "you"
  are in the world. Add a pulsing sphere or crosshair at the observer's
  connected zone position so you can see yourself relative to the zone
  curtains.
- **Zone labels are flat on the ground** (`rotation_degrees.x = -90`
  in `zone_curtain.gd:54`). From the spectator camera's oblique angle
  they are foreshortened and hard to read. Either billboard them toward
  the camera or duplicate them on vertical faces of the curtain.
- **Zone curtain colors are very transparent** (`alpha = 0.18`). From
  far away the boundaries vanish. Consider raising alpha or adding a
  wireframe outline pass.

**Risk retired:** you can see zone boundaries, your position, and
status text during the smoke test.

## Add a top-down bird's eye development camera

The current spectator camera orbits at an oblique angle making it hard
to see zone boundaries and entity movement. Add an orthographic
top-down camera mode (like a Final Fantasy Tactics overworld view) as
the default development view. The camera looks straight down at the
`SIM_BOUND` area, zone curtains are visible as colored region borders,
entities are dots, and the observer position is a highlighted marker.
This makes zone assignment, migration flow, and entity clustering
immediately legible without VR hardware.

Toggle between top-down and orbit modes with a key (e.g. Tab) so
both views remain available. The top-down view is the primary
development and debugging tool; the orbit view is for visual polish.

**Risk retired:** developers can observe zone state, migration, and
entity distribution at a glance without a headset.

## Smoke-test the demo (top-down first, then headset)

Boot with three zone servers (the minimum for testing transitive
migration: zone 0 → 1 → 2 exercises both neighbor indices). Two zones
only test one boundary; three zones prove the neighbor-index logic for
both `ni=0` (lower) and `ni=1` (upper). The observer scene already
defaults to `zone_count = 3`.

First confirm in the top-down view (no headset needed): zone curtains
visible, entities populate all three zones, 144-entity burst migrates
without mass rollback. Then put on the headset and confirm VR
rendering, head tracking, and hand tracking update in CH_INTEREST.

Three populations stress-test different failure modes:

| Population | IDs | What it tests |
|---|---|---|
| `jellyfish_bloom_concert` | 0--255 | Dense crowd at the origin. Players appear alongside NPCs in CH_INTEREST — the concert scenario where everyone sees everyone. |
| `jellyfish_zone_crossing` | 256--399 | 144 entities burst across a zone boundary simultaneously. This is the worst-case migration spike. |
| `whale_with_sharks` | 400--511 | 8 pods of 14 at cruising speed. Tests sustained cross-zone movement, not just a spike. |

Pass condition: an observer in Zone B receives all 144 burst entities
from Zone A without snap, duplicate, or loss. The Predictive BVH
projects ghost AABBs forward using per-segment velocity so the
receiving zone pre-allocates slots before the burst finishes arriving.
`MIGRATION_HEADROOM` (defined in `fabric_zone.h`) absorbs the spike.

**Risk retired:** the demo boots and renders after all recent code
changes (RTT timeout, static extraction, CSG fix).

## Instance the procedural grid into the demo

The xr-grid addon (`thirdparty/xr-grid/addons/procedural_3d_grid/`)
provides `procedural_grid_3d.gd` (infinite multi-level grid that
scales with the XR origin) and its base mesh scene. Instance the
`ProceduralGrid3D` node under `XROrigin3D` in `main.tscn` so the
player has spatial reference in the void. Wire `FOCUS_NODE` to the
headset camera.

The xr-grid scripts live under `thirdparty/xr-grid/addons/`. Windows
Steam PCVR cannot use symlinks (requires admin privileges and NTFS
developer mode). Copy the needed scripts into the demo directory or
reference them via `res://` paths that the export preset remaps. Do
not assume symlinks work on the target platform.

**Risk retired:** the player has a visible ground plane and scale
reference in VR.

## Wire WorldGrab navigation

The xr-grid addon provides `world_grab.gd` (`WorldGrab` RefCounted)
and `xr_pinch.gd` (`XRPinch`). Instance `XRPinch` on each
`XRController3D` hand node in `main.tscn`. WorldGrab lets the player
grab the world with both hands and move, rotate, and scale it —
the primary navigation method for an art-viewing VR experience.

Same symlink caveat as item 2: copy or remap, do not symlink.

**Risk retired:** the player can navigate the world in VR without
teleport or joystick; two-hand grab is the only input method the
demo needs.

## Verify XR node tree in main.tscn

Confirm `WorldGrab`, `XRPinch`, `ProceduralGrid3D`, and
`trident_hand.gd` are all instanced and functional under the
`XROrigin3D` node. If nodes are missing or disconnected, wire them.

**Risk retired:** VR scene graph is complete; input reaches scripts.

## Wire trident trigger to CH_PLAYER cmd=1

`trident_hand.gd` is a cosmetic CSG mesh. Wire the XR controller
trigger to emit a CH_PLAYER cmd=1 (`current_funnel`) packet from
`fabric_client.gd`. The server-side handler in `fabric_zone.cpp:1494`
already injects the C7 velocity spike — only the client send path is
missing.

**Risk retired:** player input reaches the zone simulation.

## End-to-end trident test

Trident trigger in PCVR produces a C7 spike visible in Zone B's
interest range at `CURRENT_FUNNEL_PEAK_V` without a false negative.
First test that exercises the full client, zone, observer path through
CH_PLAYER and CH_INTEREST.

**Risk retired:** the wire format carries player commands faithfully
across zones.

## Wire pen tool to CH_PLAYER cmd=3

`fabric_client.gd` should emit a CH_PLAYER cmd=3 packet for each
stroke knot written by the pen tool. The server-side handler route
mirrors the trident cmd=1 path. Wire the XR controller input event
to the send call and verify knots appear in the observer's
CH_INTEREST stream. Bibliography:
`thirdparty/predictive_bvh/OptimalPartitionBook.md`.

**Risk retired:** the full client-to-zone-to-observer path through
CH_PLAYER and CH_INTEREST is exercised by both weapon and pen input.

## Build 100-peer load-test harness

Write a headless driver that spawns 100 `FabricPeer` connections to a
single zone server and subscribes each to `CH_INTEREST`. The driver
records the timestamp of every broadcast packet received. No analysis
yet — just get 100 peers connected and logging.

**Risk retired:** the test infrastructure exists and can be run
repeatably without VR hardware.

## Measure CH_INTEREST fan-out latency at 100 peers

Run the harness built in the previous step. Record p50/p99 fan-out
latency for `local_broadcast_raw` at 100 simultaneous subscribers per
zone. Validates that the Hilbert AOI band and one-copy-per-link relay
scale to the concert scenario before adding more zones.

**Risk retired:** per-zone fan-out is bounded and measurable before
scaling to multiple zones.

## Add content-addressed chunk store to Uro

Add a `/chunks/:hash` endpoint to Uro that accepts PUT (upload) and
GET (fetch) for binary blobs. Store blobs keyed by their BLAKE3 hash.
No permissions yet — accept all authenticated requests. This is the
storage primitive that the next three steps build on.

**Risk retired:** Uro can store and return arbitrary content-addressed
chunks; the hash round-trip is verified.

## Enforce ReBAC permissions on Uro chunk fetch

Add a ReBAC policy check to the `GET /chunks/:hash` handler: the
requesting principal must hold a `can_read` relation on the chunk's
namespace. Reject with 403 otherwise. Operators assign namespaces at
upload time.

**Risk retired:** operators control who can fetch which assets; the
data-sovereignty claim is enforced, not aspirational.

## Implement client-side chunk streaming by hash

In the Godot client, replace the baked-in asset bundle load with
a runtime fetch: given a chunk hash, issue an authenticated GET to
the Uro `/chunks/:hash` endpoint and deserialize the result. Cache
fetched chunks on disk by hash to avoid redundant downloads.

**Risk retired:** the client can load world assets at runtime without
a bundled export.

## End-to-end asset streaming integration test

Upload a test chunk from the demo scene to a local Uro instance, then
boot the client cold (empty cache) and confirm it fetches and renders
the chunk by hash. Test both the happy path and a 403 rejection with
an unauthorized principal.

**Risk retired:** asset streaming works end-to-end through Uro; the
client fetches chunks by hash at runtime.

## Audit existing Lean proofs and sketch headroom theorem

Read `ghost_containment_implies_no_exit` and
`staging_resolves_to_single_owner` in
`PredictiveBVH/Spatial/HilbertRoundtrip.lean`. Identify the exact
lemmas the new theorem will depend on. Write the statement:
`MIGRATION_HEADROOM ≥ MAX_BURST_SIZE` and confirm the constant
values in `fabric_zone.h` are visible to the Lean build.

**Risk retired:** the theorem is stated correctly and its dependencies
are known before any proof attempt.

## Write and verify the headroom ≥ burst size Lean theorem

Implement the theorem sketched in the previous step. The proof should
reduce to a `decide` or `norm_num` call once the constants are in
scope. Run `lake build` and confirm no sorry placeholders remain.

**Risk retired:** the burst absorption claim in the concept doc is
formally verified, not just tested.

## Verify entity-tight parentBounds RDO quality

`lbvhAux` now sets `parentBounds` to the entity-tight union instead
of the old Morton octree cell. `evalNodeCost?` uses
`surfaceArea(parentBounds)` for RDO cost, so this change affects every
split decision. Run the BVH builder on all three Abyssal VR Grid
populations and confirm total SAH cost is ≤ the Morton baseline.

**Risk retired:** entity-tight bounds do not regress BVH quality.

## Validate centroid axis selection heuristic

The initial split axis is now picked by max child centroid separation
instead of `depth % 3`. Instrument `lbvhAux` to log the chosen axis
for each node. Run on `jellyfish_bloom_concert` and `whale_with_sharks`
and confirm the heuristic distributes axes sensibly (not always `.horz`
or degenerate on flat populations).

**Risk retired:** the centroid axis heuristic picks useful splits on
real entity distributions.

## Confirm saturator convergence on demo populations

`saturateAxes` tries `.horz`, `.vert`, and `.depth` for each 2-way
node and keeps the cheapest. Run it on all three populations and
verify: (a) it converges in ≤ 3 passes, and (b) it finds a cheaper
partition than the initial LBVH on at least some subtrees.

**Risk retired:** the Hilbert-sorted BVH produces correct and
competitive RDO cost with the full entity-tight + AV1 partition model.

## ~~Add UDS zone-to-zone transport~~ DEFERRED

Add `FabricLocalZonePeer` via `UDSServer`/`StreamPeerUDS` as an
opt-in alternative to ENet for same-machine zone-to-zone traffic.
ENet remains the default and stays for zone-to-player. Gated by
`#ifdef UNIX_ENABLED`. The RTT-derived adaptive timeout already
fixes the 144-entity burst under ENet fragmentation. UDS removes
fragmentation overhead entirely but is only relevant for same-machine
deployments — unnecessary mass until fan-out measurement (item 7)
shows ENet is the bottleneck.

## ~~Editor zone visualizer~~ DEFERRED

Hilbert band overlay, entity count per zone, migration arrows in the
3D viewport. Unnecessary mass before the VR smoke test passes (item 1).
Revisit if debugging items 5+ becomes painful without visualization.

## ~~Editor multiplayer_fabric awareness~~ DEFERRED

Making the editor understand zones, migration state, or CH_INTEREST
routing. The demo runs headless zone servers plus a PCVR client; the
editor does not participate in the fabric. Godot's existing "Run
Multiple Instances" covers the multi-process case. Adding editor
integration is maintenance surface area that breaks across Godot
versions and solves no current risk.

## Provision 5-machine fabric (32 zones)

Sizing: 1,000 players × 56 entities = 56,000 entities; at 1,800 per
zone → 32 zones; 7 zones per 8-core machine → 5 machines, 63,000
capacity, 1,125 players at 12.5% headroom. Provision the machines,
deploy zone binaries, confirm all 32 zones register with each other
and show healthy in the observer.

**Risk retired:** the full fabric topology is live and observable
before load is applied.

## Run 1,000-player load test and record headroom

Drive 1,000 simulated clients against the 32-zone fabric. Record peak
entity count per zone, p99 migration latency, and headroom margin.
Pass condition: no zone exceeds 1,800 entities and headroom stays
above 12.5% throughout the run.

**Risk retired:** the full stack holds under production-scale load.
