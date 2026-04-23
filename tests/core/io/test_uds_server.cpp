/**************************************************************************/
/*  test_uds_server.cpp                                                   */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_uds_server)

#ifdef UNIX_ENABLED

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/stream_peer_uds.h"
#include "core/io/uds_server.h"
#include "core/os/os.h"

namespace TestUDSServer {

const String SOCKET_PATH = "/tmp/godot_test_uds_socket";
const uint32_t SLEEP_DURATION = 1000;
const uint64_t MAX_WAIT_USEC = 2000000;
// Iteration bound for state-machine polling loops: same wall-clock budget as
// wait_for_condition but expressed as a count so no raw time arithmetic is
// needed inside individual loops.
static constexpr int POLL_LIMIT = (int)(MAX_WAIT_USEC / SLEEP_DURATION);

// Template instead of std::function: avoids heap/SBO boxing that triggers
// stack-smashing detection in template_debug builds with -fstack-protector-all.
template <typename F>
void wait_for_condition(F f_test) {
	const uint64_t time = OS::get_singleton()->get_ticks_usec();
	while (!f_test() && (OS::get_singleton()->get_ticks_usec() - time) < MAX_WAIT_USEC) {
		OS::get_singleton()->delay_usec(SLEEP_DURATION);
	}
}

void cleanup_socket_file() {
	// Remove socket file if it exists
	if (FileAccess::exists(SOCKET_PATH)) {
		DirAccess::remove_absolute(SOCKET_PATH);
	}
}

Ref<UDSServer> create_server(const String &p_path) {
	cleanup_socket_file();

	Ref<UDSServer> server;
	server.instantiate();

	REQUIRE_EQ(server->listen(p_path), Error::OK);
	REQUIRE(server->is_listening());
	CHECK_FALSE(server->is_connection_available());

	return server;
}

// Returns an invalid Ref and records CHECK failure if the connection cannot be
// established. Callers must check .is_valid() before using the returned value.
//
// Drives the StreamPeerSocket state machine (STATUS_CONNECTING → STATUS_CONNECTED
// or STATUS_ERROR) via poll(), bounded by POLL_LIMIT iterations — no raw time
// arithmetic. create_client() guarantees STATUS_CONNECTED on success, so callers
// can check accept_connection()'s server queue immediately without any further
// polling loop.
Ref<StreamPeerUDS> create_client(const String &p_path) {
	Ref<StreamPeerUDS> client;
	client.instantiate();

	Error err = client->connect_to_host(p_path);
	CHECK_EQ(err, Error::OK);
	if (err != Error::OK) {
		return {};
	}

	// Drive the non-blocking connect state machine.
	// poll() calls connect() again on the non-blocking socket each iteration;
	// the state machine exits STATUS_CONNECTING once the OS completes the
	// handshake (→ STATUS_CONNECTED) or the built-in timeout fires (→ STATUS_ERROR).
	for (int i = 0; i < POLL_LIMIT &&
			client->get_status() == StreamPeerUDS::STATUS_CONNECTING;
			i++) {
		client->poll();
		OS::get_singleton()->delay_usec(SLEEP_DURATION);
	}

	CHECK_MESSAGE(client->get_status() == StreamPeerUDS::STATUS_CONNECTED,
			"UDS client did not reach STATUS_CONNECTED — UDS may not be available in this environment");
	if (client->get_status() != StreamPeerUDS::STATUS_CONNECTED) {
		return {};
	}

	CHECK_EQ(client->get_connected_path(), p_path);
	return client;
}

// Accept the next pending connection from the server's queue.
// create_client() guarantees STATUS_CONNECTED before returning, which means
// the OS has already completed the UDS handshake and enqueued the connection
// on the server's accept queue — check the queue directly, no polling loop.
Ref<StreamPeerUDS> accept_connection(Ref<UDSServer> &p_server) {
	CHECK(p_server->is_connection_available());
	if (!p_server->is_connection_available()) {
		return {};
	}
	Ref<StreamPeerUDS> client_from_server = p_server->take_connection();
	CHECK(client_from_server.is_valid());
	if (!client_from_server.is_valid()) {
		return {};
	}
	CHECK_EQ(client_from_server->get_status(), StreamPeerUDS::STATUS_CONNECTED);
	return client_from_server;
}

TEST_CASE("[UDSServer] Instantiation") {
	Ref<UDSServer> server;
	server.instantiate();

	REQUIRE(server.is_valid());
	CHECK_FALSE(server->is_listening());
}

TEST_CASE("[UDSServer] Accept a connection and receive/send data") {
	Ref<UDSServer> server = create_server(SOCKET_PATH);
	Ref<StreamPeerUDS> client = create_client(SOCKET_PATH);
	if (!client.is_valid()) {
		return;
	}
	Ref<StreamPeerUDS> client_from_server = accept_connection(server);
	if (!client_from_server.is_valid()) {
		return;
	}

	// client is already STATUS_CONNECTED (guaranteed by create_client).
	CHECK_EQ(client->get_status(), StreamPeerUDS::STATUS_CONNECTED);

	// Sending data from client to server.
	const String hello_world = "Hello World!";
	client->put_string(hello_world);
	CHECK_EQ(client_from_server->get_string(), hello_world);

	// Sending data from server to client.
	const float pi = 3.1415;
	client_from_server->put_float(pi);
	CHECK_EQ(client->get_float(), pi);

	client->disconnect_from_host();
	server->stop();
	CHECK_FALSE(server->is_listening());

	cleanup_socket_file();
}

TEST_CASE("[UDSServer] Handle multiple clients at the same time") {
	Ref<UDSServer> server = create_server(SOCKET_PATH);

	Vector<Ref<StreamPeerUDS>> clients;
	for (int i = 0; i < 5; i++) {
		Ref<StreamPeerUDS> c = create_client(SOCKET_PATH);
		if (!c.is_valid()) {
			return;
		}
		clients.push_back(c);
	}

	Vector<Ref<StreamPeerUDS>> clients_from_server;
	for (int i = 0; i < clients.size(); i++) {
		Ref<StreamPeerUDS> c = accept_connection(server);
		if (!c.is_valid()) {
			return;
		}
		clients_from_server.push_back(c);
	}

	// All clients are already STATUS_CONNECTED (guaranteed by create_client).
	for (Ref<StreamPeerUDS> &c : clients) {
		CHECK_EQ(c->get_status(), StreamPeerUDS::STATUS_CONNECTED);
	}

	// Sending data from each client to server.
	for (int i = 0; i < clients.size(); i++) {
		String hello_client = "Hello " + itos(i);
		clients[i]->put_string(hello_client);
		CHECK_EQ(clients_from_server[i]->get_string(), hello_client);
	}

	for (Ref<StreamPeerUDS> &c : clients) {
		c->disconnect_from_host();
	}
	server->stop();

	cleanup_socket_file();
}

TEST_CASE("[UDSServer] When stopped shouldn't accept new connections") {
	Ref<UDSServer> server = create_server(SOCKET_PATH);
	Ref<StreamPeerUDS> client = create_client(SOCKET_PATH);
	if (!client.is_valid()) {
		return;
	}
	Ref<StreamPeerUDS> client_from_server = accept_connection(server);
	if (!client_from_server.is_valid()) {
		return;
	}

	// client is already STATUS_CONNECTED (guaranteed by create_client).
	CHECK_EQ(client->get_status(), StreamPeerUDS::STATUS_CONNECTED);

	// Sending data from client to server.
	const String hello_world = "Hello World!";
	client->put_string(hello_world);
	CHECK_EQ(client_from_server->get_string(), hello_world);

	client->disconnect_from_host();
	server->stop();
	CHECK_FALSE(server->is_listening());

	// Clean up the socket file after server stops
	cleanup_socket_file();

	// Try to connect to non-existent socket
	Ref<StreamPeerUDS> new_client;
	new_client.instantiate();
	Error err = new_client->connect_to_host(SOCKET_PATH);

	// Connection should fail since socket doesn't exist
	CHECK_NE(err, Error::OK);
	CHECK_FALSE(server->is_connection_available());

	cleanup_socket_file();
}

TEST_CASE("[UDSServer] Should disconnect client") {
	Ref<UDSServer> server = create_server(SOCKET_PATH);
	Ref<StreamPeerUDS> client = create_client(SOCKET_PATH);
	if (!client.is_valid()) {
		return;
	}
	Ref<StreamPeerUDS> client_from_server = accept_connection(server);
	if (!client_from_server.is_valid()) {
		return;
	}

	// client is already STATUS_CONNECTED (guaranteed by create_client).
	CHECK_EQ(client->get_status(), StreamPeerUDS::STATUS_CONNECTED);

	// Sending data from client to server.
	const String hello_world = "Hello World!";
	client->put_string(hello_world);
	CHECK_EQ(client_from_server->get_string(), hello_world);

	client_from_server->disconnect_from_host();
	server->stop();
	CHECK_FALSE(server->is_listening());

	// Wait for disconnection
	wait_for_condition([&]() {
		return client->poll() != Error::OK || client->get_status() == StreamPeerUDS::STATUS_NONE;
	});

	// Wait for disconnection
	wait_for_condition([&]() {
		return client_from_server->poll() != Error::OK || client_from_server->get_status() == StreamPeerUDS::STATUS_NONE;
	});

	CHECK_EQ(client->get_status(), StreamPeerUDS::STATUS_NONE);
	CHECK_EQ(client_from_server->get_status(), StreamPeerUDS::STATUS_NONE);

	ERR_PRINT_OFF;
	CHECK_EQ(client->get_string(), String());
	CHECK_EQ(client_from_server->get_string(), String());
	ERR_PRINT_ON;

	cleanup_socket_file();
}

TEST_CASE("[UDSServer] Test with different socket paths") {
	// Test with a different socket path
	const String alt_socket_path = "/tmp/godot_test_uds_socket_alt";

	// Clean up before test
	if (FileAccess::exists(alt_socket_path)) {
		DirAccess::remove_absolute(alt_socket_path);
	}

	Ref<UDSServer> server = create_server(alt_socket_path);
	Ref<StreamPeerUDS> client = create_client(alt_socket_path);
	if (!client.is_valid()) {
		return;
	}
	Ref<StreamPeerUDS> client_from_server = accept_connection(server);
	if (!client_from_server.is_valid()) {
		return;
	}

	// client is already STATUS_CONNECTED (guaranteed by create_client).
	CHECK_EQ(client->get_status(), StreamPeerUDS::STATUS_CONNECTED);

	// Test data exchange
	const int test_number = 42;
	client->put_32(test_number);
	CHECK_EQ(client_from_server->get_32(), test_number);

	client->disconnect_from_host();
	server->stop();

	// Clean up
	if (FileAccess::exists(alt_socket_path)) {
		DirAccess::remove_absolute(alt_socket_path);
	}
}

} // namespace TestUDSServer

#endif // UNIX_ENABLED
