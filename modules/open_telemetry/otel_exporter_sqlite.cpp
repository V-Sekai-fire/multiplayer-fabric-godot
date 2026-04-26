/**************************************************************************/
/*  otel_exporter_sqlite.cpp                                              */
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

// godot_sqlite.h is included ONLY here — callers of otel_exporter_sqlite.h
// see only Ref<RefCounted>; this file is the only one that casts them back.
#include "../sqlite/src/godot_sqlite.h"

#include "otel_exporter_sqlite.h"
#include "structures/otel_span.h"

#include "core/variant/array.h"

// ── helpers ───────────────────────────────────────────────────────────────────

// Cast the opaque _db ref back to SQLite* for internal use.
static SQLite *_as_db(const Ref<RefCounted> &p_ref) {
	return Object::cast_to<SQLite>(p_ref.ptr());
}

static SQLiteQuery *_as_query(const Ref<RefCounted> &p_ref) {
	return Object::cast_to<SQLiteQuery>(p_ref.ptr());
}

// Execute a one-shot DDL statement (CREATE TABLE / INDEX).
static bool _exec(SQLite *p_db, const String &p_sql) {
	Ref<SQLiteQuery> q = p_db->create_query(p_sql);
	ERR_FAIL_COND_V(q.is_null(), false);
	Variant result = q->execute(Array());
	// execute() returns null on success for non-SELECT queries.
	return true;
}

// Minimal JSON serialisation for span attributes (Dictionary of Variant).
static String _attrs_to_json(const Dictionary &p_attrs) {
	if (p_attrs.is_empty()) {
		return "{}";
	}
	String out = "{";
	bool first = true;
	for (int i = 0; i < p_attrs.size(); i++) {
		Variant key = p_attrs.get_key_at_index(i);
		Variant val = p_attrs.get_value_at_index(i);
		if (!first) {
			out += ",";
		}
		first = false;
		out += "\"" + String(key).json_escape() + "\":";
		switch (val.get_type()) {
			case Variant::BOOL:
				out += (bool)val ? "true" : "false";
				break;
			case Variant::INT:
				out += itos((int64_t)val);
				break;
			case Variant::FLOAT:
				out += rtos((double)val);
				break;
			case Variant::STRING:
			case Variant::STRING_NAME:
				out += "\"" + String(val).json_escape() + "\"";
				break;
			default:
				out += "null";
				break;
		}
	}
	return out + "}";
}

// ── schema & statements ───────────────────────────────────────────────────────

Error OTelExporterSQLite::_apply_schema() {
	SQLite *db = _as_db(_db);
	ERR_FAIL_NULL_V(db, FAILED);

	_exec(db, "PRAGMA journal_mode=WAL;");
	_exec(db, "PRAGMA synchronous=NORMAL;");

	_exec(db,
			"CREATE TABLE IF NOT EXISTS traces("
			"  trace_id             TEXT    PRIMARY KEY,"
			"  service              TEXT    NOT NULL DEFAULT '',"
			"  start_time_unix_nano INTEGER NOT NULL DEFAULT 0"
			");");

	_exec(db,
			"CREATE TABLE IF NOT EXISTS spans("
			"  span_id              TEXT    PRIMARY KEY,"
			"  trace_id             TEXT    NOT NULL,"
			"  parent_span_id       TEXT    NOT NULL DEFAULT '',"
			"  name                 TEXT    NOT NULL,"
			"  kind                 INTEGER NOT NULL DEFAULT 0,"
			"  start_time_unix_nano INTEGER NOT NULL DEFAULT 0,"
			"  end_time_unix_nano   INTEGER NOT NULL DEFAULT 0,"
			"  duration_nano        INTEGER NOT NULL DEFAULT 0,"
			"  status_code          INTEGER NOT NULL DEFAULT 0,"
			"  status_message       TEXT    NOT NULL DEFAULT '',"
			"  attrs_json           TEXT    NOT NULL DEFAULT '{}'"
			");");

	_exec(db, "CREATE INDEX IF NOT EXISTS idx_spans_trace ON spans(trace_id);");
	_exec(db, "CREATE INDEX IF NOT EXISTS idx_spans_start ON spans(start_time_unix_nano);");
	return OK;
}

Error OTelExporterSQLite::_prepare_statements() {
	SQLite *db = _as_db(_db);
	ERR_FAIL_NULL_V(db, FAILED);

	_q_upsert_trace = db->create_query(
			"INSERT OR REPLACE INTO traces(trace_id, service, start_time_unix_nano)"
			" VALUES(?, ?, ?);");
	ERR_FAIL_COND_V(_q_upsert_trace.is_null(), FAILED);

	_q_upsert_span = db->create_query(
			"INSERT OR REPLACE INTO spans("
			"  span_id, trace_id, parent_span_id, name, kind,"
			"  start_time_unix_nano, end_time_unix_nano, duration_nano,"
			"  status_code, status_message, attrs_json"
			") VALUES(?,?,?,?,?,?,?,?,?,?,?);");
	ERR_FAIL_COND_V(_q_upsert_span.is_null(), FAILED);

	return OK;
}

// ── span insert ───────────────────────────────────────────────────────────────

Error OTelExporterSQLite::_upsert_span(const Ref<OTelSpan> &p_span) {
	ERR_FAIL_COND_V(p_span.is_null(), FAILED);

	SQLiteQuery *q_trace = _as_query(_q_upsert_trace);
	SQLiteQuery *q_span = _as_query(_q_upsert_span);
	ERR_FAIL_NULL_V(q_trace, FAILED);
	ERR_FAIL_NULL_V(q_span, FAILED);

	uint64_t t0 = p_span->get_start_time_unix_nano();
	uint64_t t1 = p_span->get_end_time_unix_nano();
	int64_t dur = (t1 >= t0) ? (int64_t)(t1 - t0) : 0;

	// Upsert trace row (idempotent — service field left blank; callers can
	// UPDATE it separately if they track service names).
	Array trace_args;
	trace_args.push_back(p_span->get_trace_id());
	trace_args.push_back("");
	trace_args.push_back((int64_t)t0);
	q_trace->execute(trace_args);

	// Upsert span row.
	Array span_args;
	span_args.push_back(p_span->get_span_id());
	span_args.push_back(p_span->get_trace_id());
	span_args.push_back(p_span->get_parent_span_id());
	span_args.push_back(p_span->get_name());
	span_args.push_back((int)p_span->get_kind());
	span_args.push_back((int64_t)t0);
	span_args.push_back((int64_t)t1);
	span_args.push_back(dur);
	span_args.push_back((int)p_span->get_status_code());
	span_args.push_back(p_span->get_status_message());
	span_args.push_back(_attrs_to_json(p_span->get_attributes()));
	q_span->execute(span_args);

	return OK;
}

// ── public API ────────────────────────────────────────────────────────────────

OTelExporterSQLite::OTelExporterSQLite() {}

OTelExporterSQLite::~OTelExporterSQLite() {
	close();
}

Error OTelExporterSQLite::open(const String &p_path) {
	close();
	_last_error = "";
	Ref<SQLite> db;
	db.instantiate();
	if (!db->open(p_path)) {
		_last_error = db->get_last_error_message();
		return FAILED;
	}
	_db = db;
	_db_path = p_path;
	if (_apply_schema() != OK || _prepare_statements() != OK) {
		close();
		return FAILED;
	}
	return OK;
}

Error OTelExporterSQLite::open_in_memory() {
	close();
	_last_error = "";
	Ref<SQLite> db;
	db.instantiate();
	if (!db->open_in_memory()) {
		_last_error = db->get_last_error_message();
		return FAILED;
	}
	_db = db;
	_db_path = ":memory:";
	if (_apply_schema() != OK || _prepare_statements() != OK) {
		close();
		return FAILED;
	}
	return OK;
}

void OTelExporterSQLite::close() {
	_q_upsert_trace = Ref<RefCounted>();
	_q_upsert_span = Ref<RefCounted>();
	_db = Ref<RefCounted>();
	_db_path = "";
}

bool OTelExporterSQLite::is_open() const {
	return _db.is_valid();
}

String OTelExporterSQLite::get_db_path() const {
	return _db_path;
}

String OTelExporterSQLite::get_last_error() const {
	return _last_error;
}

Error OTelExporterSQLite::export_traces(Ref<OTelState> p_state) {
	ERR_FAIL_COND_V(!is_open(), ERR_FILE_NOT_FOUND);
	ERR_FAIL_COND_V(p_state.is_null(), ERR_INVALID_PARAMETER);

	SQLite *db = _as_db(_db);
	ERR_FAIL_NULL_V(db, FAILED);

	TypedArray<OTelSpan> spans = p_state->get_spans();
	if (spans.is_empty()) {
		return OK;
	}

	_exec(db, "BEGIN;");
	Error err = OK;
	for (int i = 0; i < spans.size(); i++) {
		Ref<OTelSpan> span = spans[i];
		if (span.is_null() || !span->is_ended()) {
			continue;
		}
		if (_upsert_span(span) != OK) {
			err = FAILED;
			break;
		}
	}
	_exec(db, err == OK ? "COMMIT;" : "ROLLBACK;");
	return err;
}

Error OTelExporterSQLite::export_traces_and_clear(Ref<OTelState> p_state) {
	Error err = export_traces(p_state);
	if (err == OK && p_state.is_valid()) {
		p_state->clear_spans();
	}
	return err;
}

// ── bindings ──────────────────────────────────────────────────────────────────

void OTelExporterSQLite::_bind_methods() {
	ClassDB::bind_method(D_METHOD("open", "path"), &OTelExporterSQLite::open);
	ClassDB::bind_method(D_METHOD("open_in_memory"), &OTelExporterSQLite::open_in_memory);
	ClassDB::bind_method(D_METHOD("close"), &OTelExporterSQLite::close);
	ClassDB::bind_method(D_METHOD("is_open"), &OTelExporterSQLite::is_open);
	ClassDB::bind_method(D_METHOD("get_db_path"), &OTelExporterSQLite::get_db_path);
	ClassDB::bind_method(D_METHOD("get_last_error"), &OTelExporterSQLite::get_last_error);
	ClassDB::bind_method(D_METHOD("export_traces", "state"), &OTelExporterSQLite::export_traces);
	ClassDB::bind_method(D_METHOD("export_traces_and_clear", "state"), &OTelExporterSQLite::export_traces_and_clear);
}
