/**************************************************************************/
/*  fabric_mmog_zone.cpp                                                  */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "fabric_mmog_zone.h"

#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/string/print_string.h"

#include <cstring>

// Match FabricZone / FabricMultiplayerPeer channel table.
static constexpr int CH_MIGRATION = 1;

void FabricMMOGZone::_bind_methods() {
	ClassDB::bind_method(D_METHOD("spawn_humanoid_entities_for_player", "player_id"),
			&FabricMMOGZone::spawn_humanoid_entities_for_player);
	ClassDB::bind_method(D_METHOD("despawn_humanoid_entities_for_player", "player_id"),
			&FabricMMOGZone::despawn_humanoid_entities_for_player);
	ClassDB::bind_method(D_METHOD("register_script", "slot", "index_chunk_id", "uro_uuid"),
			&FabricMMOGZone::register_script);
	ClassDB::bind_method(D_METHOD("send_script_registry", "peer_id"),
			&FabricMMOGZone::send_script_registry);

	BIND_CONSTANT(HUMANOID_BONE_COUNT);
	BIND_CONSTANT(ENTITIES_PER_PLAYER);
	BIND_CONSTANT(TARGET_PLAYERS_PER_ZONE);
	BIND_CONSTANT(ZONE_CAPACITY_TARGET);
	BIND_CONSTANT(ENTITY_CLASS_HUMANOID_BONE);
}

int FabricMMOGZone::spawn_humanoid_entities_for_player(int p_player_id) {
	ERR_FAIL_COND_V_MSG(_player_bone_slots.has(p_player_id), -1,
			"FabricMMOGZone: humanoid entities already spawned for player.");
	LocalVector<int> bone_slots;
	bone_slots.resize(ENTITIES_PER_PLAYER);
	for (int bone = 0; bone < ENTITIES_PER_PLAYER; bone++) {
		int idx = _alloc_entity_slot();
		if (idx < 0) {
			// Zone is full — roll back slots already allocated this call.
			for (int j = 0; j < bone; j++) {
				_free_entity_slot(bone_slots[j]);
			}
			ERR_FAIL_V_MSG(-1, "FabricMMOGZone: zone full, cannot spawn humanoid entities for player.");
		}
		FabricEntity &e = _slot_entity_ref(idx);
		e.global_id = HUMANOID_BONE_ENTITY_BASE + p_player_id * ENTITIES_PER_PLAYER + bone;
		// payload[0]: entity_class(8b) | player_id(16b) | bone_index(6b) | dof_mask(2b)
		e.payload[0] = ((uint32_t)ENTITY_CLASS_HUMANOID_BONE << 24u) |
				((uint32_t)(p_player_id & 0xFFFF) << 8u) |
				((uint32_t)(bone & 0x3F) << 2u);
		bone_slots[bone] = idx;
	}
	int first_slot = bone_slots[0];
	_player_bone_slots.insert(p_player_id, bone_slots);
	return first_slot;
}

void FabricMMOGZone::despawn_humanoid_entities_for_player(int p_player_id) {
	HashMap<int, LocalVector<int>>::Iterator it = _player_bone_slots.find(p_player_id);
	ERR_FAIL_COND_MSG(it == _player_bone_slots.end(),
			"FabricMMOGZone: no bone entities found for player.");
	for (int idx : it->value) {
		_free_entity_slot(idx);
	}
	_player_bone_slots.remove(it);
}

void FabricMMOGZone::register_script(int p_slot, const PackedByteArray &p_index_chunk_id,
		const PackedByteArray &p_uro_uuid) {
	ERR_FAIL_COND_MSG(p_index_chunk_id.size() != FabricMMOGAsset::REGISTRY_INDEX_ID_BYTES,
			"register_script: index_chunk_id must be exactly 32 bytes (SHA-512/256).");
	ERR_FAIL_COND_MSG(p_uro_uuid.size() != FabricMMOGAsset::REGISTRY_URO_UUID_BYTES,
			"register_script: uro_uuid must be exactly 16 bytes.");
	ScriptRegistryEntry entry;
	entry.slot = (uint16_t)(p_slot & 0xFFFF);
	memcpy(entry.index_chunk_id, p_index_chunk_id.ptr(), FabricMMOGAsset::REGISTRY_INDEX_ID_BYTES);
	memcpy(entry.uro_uuid, p_uro_uuid.ptr(), FabricMMOGAsset::REGISTRY_URO_UUID_BYTES);
	_script_registry.push_back(entry);
}

void FabricMMOGZone::send_script_registry(int p_peer_id) {
	if (_script_registry.is_empty()) {
		return;
	}
	// Serialize: [slot: u16][index_chunk_id: 32B][uro_uuid: 16B] per entry.
	const uint32_t entry_bytes = FabricMMOGAsset::REGISTRY_ENTRY_BYTES; // 50
	const uint32_t total = _script_registry.size() * entry_bytes;
	Vector<uint8_t> buf;
	buf.resize((int)total);
	uint8_t *w = buf.ptrw();
	for (uint32_t i = 0; i < _script_registry.size(); i++) {
		const ScriptRegistryEntry &e = _script_registry[i];
		uint8_t *p = w + i * entry_bytes;
		p[0] = e.slot & 0xFF;
		p[1] = (e.slot >> 8) & 0xFF;
		memcpy(p + FabricMMOGAsset::REGISTRY_SLOT_BYTES,
				e.index_chunk_id, FabricMMOGAsset::REGISTRY_INDEX_ID_BYTES);
		memcpy(p + FabricMMOGAsset::REGISTRY_SLOT_BYTES + FabricMMOGAsset::REGISTRY_INDEX_ID_BYTES,
				e.uro_uuid, FabricMMOGAsset::REGISTRY_URO_UUID_BYTES);
	}
	_send_to_peer_raw(p_peer_id, CH_MIGRATION, buf.ptr(), buf.size());
}

void FabricMMOGZone::_on_cmd_instance_asset(uint32_t p_player_id,
		real_t p_pcx, real_t p_pcy, real_t p_pcz,
		const Vector<uint8_t> &p_pkt) {
	if (p_pkt.size() < 68) {
		return;
	}

	// payload[1] = asset_id high 32 bits (offset 48)
	// payload[2] = asset_id low  32 bits (offset 52)
	uint32_t asset_id_hi = 0, asset_id_lo = 0;
	memcpy(&asset_id_hi, p_pkt.ptr() + 48, 4);
	memcpy(&asset_id_lo, p_pkt.ptr() + 52, 4);
	const uint64_t asset_id64 = ((uint64_t)asset_id_hi << 32u) | asset_id_lo;

	// payload[3-5] = target position as f32 bit patterns (offset 56-67)
	uint32_t xu = 0, yu = 0, zu = 0;
	memcpy(&xu, p_pkt.ptr() + 56, 4);
	memcpy(&yu, p_pkt.ptr() + 60, 4);
	memcpy(&zu, p_pkt.ptr() + 64, 4);
	float tx, ty, tz;
	memcpy(&tx, &xu, 4);
	memcpy(&ty, &yu, 4);
	memcpy(&tz, &zu, 4);

	// Build hex string from 64-bit asset id for the uro manifest endpoint.
	String asset_id_str = String::num_uint64(asset_id64, 16).lpad(16, "0");

	String uro_url = OS::get_singleton()->get_environment("URO_URL");
	if (uro_url.is_empty()) {
		uro_url = "http://zone-backend:4000";
	}

	Vector<FabricMMOGAsset::CaibxChunk> chunks;
	String manifest_error;
	const Error err = FabricMMOGAsset::request_manifest(uro_url, asset_id_str,
			chunks, manifest_error);
	if (err != OK) {
		print_error(vformat("CMD_INSTANCE_ASSET: manifest fetch failed for %s: %s",
				asset_id_str, manifest_error));
		return;
	}

	// Allocate a slot at the target position and broadcast it via CH_INTEREST.
	const int slot_idx = _alloc_entity_slot();
	if (slot_idx < 0) {
		print_error("CMD_INSTANCE_ASSET: zone full, cannot allocate slot");
		return;
	}

	FabricEntity &ent = _slot_entity_ref(slot_idx);
	ent.cx = (real_t)tx;
	ent.cy = (real_t)ty;
	ent.cz = (real_t)tz;
	ent.global_id = ASSET_INSTANCE_ENTITY_BASE + _asset_instance_counter++;
	// payload[0]: entity_class(8b) | asset_id_lo bits 0-23 for client lookup
	ent.payload[0] = ((uint32_t)ENTITY_CLASS_ASSET_INSTANCE << 24u) |
			(asset_id_lo & 0x00FFFFFFu);
	ent.payload[1] = asset_id_hi;
	ent.payload[2] = asset_id_lo;
}
