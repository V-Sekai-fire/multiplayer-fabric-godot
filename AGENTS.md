# AGENTS.md — AI Agent Collaboration Guide

This document describes how AI coding agents should work in this repository.
Add notes here incrementally as conventions are established or edge cases discovered.

---

## Repository layout

| Path | Purpose |
|---|---|
| `modules/multiplayer_fabric_mmog/` | Elixir MMOG tooling (zone console, taskweft planner) |
| `modules/http3/demo/wt_server_demo.gd` | Headless Godot WebTransport zone script |
| `thirdparty/uro/` | Uro backend (Phoenix/Elixir REST API + zone spawner) |

---

## Uro backend (`thirdparty/uro/`)

### Starting the dev server

```bash
cd thirdparty/uro
export $(grep -v '^#' .env | xargs)
mix phx.server
```

`.env` must contain absolute paths (dotenv loader does not expand `$HOME`):

```
GODOT_BIN=/Users/ernest.lee/Desktop/godot/bin/godot.macos.editor.dev.arm64
GODOT_PROJECT=/Users/ernest.lee/Desktop/godot
```

### Zone process lifecycle

Zones are headless Godot processes spawned by `Uro.WebTransport.Zone` (GenServer).

- **Start**: `POST /zones` → `ZoneSupervisor` starts a GenServer → `:exec.run/2` spawns Godot.
- **Ready signal**: Godot prints `{"event":"ready","cert_hash":"..."}` to stdout → DB status set to `running`.
- **Stop**: `DELETE /zones/:shard_id/:port` → `DynamicSupervisor.terminate_child` → `terminate/1` → `:exec.kill(os_pid, 15)`.

**Why erlexec instead of `Port.open`**: `:exec.kill/2` only works on PIDs started by erlexec itself (`exec:run/2`). `Port.open` creates untracked OS PIDs that erlexec refuses to kill. Use `{:erlexec, "~> 2.0"}` in `mix.exs`.

**Why `Process.flag(:trap_exit, true)` in `init/1`**: Without it, `terminate/2` is never called when the supervisor sends `:shutdown`, so cleanup (SIGTERM + DB mark) is skipped.

### OpenAPI spec

Regenerate after adding or changing controller actions:

```bash
cd thirdparty/uro
mix openapi.spec.json --spec Uro.OpenAPI.Specification --pretty=true openapi.json
```

The generated `openapi.json` is tracked in git (not gitignored).

---

## Zone console (`modules/multiplayer_fabric_mmog/tools/zone_console/`)

TUI operator console built with ExRatatui. Run as a Mix task (not escript — NIFs can't load from zip archives):

```bash
cd modules/multiplayer_fabric_mmog/tools/zone_console
cp .env.sample .env   # fill in URO_URL, URO_USERNAME, URO_PASSWORD
mix zone_console
```

Key commands: `shards`, `connect <name>`, `start <port>`, `stop <port>`, `zones`.

---

## Godot headless zone script

`modules/http3/demo/wt_server_demo.gd` — launched by Uro with:

```
--headless --script modules/http3/demo/wt_server_demo.gd
```

Environment variables it reads: `ZONE_PORT`, `ZONE_SHARD_ID`.

Stdout JSON protocol:
- `{"event":"ready","port":<N>,"cert_hash":"<base64>"}` — emitted once when WebTransport server is up.

---

## Commit conventions

- One PR per logical change.
- Do not add "Generated with AI" or Co-Authored-By footers to commit messages.
- No shell scripts — use compiled Elixir or Godot programs only.
- Avoid `System.cmd` — use libraries or Erlang ports instead.
