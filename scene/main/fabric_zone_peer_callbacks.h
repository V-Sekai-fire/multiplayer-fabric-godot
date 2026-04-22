/**************************************************************************/
/*  fabric_zone_peer_callbacks.h                                          */
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

#pragma once

#include "core/templates/local_vector.h"
#include "core/templates/vector.h"
#include "scene/main/multiplayer_peer.h"

// Vtable filled by the multiplayer_fabric module so FabricZone never depends
// on the concrete ENet-backed FabricMultiplayerPeer directly.
struct FabricZonePeerCallbacks {
	Ref<MultiplayerPeer> (*create_server)(int p_port, int p_max_clients) = nullptr;
	Ref<MultiplayerPeer> (*create_client)(const String &p_address, int p_port) = nullptr;
	void (*connect_to_zone)(MultiplayerPeer *p_peer, int p_target_zone_id, int p_target_port) = nullptr;
	bool (*is_zone_connected)(const MultiplayerPeer *p_peer, int p_zone_id) = nullptr;
	void (*send_to_zone_raw)(MultiplayerPeer *p_peer, int p_target_zone_id, int p_channel, const uint8_t *p_data, int p_size) = nullptr;
	void (*broadcast_raw)(MultiplayerPeer *p_peer, int p_channel, const uint8_t *p_data, int p_size) = nullptr;
	void (*local_broadcast_raw)(MultiplayerPeer *p_peer, int p_channel, const uint8_t *p_data, int p_size) = nullptr;
	LocalVector<Vector<uint8_t>> (*drain_channel_raw)(MultiplayerPeer *p_peer, int p_channel) = nullptr;

	bool is_valid() const { return create_server != nullptr; }
};
