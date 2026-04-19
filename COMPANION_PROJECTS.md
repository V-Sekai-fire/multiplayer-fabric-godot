# Companion Projects

Shared reference for all fabric-related modules and vendored projects.
When making non-trivial changes to any of these, check the matching code
in the others — they are upstream providers, downstream consumers, and
the source of the numbers the fabric stack is specialized for.

A change to anything externally observable — wire format, command set,
URO paths, chunk parameters, asset-delivery sequence — is not complete
until the corresponding change has landed in the relevant companion
project below. Prefer a single PR per companion over a chain of partial
updates.

## What you can do right now

The following end-to-end paths are working on `main` or in open PRs:

| Capability | Status | How |
|---|---|---|
| Fetch jellyfish from Uro by hash | **Working** | `GET /storage/:id`, `POST /storage/:id/manifest` |
| Instance UGC scene in xr-grid VR | **Testing** | `jellyfish_asset_loader.gd` → `FabricMMOGAsset` |
| Start/stop zone servers from TUI | **Working** | `zone_console` mix task (PR #7 merged) |
| View OTel traces from Uro server | **Working** | LiveDashboard `/dev/dashboard` → Traces page (PR #9 merged) |
| View OTel traces from Godot editor/zone | **Open PR #13** | `modules/open_telemetry` → console or `localhost:4318` |
| Persist entity state at spawn/despawn | **Open PR #12** | `GET/PUT /entities/:global_id`, `POST /entities/:global_id/teleport` |
| ReBAC asset access control | **Working** | `POST /acl/check` |
| CockroachDB TLS auth | **Working** | `mix uro.crdb_gen_certs` (PR #8 merged) |
| Zone-to-zone entity migration | **Working** | `SCENARIO_JELLYFISH_ZONE_CROSSING` in `fabric_zone.cpp` |
| 511+ jellyfish across 3-zone loop | **Working** | `MIGRATION_HEADROOM = 400` |

Two-hour demo path: zone_console start → jellyfish_asset_loader fetches from Uro → scene instanced in xr-grid → visible in VR.

---

## Modules

### [`modules/multiplayer_fabric`](modules/multiplayer_fabric) — zone transport layer

The lower networking layer. Zone architecture, Hilbert code assignment,
AOI bands, migration protocol, and `FabricMultiplayerPeer` channel
routing all live here. Wire channel constants and entity slot layout
must stay in sync with the MMOG layer above.

### [`modules/multiplayer_fabric_mmog`](modules/multiplayer_fabric_mmog) — MMOG layer

Adds the 100-byte wire format, entity class tags, humanoid bone sync,
asset delivery via desync chunk stores, and ReBAC permissions on top of
the zone transport. Wire format byte offsets in `fabric_zone.h` and
channel constants in `fabric_multiplayer_peer.h` must stay in sync with
the MMOG peer and asset code.

### [`modules/open_telemetry`](modules/open_telemetry) — GDScript OTel module

Cherry-picked from `vsk-otel-4.6`. Provides `OpenTelemetry`,
`OpenTelemetryTracerProvider`, and the `OTel*` structure classes for
distributed tracing from GDScript and C++. In editor builds the default
sink is the Godot output console (`print_verbose`); override
`opentelemetry/editor_endpoint` in Project Settings to forward to a
local OTLP collector. Exported zone builds read `opentelemetry/enabled`
and `opentelemetry/endpoint` from `project.godot`. The `abyssal_vr`
demo project has these set to `enabled=true, endpoint="console"`. See
open PR #13.

### [`modules/keychain`](modules/keychain) — OS secure storage

Platform-gated module (all platforms except web) wrapping
`thirdparty/keychain/` for persisting per-asset AES key material. The
MMOG layer's `fabric_mmog_asset.cpp` guards keystore calls behind
`MODULE_KEYCHAIN_ENABLED` so it builds on platforms without secure
storage.

### [`modules/speech`](modules/speech) — voice chat

Upstream: <https://github.com/V-Sekai/godot-speech>

Speech processor and Opus compressor module. Provides real-time voice
transport that runs alongside the fabric zone channels. Voice packets
travel over the Godot high-level multiplayer (CH_SYSTEM, channel 0),
not the fabric-specific wire channels, so the two systems are
independent at the wire level but share the same `ENetConnection`.

### [`modules/sandbox`](modules/sandbox) — RISC-V sandbox

Upstream: <https://github.com/libriscv/godot-sandbox>

Sandboxed execution of untrusted GDScript/C++ via a RISC-V emulator.
Used by the V-Sekai client to run user-uploaded scripts safely. No
direct dependency on the fabric stack, but ships in the same binary.

---

## Vendored thirdparty

### [`thirdparty/predictive_bvh`](thirdparty/predictive_bvh) — Lean 4 proofs and codegen

Formal verification of the broadphase, ghost expansion, migration
protocol, and zone assignment. Constants like `PBVH_V_MAX_PHYSICAL_DEFAULT`,
`PBVH_INTEREST_RADIUS_UM`, and `PBVH_LATENCY_TICKS` flow from Lean
through `predictive_bvh.h` into `multiplayer_fabric` and then into the
MMOG layer's wire encoding scales. `predictive_bvh.h` is generated —
never hand-edit. Full bibliography in
`thirdparty/predictive_bvh/OptimalPartitionBook.md`.

### [`thirdparty/keychain`](thirdparty/keychain/) — vendored keychain library

Upstream: <https://github.com/hrantzsch/keychain>

Cross-platform keychain C++ library. One platform backend
(`keychain_mac.cpp`, `keychain_win.cpp`, `keychain_linux.cpp`, or
`keychain_android.cpp`) is compiled per platform by `modules/keychain/SCsub`.

### [`thirdparty/rx`](thirdparty/rx) — V-Sekai game

Upstream: <https://github.com/V-Sekai/v-sekai-game>

The V-Sekai social VR game running on Godot 4. Reference client — sized
for `FabricMMOGZone::TARGET_PLAYERS_PER_ZONE` and consuming the 100-byte
CH_PLAYER / CH_INTEREST wire format from `fabric_mmog_peer.h`.

### [`thirdparty/humanoid-project`](thirdparty/humanoid-project) — humanoid rig

Upstream: <https://github.com/V-Sekai/godot-humanoid-project>

Defines the humanoid bone set that `FabricMMOGZone::HUMANOID_BONE_COUNT`
is derived from. If bone count or ordering changes, `ENTITIES_PER_PLAYER`
and `ENTITY_CLASS_HUMANOID_BONE` payload indexing must be updated.

### [`thirdparty/desync`](thirdparty/desync) — reference casync implementation

Upstream: <https://github.com/V-Sekai/desync>

Go implementation of the casync-compatible chunked store. Kept in-tree
as the wire-format reference only. The chunk ID hash width, min/max
chunk-size window, and `.caibx` / `.caidx` index layout in
`fabric_mmog_asset.h` must match the constants here.

### [`thirdparty/uro`](thirdparty/uro) — asset and zone backend

Upstream: <https://github.com/V-Sekai/uro>

Phoenix/Elixir backend. Merged features on `main`:

- Storage, manifest, and ACL endpoints (`/storage`, `/acl/check`, `/auth/script_key`)
- Zone spawner API (`/zones`) — erlexec-managed Godot processes
- Session auth (Pow + MnesiaCache; Redis removed)
- CockroachDB TLS client-cert auth (`mix uro.crdb_gen_certs`)
- OpenTelemetry — in-process ETS span store + LiveDashboard Traces page at `/dev/dashboard`

Open PRs:
- **PR #12** — entity lifecycle (`GET/PUT /entities/:global_id`, `POST .../teleport`): zone calls GET at spawn to restore last state; PUT at despawn to persist. C3 teleport registered before portal crossings so the receiving zone skips the discontinuity check.

### [`thirdparty/uro/tools/zone_console`](thirdparty/uro/tools/zone_console) — operator TUI

ExRatatui terminal UI. Commands: `start`, `stop`, `zones`, `register`,
`unregister`, `heartbeat`. Authenticates against the Uro REST API using
credentials from `.env`. Run via `mix zone_console`.

### [`thirdparty/interaction-system`](thirdparty/interaction-system) — VR input delegation

Upstream: <https://github.com/V-Sekai/godot-interaction-system>

Delegates input events as 3D raycasts. The fabric demo's trident
controller and pen tool originate from interaction-system actions
routed through `fabric_client.gd`.

### [`thirdparty/xr-grid`](thirdparty/xr-grid) — VR locomotion

Upstream: <https://github.com/V-Sekai/V-Sekai.xr-grid>

GDScript addon providing `WorldGrab`, `XRPinch`, and
`procedural_grid_3d.gd` for VR world navigation. Instanced under
`XROrigin3D` in the demo's `main.tscn`. The jellyfish asset loader
instances UGC scenes into this scene at runtime.
