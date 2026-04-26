/**************************************************************************/
/*  otel_exporter_sqlite.h                                                */
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

// godot_sqlite.h is intentionally NOT included here.
// SQLite and SQLiteQuery are stored as Ref<RefCounted> so callers of this
// header never see the SQLite module's types — they stay an implementation
// detail confined to otel_exporter_sqlite.cpp.

#include "otel_state.h"
#include "core/io/resource.h"
#include "core/object/ref_counted.h"

// OTelExporterSQLite — persists OTel spans to a SQLite database.
//
// Uses the sibling modules/sqlite module internally; none of its types
// appear in this header or in the GDScript API.
//
// Schema (auto-created on open()):
//
//   traces(trace_id TEXT PK, service TEXT, start_time_unix_nano INTEGER)
//
//   spans(span_id              TEXT PRIMARY KEY,
//         trace_id             TEXT NOT NULL,
//         parent_span_id       TEXT NOT NULL DEFAULT '',
//         name                 TEXT NOT NULL,
//         kind                 INTEGER NOT NULL DEFAULT 0,
//         start_time_unix_nano INTEGER NOT NULL DEFAULT 0,
//         end_time_unix_nano   INTEGER NOT NULL DEFAULT 0,
//         duration_nano        INTEGER NOT NULL DEFAULT 0,
//         status_code          INTEGER NOT NULL DEFAULT 0,
//         status_message       TEXT NOT NULL DEFAULT '',
//         attrs_json           TEXT NOT NULL DEFAULT '{}')
//
// INSERT OR REPLACE is used throughout so re-exporting the same state
// is idempotent (safe to call after a failed partial flush).
class OTelExporterSQLite : public Resource {
	GDCLASS(OTelExporterSQLite, Resource);

private:
	// SQLite and SQLiteQuery are stored as their base class so this header
	// never needs to include godot_sqlite.h.  The .cpp casts them back.
	Ref<RefCounted> _db;
	Ref<RefCounted> _q_upsert_trace;
	Ref<RefCounted> _q_upsert_span;

	String _db_path;
	String _last_error;

	Error _apply_schema();
	Error _prepare_statements();
	Error _upsert_span(const Ref<OTelSpan> &p_span);

protected:
	static void _bind_methods();

public:
	OTelExporterSQLite();
	~OTelExporterSQLite();

	// ── Lifecycle ──────────────────────────────────────────────────────────
	Error open(const String &p_path);
	Error open_in_memory();
	void close();
	bool is_open() const;
	String get_db_path() const;
	String get_last_error() const;

	// ── Export ─────────────────────────────────────────────────────────────
	// Write all ended spans in p_state to the database.
	Error export_traces(Ref<OTelState> p_state);
	// export_traces + state->clear_spans() atomically.
	Error export_traces_and_clear(Ref<OTelState> p_state);
};
