/**************************************************************************/
/*  test_http3_client.h                                                   */
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

#include "../http3_client.h"

#include "core/os/os.h"
#include "tests/test_macros.h"

namespace TestHTTP3Client {

static constexpr uint32_t POLL_SLEEP_USEC = 50 * 1000; // 50 ms

TEST_CASE("[HTTP3Client] Fresh instance is DISCONNECTED") {
	Ref<HTTP3Client> client;
	client.instantiate();
	REQUIRE(client.is_valid());
	CHECK(client->get_status() == HTTP3Client::STATUS_DISCONNECTED);
	CHECK(client->get_response_code() == 0);
}

TEST_CASE("[HTTP3Client] Status enum mirrors HTTPClient") {
	// Values need not match HTTPClient exactly, but order should follow
	// the familiar handshake-then-request flow.
	CHECK(HTTP3Client::STATUS_DISCONNECTED == 0);
	CHECK(HTTP3Client::STATUS_CONNECTING > HTTP3Client::STATUS_DISCONNECTED);
	CHECK(HTTP3Client::STATUS_CONNECTED > HTTP3Client::STATUS_CONNECTING);
	CHECK(HTTP3Client::STATUS_REQUESTING > HTTP3Client::STATUS_CONNECTED);
	CHECK(HTTP3Client::STATUS_BODY > HTTP3Client::STATUS_REQUESTING);
}

TEST_CASE("[HTTP3Client] connect_to_host rejects invalid args") {
	Ref<HTTP3Client> client;
	client.instantiate();
	CHECK(client->connect_to_host(String(), 443) == ERR_INVALID_PARAMETER);
	CHECK(client->connect_to_host("example.com", 0) == ERR_INVALID_PARAMETER);
	CHECK(client->connect_to_host("example.com", 65536) == ERR_INVALID_PARAMETER);
}

TEST_CASE("[HTTP3Client] request before connect returns ERR_UNCONFIGURED") {
	Ref<HTTP3Client> client;
	client.instantiate();
	Vector<String> hdrs;
	CHECK(client->request(HTTP3Client::METHOD_GET, "/", hdrs, nullptr, 0) == ERR_UNCONFIGURED);
}

TEST_CASE("[HTTP3Client] close() resets state") {
	Ref<HTTP3Client> client;
	client.instantiate();
	client->close();
	CHECK(client->get_status() == HTTP3Client::STATUS_DISCONNECTED);
	CHECK(client->get_response_code() == 0);
	CHECK(client->read_response_body_chunk().is_empty());
}

TEST_CASE("[HTTP3Client] 🏆 GET cloudflare-quic.com returns 200 via HTTP3Client API") {
	if (QUICClient::create_backend_func == nullptr) {
		MESSAGE("No QUIC backend registered — skipping");
		return;
	}
	Ref<HTTP3Client> client;
	client.instantiate();

	Error err = client->connect_to_host("cloudflare-quic.com", 443);
	if (err == ERR_CANT_RESOLVE) {
		MESSAGE("DNS unavailable — skipping");
		return;
	}
	REQUIRE(err == OK);

	// Drive handshake state machine: exit when no longer CONNECTING.
	// Termination proved in lean/http3/PollingTermination.lean.
	while (client->get_status() == HTTP3Client::STATUS_CONNECTING) {
		client->poll();
		OS::get_singleton()->delay_usec(POLL_SLEEP_USEC);
	}
	REQUIRE(client->get_status() == HTTP3Client::STATUS_CONNECTED);

	// Issue request (spec-shaped signature).
	Vector<String> hdrs;
	REQUIRE(client->request(HTTP3Client::METHOD_GET, "/", hdrs, nullptr, 0) == OK);

	// Drive response state machine: exit when headers parsed or error.
	while (client->get_status() != HTTP3Client::STATUS_BODY &&
			client->get_status() != HTTP3Client::STATUS_CONNECTION_ERROR) {
		client->poll();
		OS::get_singleton()->delay_usec(POLL_SLEEP_USEC);
	}

	MESSAGE("🏆 HTTP3Client response code: ", client->get_response_code());
	CHECK(client->get_response_code() == 200);
	CHECK(client->has_response());
	CHECK(client->is_response_chunked());

	List<String> headers;
	client->get_response_headers(&headers);
	MESSAGE("response headers: ", (int)headers.size());
	for (const String &h : headers) {
		MESSAGE("  ", h);
	}
	CHECK(headers.size() >= 1); // at least :status should be there

	// Drain one body chunk.
	client->poll();
	PackedByteArray body = client->read_response_body_chunk();
	MESSAGE("body chunk bytes: ", (int)body.size());
	CHECK(body.size() > 0);

	client->close();
}

} // namespace TestHTTP3Client
