/**************************************************************************/
/*  test_fabric_mmog_transport_peer.h                                     */
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

#include "../fabric_mmog_transport_peer.h"

#include "tests/test_macros.h"

#ifdef MODULE_HTTP3_ENABLED
#include "modules/http3/quic_client.h"
#include "modules/http3/web_transport_peer.h"
#endif

namespace TestFabricMMOGTransportPeer {

#ifdef MODULE_HTTP3_ENABLED
// Build a WebTransportPeer that is already in DISCONNECTED state by binding
// it to a QUICClient that has never connected (STATUS_DISCONNECTED == 0).
static Ref<WebTransportPeer> _make_disconnected_wt_peer() {
	Ref<QUICClient> quic;
	quic.instantiate();
	Ref<WebTransportPeer> peer;
	peer.instantiate();
	peer->_bind_quic(quic, WebTransportPeer::MODE_CLIENT);
	return peer;
}
#endif

TEST_CASE("[FabricMMOGTransportPeer] initial state is DISCONNECTED") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_DISCONNECTED);
#ifdef MODULE_HTTP3_ENABLED
	CHECK(tp->get_wt_peer().is_null());
#endif
	CHECK(tp->get_ws_peer().is_null());
}

#ifdef MODULE_HTTP3_ENABLED
TEST_CASE("[FabricMMOGTransportPeer] create_client returns OK and reports CONNECTING via WT") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	// Port 1 is always refused on loopback — WT will fail asynchronously.
	CHECK(tp->create_client("127.0.0.1", 1) == OK);
	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_CONNECTING);
	CHECK(tp->get_wt_peer().is_valid());
}

TEST_CASE("[FabricMMOGTransportPeer] poll triggers WS fallback when WT is DISCONNECTED") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	// Inject a pre-failed WT peer so the test is synchronous.
	tp->_set_wt_peer_for_test(_make_disconnected_wt_peer());
	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_CONNECTING);

	// poll() detects WT failure and switches to WebSocketMultiplayerPeer.
	tp->poll();

	// Still CONNECTING — now attempting the WS fallback.
	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_CONNECTING);
	CHECK(tp->get_ws_peer().is_valid());
}

TEST_CASE("[FabricMMOGTransportPeer] poll reaches FAILED after both transports disconnect") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	tp->_set_wt_peer_for_test(_make_disconnected_wt_peer());
	tp->poll(); // WT fails → WS created (STATE_TRYING_FALLBACK)

	CHECK(tp->get_ws_peer().is_valid());

	constexpr int MAX_POLLS = 50;
	for (int i = 0; i < MAX_POLLS; i++) {
		tp->poll();
		if (tp->get_connection_status() == MultiplayerPeer::CONNECTION_DISCONNECTED) {
			break;
		}
	}
	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_DISCONNECTED);
}

TEST_CASE("[FabricMMOGTransportPeer] close resets to DISCONNECTED (with WT)") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	tp->_set_wt_peer_for_test(_make_disconnected_wt_peer());
	tp->poll(); // advance to TRYING_FALLBACK

	tp->close();
	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_DISCONNECTED);
	CHECK(tp->get_wt_peer().is_null());
	CHECK(tp->get_ws_peer().is_null());
}

TEST_CASE("[FabricMMOGTransportPeer] wt_path and ws_path are configurable") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	tp->set_wt_path("/webtransport");
	tp->set_ws_path("/websocket");

	CHECK(tp->get_wt_path() == "/webtransport");
	CHECK(tp->get_ws_path() == "/websocket");
}
#else
TEST_CASE("[FabricMMOGTransportPeer] create_client returns OK and reports CONNECTING via WS (no http3)") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	// Without http3, create_client goes straight to WebSocket.
	CHECK(tp->create_client("127.0.0.1", 1) == OK);
	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_CONNECTING);
	CHECK(tp->get_ws_peer().is_valid());
}

TEST_CASE("[FabricMMOGTransportPeer] close resets to DISCONNECTED (WS only)") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	tp->create_client("127.0.0.1", 1);
	tp->close();
	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_DISCONNECTED);
	CHECK(tp->get_ws_peer().is_null());
}

TEST_CASE("[FabricMMOGTransportPeer] ws_path is configurable") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	tp->set_ws_path("/websocket");
	CHECK(tp->get_ws_path() == "/websocket");
}
#endif

} // namespace TestFabricMMOGTransportPeer
