/**************************************************************************/
/*  fabric_mmog_transport_peer.cpp                                        */
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

#include "fabric_mmog_transport_peer.h"

#include "core/object/class_db.h"
#include "core/string/ustring.h"

void FabricMMOGTransportPeer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("create_client", "host", "port"),
			&FabricMMOGTransportPeer::create_client);

	ClassDB::bind_method(D_METHOD("set_wt_path", "path"), &FabricMMOGTransportPeer::set_wt_path);
	ClassDB::bind_method(D_METHOD("get_wt_path"), &FabricMMOGTransportPeer::get_wt_path);
	ClassDB::bind_method(D_METHOD("set_ws_path", "path"), &FabricMMOGTransportPeer::set_ws_path);
	ClassDB::bind_method(D_METHOD("get_ws_path"), &FabricMMOGTransportPeer::get_ws_path);

	ClassDB::bind_method(D_METHOD("get_wt_peer"), &FabricMMOGTransportPeer::get_wt_peer);
	ClassDB::bind_method(D_METHOD("get_ws_peer"), &FabricMMOGTransportPeer::get_ws_peer);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "wt_path"), "set_wt_path", "get_wt_path");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "ws_path"), "set_ws_path", "get_ws_path");
}

// ── config ───────────────────────────────────────────────────────────────────

void FabricMMOGTransportPeer::set_wt_path(const String &p_path) {
	_wt_path = p_path;
}
String FabricMMOGTransportPeer::get_wt_path() const {
	return _wt_path;
}

void FabricMMOGTransportPeer::set_ws_path(const String &p_path) {
	_ws_path = p_path;
}
String FabricMMOGTransportPeer::get_ws_path() const {
	return _ws_path;
}

Ref<WebTransportPeer> FabricMMOGTransportPeer::get_wt_peer() const {
	return _wt_peer;
}
Ref<WebSocketMultiplayerPeer> FabricMMOGTransportPeer::get_ws_peer() const {
	return _ws_peer;
}

// ── connection ───────────────────────────────────────────────────────────────

Error FabricMMOGTransportPeer::create_client(const String &p_host, int p_port) {
	_host = p_host;
	_port = p_port;

	_wt_peer.instantiate();
	_active = _wt_peer;
	_state = STATE_TRYING_PRIMARY;

	// Initiate the WebTransport connect; failure is detected asynchronously
	// in poll() via get_connection_status() == CONNECTION_DISCONNECTED.
	_wt_peer->create_client(p_host, p_port, _wt_path);
	return OK;
}

void FabricMMOGTransportPeer::_try_fallback() {
	_ws_peer.instantiate();
	_active = _ws_peer;
	_state = STATE_TRYING_FALLBACK;

	const String url = vformat("ws://%s:%d%s", _host, _port, _ws_path);
	_ws_peer->create_client(url, Ref<TLSOptions>());
}

void FabricMMOGTransportPeer::_set_wt_peer_for_test(Ref<WebTransportPeer> p_peer) {
	_wt_peer = p_peer;
	_active = _wt_peer;
	_state = STATE_TRYING_PRIMARY;
}

// ── poll / close ─────────────────────────────────────────────────────────────

void FabricMMOGTransportPeer::poll() {
	if (!_active.is_valid()) {
		return;
	}
	_active->poll();

	const ConnectionStatus status = _active->get_connection_status();

	if (_state == STATE_TRYING_PRIMARY && status == CONNECTION_DISCONNECTED) {
		_try_fallback();
	} else if (_state == STATE_TRYING_PRIMARY && status == CONNECTION_CONNECTED) {
		_state = STATE_CONNECTED;
	} else if (_state == STATE_TRYING_FALLBACK && status == CONNECTION_DISCONNECTED) {
		_state = STATE_FAILED;
	} else if (_state == STATE_TRYING_FALLBACK && status == CONNECTION_CONNECTED) {
		_state = STATE_CONNECTED;
	}
}

void FabricMMOGTransportPeer::close() {
	if (_active.is_valid()) {
		_active->close();
	}
	_active.unref();
	_wt_peer.unref();
	_ws_peer.unref();
	_state = STATE_IDLE;
}

// ── connection status ────────────────────────────────────────────────────────

MultiplayerPeer::ConnectionStatus FabricMMOGTransportPeer::get_connection_status() const {
	switch (_state) {
		case STATE_IDLE:
		case STATE_FAILED:
			return CONNECTION_DISCONNECTED;
		case STATE_TRYING_PRIMARY:
		case STATE_TRYING_FALLBACK:
			return CONNECTION_CONNECTING;
		case STATE_CONNECTED:
			return CONNECTION_CONNECTED;
	}
	return CONNECTION_DISCONNECTED;
}

// ── MultiplayerPeer delegation ────────────────────────────────────────────────

void FabricMMOGTransportPeer::set_target_peer(int p_peer_id) {
	if (_active.is_valid()) {
		_active->set_target_peer(p_peer_id);
	}
}

int FabricMMOGTransportPeer::get_packet_peer() const {
	return _active.is_valid() ? _active->get_packet_peer() : 0;
}

MultiplayerPeer::TransferMode FabricMMOGTransportPeer::get_packet_mode() const {
	return _active.is_valid() ? _active->get_packet_mode() : TRANSFER_MODE_RELIABLE;
}

int FabricMMOGTransportPeer::get_packet_channel() const {
	return _active.is_valid() ? _active->get_packet_channel() : 0;
}

void FabricMMOGTransportPeer::disconnect_peer(int p_peer, bool p_force) {
	if (_active.is_valid()) {
		_active->disconnect_peer(p_peer, p_force);
	}
}

bool FabricMMOGTransportPeer::is_server() const {
	return _active.is_valid() ? _active->is_server() : false;
}

int FabricMMOGTransportPeer::get_unique_id() const {
	return _active.is_valid() ? _active->get_unique_id() : 0;
}

bool FabricMMOGTransportPeer::is_server_relay_supported() const {
	return _active.is_valid() ? _active->is_server_relay_supported() : false;
}

// ── PacketPeer delegation ─────────────────────────────────────────────────────

Error FabricMMOGTransportPeer::get_packet(const uint8_t **r_buffer, int &r_buffer_size) {
	ERR_FAIL_COND_V(!_active.is_valid(), ERR_UNAVAILABLE);
	return _active->get_packet(r_buffer, r_buffer_size);
}

Error FabricMMOGTransportPeer::put_packet(const uint8_t *p_buffer, int p_buffer_size) {
	ERR_FAIL_COND_V(!_active.is_valid(), ERR_UNAVAILABLE);
	return _active->put_packet(p_buffer, p_buffer_size);
}

int FabricMMOGTransportPeer::get_available_packet_count() const {
	return _active.is_valid() ? _active->get_available_packet_count() : 0;
}

int FabricMMOGTransportPeer::get_max_packet_size() const {
	return _active.is_valid() ? _active->get_max_packet_size() : 0;
}
