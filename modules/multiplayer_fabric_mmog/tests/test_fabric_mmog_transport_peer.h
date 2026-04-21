// SPDX-License-Identifier: MIT
// Copyright (c) 2026 K. S. Ernest (iFire) Lee
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

#include "modules/http3/quic_client.h"
#include "modules/http3/web_transport_peer.h"

namespace TestFabricMMOGTransportPeer {

// Build a WebTransportPeer that is already in DISCONNECTED state by binding
// it to a QUICClient that has never connected (STATUS_DISCONNECTED == 0).
static Ref<WebTransportPeer> _make_disconnected_wt_peer() {
	Ref<QUICClient> quic;
	quic.instantiate();
	// Default QUICClient status is STATUS_DISCONNECTED — no _set_status call needed.
	Ref<WebTransportPeer> peer;
	peer.instantiate();
	peer->_bind_quic(quic, WebTransportPeer::MODE_CLIENT);
	return peer;
}

TEST_CASE("[FabricMMOGTransportPeer] initial state is DISCONNECTED") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_DISCONNECTED);
	CHECK(tp->get_wt_peer().is_null());
	CHECK(tp->get_ws_peer().is_null());
}

TEST_CASE("[FabricMMOGTransportPeer] create_client returns OK and reports CONNECTING") {
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
	// WS peer was created by the fallback path.
	CHECK(tp->get_ws_peer().is_valid());
}

TEST_CASE("[FabricMMOGTransportPeer] poll reaches FAILED after both transports disconnect") {
	Ref<FabricMMOGTransportPeer> tp;
	tp.instantiate();

	// Start with a pre-failed WT peer; trigger fallback.
	tp->_set_wt_peer_for_test(_make_disconnected_wt_peer());
	tp->poll(); // WT fails → WS created (STATE_TRYING_FALLBACK)

	// The WS peer connects to port 1 which will be refused; poll once more to
	// drain whatever state the WebSocketPeer surfaces immediately.
	// On most platforms a refused TCP connect is visible after one poll.
	CHECK(tp->get_ws_peer().is_valid());

	// After the WS peer also reaches DISCONNECTED the overall state is FAILED.
	// Poll until either DISCONNECTED is observed or we exhaust a safety cap.
	constexpr int MAX_POLLS = 50;
	for (int i = 0; i < MAX_POLLS; i++) {
		tp->poll();
		if (tp->get_connection_status() == MultiplayerPeer::CONNECTION_DISCONNECTED) {
			break;
		}
	}
	// WS fallback to 127.0.0.1:1 must eventually fail.
	CHECK(tp->get_connection_status() == MultiplayerPeer::CONNECTION_DISCONNECTED);
}

TEST_CASE("[FabricMMOGTransportPeer] close resets to DISCONNECTED") {
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

} // namespace TestFabricMMOGTransportPeer
