/**************************************************************************/
/*  openvr_overlay_container.h                                            */
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

#include "openvr_data.h"
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/sub_viewport_container.hpp>
#include <godot_cpp/templates/hash_set.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace godot {
class OpenVROverlayContainer : public SubViewportContainer {
	GDCLASS(OpenVROverlayContainer, SubViewportContainer)

private:
	openvr_data *ovr;
	vr::VROverlayHandle_t overlay;
	int overlay_id;

	float overlay_width_in_meters;
	bool overlay_visible;
	HashSet<vr::VROverlayFlags> initial_flags;

	String tracked_device_name;
	Transform3D absolute_position; // Used when tracked_device == ""
	Transform3D tracked_device_relative_position; // Used when tracked_device != ""

	void on_frame_post_draw();
	void draw_overlay(const Ref<Texture2D> &p_texture);

	bool update_overlay_transform();

protected:
	static void _bind_methods();

public:
	OpenVROverlayContainer();
	~OpenVROverlayContainer();

	void _notification(int p_what);

	bool get_flag(vr::VROverlayFlags p_flag);
	void set_flag(vr::VROverlayFlags p_flag, bool p_state);

	float get_overlay_width_in_meters();
	void set_overlay_width_in_meters(float p_new_size);

	bool is_overlay_visible();
	void set_overlay_visible(bool p_visible);

	String get_tracked_device_name();
	void set_tracked_device_name(String p_tracked_device_name);

	Transform3D get_absolute_position();
	void set_absolute_position(Transform3D p_position);

	Transform3D get_tracked_device_relative_position();
	void set_tracked_device_relative_position(Transform3D p_position);
};
} // namespace godot

VARIANT_ENUM_CAST(vr::VROverlayFlags);
