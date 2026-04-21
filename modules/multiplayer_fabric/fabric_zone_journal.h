// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
#pragma once

#include "fabric_zone.h"
#include "sqlite/sqlite3.h"

// Discrete-mutation journal backed by SQLite.
//
// Only events that change durable state are written:
//   spawn            — entity slot allocated and initialised
//   despawn          — entity slot freed
//   payload_update   — payload words changed (e.g. CMD_INSTANCE_ASSET)
//   snapshot         — full slot-array dump; caps replay length
//
// Physics-step position updates are NOT written — they are deterministic
// from the simulation and too frequent to journal economically.
//
// Crash recovery:
//   open() → replay() → zone runs normally with journal enabled
//
// WAL mode (PRAGMA journal_mode=WAL) is used when available; requires that
// SQLITE_OMIT_WAL is absent from the build (removed from modules/sqlite/SCsub).

class FabricZoneJournal {
public:
	FabricZoneJournal() = default;
	~FabricZoneJournal();

	// Open or create the journal at p_db_path. Returns false on error.
	bool open(const String &p_db_path);
	void close();
	bool is_open() const { return _db != nullptr; }

	// Discrete mutation writers — no-op when not open.
	void journal_spawn(int p_slot_idx, const FabricZone::FabricEntity &p_entity);
	void journal_despawn(int p_slot_idx, int p_global_id);
	// Records changed payload words (asset instance, player state update).
	void journal_payload_update(int p_slot_idx, const FabricZone::FabricEntity &p_entity);
	// Periodic full snapshot — resets the replay start point.
	void journal_snapshot(int p_capacity, const FabricZone::EntitySlot *p_slots);

	// Replay journal into p_slots.  p_slots must already be zero-initialised
	// with capacity p_capacity.  Sets r_entity_count to the number of active
	// slots after replay.  Returns true if any data was replayed.
	bool replay(int p_capacity, FabricZone::EntitySlot *p_slots, int &r_entity_count);

private:
	sqlite3 *_db = nullptr;

	void _exec(const char *p_sql);
	void _create_schema();
	int64_t _latest_snapshot_seq();

	static void _pack_entity(const FabricZone::FabricEntity &p_e, uint8_t *p_out);
	static void _unpack_entity(const uint8_t *p_in, FabricZone::FabricEntity &r_e);
};
