/**************************************************************************/
/*  xr_interface_openvr.h                                                 */
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

////////////////////////////////////////////////////////////////////////////////////////////////
// Our main XRInterface code for our OpenVR GDExtension module

#ifndef XR_INTERFACE_OPENVR_H
#define XR_INTERFACE_OPENVR_H

#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/xr_interface_extension.hpp>
#include <godot_cpp/classes/xr_server.hpp>
#include <godot_cpp/core/binder_common.hpp>

#include "openvr_data.h"

namespace godot {
class XRInterfaceOpenVR : public XRInterfaceExtension {
	GDCLASS(XRInterfaceOpenVR, XRInterfaceExtension);

protected:
	static void _bind_methods();

private:
	XRServer *xr_server = nullptr;
	openvr_data *ovr = nullptr;
	uint32_t width = 0;
	uint32_t height = 0;

	RID texture_rid;

public:
	// Properties
	int get_application_type() const;
	void set_application_type(int p_type);

	int get_tracking_universe() const;
	void set_tracking_universe(int p_universe);

	bool set_action_manifest_path(const String p_path);

	void register_action_set(const String p_action_set);
	void set_action_set_active(const String p_action_set, const bool p_is_active);
	bool is_action_set_active(const String p_action_set) const;

	bool play_area_available() const;
	PackedVector3Array get_play_area() const;

	float get_device_battery_percentage(vr::TrackedDeviceIndex_t p_tracked_device_index);
	bool is_device_charging(vr::TrackedDeviceIndex_t p_tracked_device_index);

	// Functions
	virtual StringName _get_name() const override;
	virtual uint32_t _get_capabilities() const override;

	virtual bool _is_initialized() const override;
	virtual bool _initialize() override;
	virtual void _uninitialize() override;

	virtual XRInterface::TrackingStatus _get_tracking_status() const override;
	virtual void _trigger_haptic_pulse(const String &action_name, const StringName &tracker_name, double frequency, double amplitude, double duration_sec, double delay_sec) override;

	virtual Vector2 _get_render_target_size() override;
	virtual uint32_t _get_view_count() override;
	virtual Transform3D _get_camera_transform() override;
	virtual Transform3D _get_transform_for_view(uint32_t p_view, const Transform3D &p_cam_transform) override;
	virtual PackedFloat64Array _get_projection_for_view(uint32_t p_view, double p_aspect, double p_z_near, double p_z_far) override;

	virtual void _process() override;
	virtual void _post_draw_viewport(const RID &render_target, const Rect2 &screen_rect) override;
	virtual void _end_frame() override;

	Array get_render_model_names();
	Ref<ArrayMesh> load_render_model(String p_model_name);
	Array load_render_model_components(String p_model_name);

	XRInterfaceOpenVR();
	~XRInterfaceOpenVR();
};
} // namespace godot

#endif /* !XR_INTERFACE_OPENVR_H */
