/**************************************************************************/
/*  fabric_mmog_transport_peer.h                                          */
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

#include "scene/main/multiplayer_peer.h"

#include "modules/http3/web_transport_peer.h"
#include "modules/websocket/websocket_multiplayer_peer.h"

// FabricMMOGTransportPeer — client-side MultiplayerPeer with automatic fallback.
//
// Tries WebTransportPeer (QUIC/HTTP3) first.  When that peer reaches
// CONNECTION_DISCONNECTED before becoming CONNECTION_CONNECTED, it is silently
// replaced by a WebSocketMultiplayerPeer (TCP-WS) dialling the same host and
// port on a configurable WebSocket path.
//
// Callers see a single lifecycle: CONNECTION_CONNECTING during both attempts,
// CONNECTION_CONNECTED once either transport succeeds.  The switch is invisible
// to FabricMultiplayerPeer and FabricMMOGZone.
//
// Caveat: WebSocketMultiplayerPeer uses TCP, so CH_INTEREST and CH_PLAYER lose
// their unreliable (drop-stale) semantics during fallback — snapshots queue up
// rather than being discarded.  Latency under congestion increases but the
// session remains alive.
//
// Usage (GDScript client_factory for FabricMultiplayerPeer):
//
//   fab.client_factory = func(host, port):
//       var tp = FabricMMOGTransportPeer.new()
//       tp.create_client(host, port)
//       return tp
class FabricMMOGTransportPeer : public MultiplayerPeer {
	GDCLASS(FabricMMOGTransportPeer, MultiplayerPeer);

	enum State {
		STATE_IDLE,
		STATE_TRYING_PRIMARY, // waiting for WebTransportPeer to connect
		STATE_TRYING_FALLBACK, // WT failed; waiting for WebSocketMultiplayerPeer
		STATE_CONNECTED,
		STATE_FAILED,
	};

	Ref<WebTransportPeer> _wt_peer;
	Ref<WebSocketMultiplayerPeer> _ws_peer;
	Ref<MultiplayerPeer> _active; // points to whichever peer is currently active

	String _host;
	int _port = 0;
	String _wt_path = "/wt";
	String _ws_path = "/ws";
	State _state = STATE_IDLE;

	void _try_fallback();

protected:
	static void _bind_methods();

public:
	// Dial WebTransportPeer; switches to WebSocketMultiplayerPeer on failure.
	Error create_client(const String &p_host, int p_port);

	void set_wt_path(const String &p_path);
	String get_wt_path() const;

	void set_ws_path(const String &p_path);
	String get_ws_path() const;

	// Inspect the underlying transport peers (available after create_client).
	Ref<WebTransportPeer> get_wt_peer() const;
	Ref<WebSocketMultiplayerPeer> get_ws_peer() const;

	// TEST HOOK: inject a pre-configured WebTransportPeer (e.g. one bound to a
	// fake QUICClient via _bind_quic) and advance to TRYING_PRIMARY without
	// initiating a real network connection.
	void _set_wt_peer_for_test(Ref<WebTransportPeer> p_peer);

	// MultiplayerPeer interface — all delegate to the active peer.
	virtual void set_target_peer(int p_peer_id) override;
	virtual int get_packet_peer() const override;
	virtual TransferMode get_packet_mode() const override;
	virtual int get_packet_channel() const override;
	virtual void disconnect_peer(int p_peer, bool p_force = false) override;
	virtual bool is_server() const override;
	virtual void poll() override;
	virtual void close() override;
	virtual int get_unique_id() const override;
	virtual ConnectionStatus get_connection_status() const override;
	virtual bool is_server_relay_supported() const override;

	// PacketPeer interface.
	virtual Error get_packet(const uint8_t **r_buffer, int &r_buffer_size) override;
	virtual Error put_packet(const uint8_t *p_buffer, int p_buffer_size) override;
	virtual int get_available_packet_count() const override;
	virtual int get_max_packet_size() const override;

	FabricMMOGTransportPeer() = default;
	~FabricMMOGTransportPeer() = default;
};
