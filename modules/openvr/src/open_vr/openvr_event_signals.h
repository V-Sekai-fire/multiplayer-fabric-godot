/**************************************************************************/
/*  openvr_event_signals.h                                                */
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

// This macro is used to define signals for each VREvent to make it impossible for the list of signals to get out of sync with
// the events. The name of the signal is automatically derived from the EVREventType. This would normally be impossible since
// there is no way to introspect the name of enum members. While IVRSystem provides GetEventTypeNameFromEnum, this would
// require connecting to OpenVR before creating our signals which makes the experience in the editor less than ideal.
#define VREVENT_SIGNAL(vrevent_id, vrevent_type, source)                             \
	{                                                                                \
		String name = String(#vrevent_id).trim_prefix("vr::EVREventType::VREvent_"); \
		ADD_SIGNAL(MethodInfo(name,                                                  \
				PropertyInfo(Variant::INT, "eventAgeSeconds"),                       \
				PropertyInfo(Variant::OBJECT, "positionalTracker"),                  \
				PropertyInfo(Variant::DICTIONARY, "data")));                         \
		openvr_data::register_event_signal(vrevent_id, vrevent_type, name);          \
	}
