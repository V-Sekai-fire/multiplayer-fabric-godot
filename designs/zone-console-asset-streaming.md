# Zone Console Asset Streaming

Enable `zone_console` to upload a Godot scene to uro, then trigger the
running zone process to stream and instance that scene near the current
player — closing the loop from authoring tool to live world.

Built strictly red-green-refactor: every cycle is one public behavior,
committed when green, with any cleanup done while the test stays green.

## Guiding principles

- **RED first, always.** Write a failing test (or add only the bare
  symbol to make it compile), then make it green. Mutation-test every
  new assertion by briefly breaking the implementation to prove it is
  load-bearing.
- **Narrow the slice.** Each cycle covers one public behavior. If a RED
  needs two implementation changes to turn green, split it into two
  cycles.
- **Warnings are errors.** `mix compile --warnings-as-errors` and
  `cargo build` with `#[warn(unused_must_use)]` enforced on every
  cycle; a new warning is a RED.
- **Commit every green.** One commit per cycle, message starts with
  `Cycle N: …` so the TDD arc is visible in `git log`.
- **No Godot headers in zone_console.** The CLI talks to uro over HTTP
  and to the zone over WebTransport datagrams. Godot-side logic lives
  in the zone process, not the CLI.

## Architecture

```
zone_console (Elixir CLI)
    │
    ├─ aria-storage (library dep)
    │   AriaStorage.process_file/2
    │       buzhash chunk split
    │       zstd compress each chunk
    │       SHA-512/256 chunk ID
    │       store chunks ──────────────────────────────────►  VersityGW S3
    │       build caibx index                                  chunks/{xx}/{chunk_id}.cacnk
    │
    ├─ UroClient.upload_asset/3
    │   POST /storage {chunk_ids, store_url} ──────────────►  uro (Phoenix)
    │                                                            SharedFile record
    │
    ├─ UroClient.get_manifest/2
    │   POST /storage/:id/manifest ────────────────────────►  uro
    │       ◄── {store_url, chunks:[{id,start,size}]}
    │
    └─ ZoneClient.send_instance/3 ──CH_PLAYER datagram────►  zone (Godot headless)
                                    CMD_INSTANCE_ASSET              │
                                    payload[1..2] = UUID (2×u32)    │  fetch manifest
                                    payload[3..5] = pos xyz (f32)   │  download chunks
                                                                     │  zstd decompress
                                                                     │  SHA-512/256 verify
                                                                     │  assemble file
                                                                     │  ResourceLoader.load()
                                                                     └► instantiate at pos
```

## Dependencies

Add to `modules/multiplayer_fabric_mmog/tools/zone_console/mix.exs`:

```elixir
{:aria_storage, github: "V-Sekai-fire/aria-storage"},
```

Configure S3 backend in `config/runtime.exs`:

```elixir
config :aria_storage,
  storage_backend: :s3,
  s3_bucket: System.get_env("AWS_S3_BUCKET", "uro-uploads"),
  s3_endpoint: System.get_env("AWS_S3_ENDPOINT", "http://localhost:7070"),
  aws_access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
```

## Wire protocol addition

New command constant in `fabric_mmog_peer.h` (next after CMD_SPAWN_STROKE = 3):

```cpp
CMD_INSTANCE_ASSET = 4,
// payload[1] = shared_file_uuid_hi (u32, bytes 0-3 of UUID, no hyphens)
// payload[2] = shared_file_uuid_lo (u32, bytes 4-7 of UUID, no hyphens)
// payload[3] = pos_x as bit-cast f32 (u32)
// payload[4] = pos_y as bit-cast f32 (u32)
// payload[5] = pos_z as bit-cast f32 (u32)
```

The zone receives this, reconstructs the UUID prefix, looks up the full
UUID via `GET /storage?prefix=<8hex>`, fetches the caibx manifest, streams
zstd-compressed SHA-512/256-verified chunks from S3, and calls
`ResourceLoader.load()` + `instantiate()` at the given world position.
The 100-byte packet has 14 payload u32 slots; this uses 6.

## Cycles (Pareto order — highest value/effort ratio first)

| Cycle | What you get | Effort |
|---|---|---|
| 1 | `UroClient.upload_asset/3` — casync chunk → S3 → uro manifest | Medium |
| 2 | `upload <path>` command — user can store a scene | Low |
| 3 | `CMD_INSTANCE_ASSET` wire encoding — protocol ready | Low |
| 4 | `instance <id> <x> <y> <z>` command — user can trigger instancing | Low |
| 5 | `UroClient.get_manifest/2` — chunk manifest fetch | Low |
| 6 | Godot zone handler — zone actually instances the scene | High |
| 7 | Round-trip integration smoke test | High |

---

### Cycle 1 — UroClient: chunk file with aria-storage, push to S3, register with uro

**Value:** Unlocks storing any scene in uro from the CLI. Every later cycle depends on this.
**Effort:** aria-storage does the heavy lifting; UroClient wires the manifest registration.

**What happens internally:**

```
file.tscn
  │
  ▼ AriaStorage.process_file/2
  ├─ buzhash content-defined split (16 KB–256 KB chunks)
  ├─ per-chunk: zstd compress → SHA-512/256 ID
  ├─ store each chunk to S3: chunks/{first4hex}/{chunk_id}.cacnk
  └─ build caibx binary index → {:ok, %{chunks: [...], store_url: "s3://..."}}
  │
  ▼ Req POST /storage
  body: {name, chunks: [{id, start, size}], store_url}
  ◄── {id: "uuid", ...}
```

**RED:** `test/zone_console/uro_client_test.exs` — stub `AriaStorage.process_file/2`
to return `{:ok, %{chunks: [%{id: "aa"<><<0::496>>, start: 0, size: 100}], store_url: "s3://bucket"}}`;
mock HTTP returns `{"id": "abc123"}`; assert
`UroClient.upload_asset(token, path, "test.tscn")` returns `{:ok, "abc123"}`.

**Implementation:**
- Add `{:aria_storage, github: "V-Sekai-fire/aria-storage"}` to `mix.exs`.
- Add `upload_asset/3` to `UroClient`:
  1. Call `AriaStorage.process_file(path, backend: :s3)` → `{:ok, %{chunks, store_url}}`.
  2. POST to `/storage` with `{name, chunks, store_url}` + Bearer token.
  3. Return `{:ok, id}`.

**Commit:** `Cycle 1: UroClient.upload_asset/3 — casync chunk + S3 store + uro register`

---

### Cycle 2 — zone_console app: `upload <path>` command

**Value:** First user-visible feature — operator can store a scene and get its ID.
**Effort:** One `handle_line/2` clause calling Cycle 1.

**RED:** `test/zone_console/app_test.exs` — feed `"upload test.tscn"`
to the app loop against a stubbed UroClient, assert the output line
contains the returned asset ID.

**Implementation:** Add `"upload"` clause to `handle_line/2` in
`app.ex`; call `UroClient.upload_asset`, display the ID.

**Commit:** `Cycle 2: app: upload command stores scene in uro`

---

### Cycle 3 — CMD_INSTANCE_ASSET constant and encode path in zone_client

**Value:** Wire protocol ready; ZoneClient can send instance commands. Unblocks Cycle 4.
**Effort:** Elixir packet encoding + constant addition in C++ header.

**RED:** Unit test `encode_player/6` with `cmd: :instance_asset,
asset_id: 7, pos: {1.0, 2.0, 3.0}` — assert payload bytes decode back
to the correct values.

**Implementation:**
- Add `CMD_INSTANCE_ASSET = 4` to the command enum in
  `fabric_mmog_peer.h`.
- Add `send_instance/4` to `ZoneClient` — build the 100-byte packet
  with `payload[1] = asset_id`, `payload[2..4] = f32 pos`.

**Commit:** `Cycle 3: ZoneClient.send_instance/4 — CMD_INSTANCE_ASSET encoding`

---

### Cycle 4 — zone_console app: `instance <asset_id> <x> <y> <z>` command

**Value:** Second user-visible feature — operator can trigger scene instancing from the CLI.
**Effort:** One `handle_line/2` clause calling Cycle 3.

**RED:** Assert the app emits `"instanced asset …"` after a stubbed
`ZoneClient.send_instance` call.

**Implementation:** Add `"instance"` clause to `handle_line/2`; parse
asset_id and float coords; call `ZoneClient.send_instance`.

**Commit:** `Cycle 4: app: instance command sends CMD_INSTANCE_ASSET to zone`

---

### Cycle 5 — UroClient: fetch manifest for a shared_file_id

**Value:** Chunk manifest available to the zone handler. Deferred until here because
nothing before Cycle 6 needs it.
**Effort:** One `Req` call.

**RED:** Assert `UroClient.get_manifest(token, id)` returns
`{:ok, %{store_url: _, chunks: [_|_]}}` against a mock that returns
the uro manifest JSON shape.

**Implementation:** Add `get_manifest/2` to `UroClient` — POST to
`/storage/:id/manifest`, parse `store_url` and `chunks` fields.

**Commit:** `Cycle 5: UroClient.get_manifest/2 — POST /storage/:id/manifest`

---

### Cycle 6 — Godot zone: handle CMD_INSTANCE_ASSET datagram

**Value:** Completes the full loop — the zone actually fetches and instances the scene.
**Effort:** C++ dispatch, `FabricMMOGAsset::fetch_asset` wiring, `ResourceLoader` call.

**RED:** C++ unit test in `modules/multiplayer_fabric_mmog/tests/` —
feed a crafted 100-byte datagram with `cmd = 4`, assert the zone
handler calls `request_manifest(asset_id)` and queues a load job.

**Implementation:**
- Add `case CMD_INSTANCE_ASSET:` to the command dispatch in
  `FabricMMOGPeer::_process_peer_packet`.
- Extract `asset_id`, `pos`; call `FabricMMOGAsset::fetch_asset` with
  the uro manifest URL.
- On completion, call `ResourceLoader::load()` + `Node::instantiate()`
  and add to the scene tree at `pos`.

**Commit:** `Cycle 6: zone: CMD_INSTANCE_ASSET — fetch manifest, stream chunks, instantiate scene`

---

### Cycle 7 — round-trip integration smoke test

**Value:** Validates the end-to-end path under a live stack.
**Effort:** Requires CockroachDB + VersityGW + uro + zone all running locally.

**RED:** `mix test` with a live local stack — upload a minimal `.tscn`,
`instance` it, assert the zone entity list shows a new entry near `pos`.

**Implementation:** Whatever the integration test exposes.

**Commit:** `Cycle 7: integration: upload → instance round-trip`

## Design notes

### Asset ID truncation

Uro uses UUID v4 strings as `SharedFile` IDs. The wire protocol carries
a `u32` in `payload[1]` (4 bytes). The zone_console sends the lower
32 bits of the UUID (after stripping hyphens). The zone reconstructs
the full UUID via a uro lookup (`GET /storage/<prefix>*`) or the
zone_console pre-resolves the full ID before streaming.

Preferred approach: zone_console sends the full UUID as two consecutive
`u32` payload slots (`payload[1]` + `payload[2]`), shifting position
into `payload[3..5]`. Packet stays within the 14-slot budget (5 slots
used total).

### S3 / VersityGW configuration

Uro's `config/runtime.exs` must set:

```elixir
config :waffle, storage: Waffle.Storage.S3,
  bucket: System.get_env("AWS_S3_BUCKET", "uro-uploads")
```

The zone process reads `URO_API_URL` from the environment and fetches
the manifest from uro; chunk downloads go directly to VersityGW using
presigned URLs returned in the manifest response.

### Chunk streaming in the zone

`FabricMMOGAsset::fetch_asset` already handles the caibx index +
chunk download + SHA-512/256 verification pipeline. Cycle 6 only needs
to call it from the command handler and wire the completion callback to
`ResourceLoader::load()`.

### Scene instancing near the player

`pos` in the datagram is the sender's current position (already in
`state.player_pos` in zone_console). The zone should apply a small
random XZ offset so multiple `instance` calls do not stack on the same
point.
