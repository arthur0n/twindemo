# core/element_picker.gd — left-click-release ray-vs-AABB picker.
# Resolves the hit MeshInstance3D to an IFC GlobalId via GlobalIdHelper (the ONE join rule),
# then emits element_picked(globalid). Does NOT fire on a camera drag (suppressed when the
# mouse moved past DRAG_THRESHOLD_PX pixels between press and release).
#
# Place as a child of Main (a sibling of CameraRig). No autoload; signals up.
class_name ElementPicker
extends Node

## Emitted when the user left-click-releases on a mesh that resolves to a GlobalId.
signal element_picked(globalid: String)

## Pixels of mouse travel that separate a click from a drag.
const DRAG_THRESHOLD_PX := 4.0

## IFC base64 alphabet length — mirrors GlobalIdHelper.GLOBALID_LEN.
const _GLOBALID_LEN := GlobalIdHelper.GLOBALID_LEN

## The Camera3D used for raycasting. Set externally by main.gd after scene ready so the
## picker does not hard-code a node path.
var active_camera: Camera3D = null

var _press_pos := Vector2.ZERO
var _dragged := false


func _unhandled_input(event: InputEvent) -> void:
	var btn := event as InputEventMouseButton
	if btn != null and btn.button_index == MOUSE_BUTTON_LEFT:
		if btn.pressed:
			_press_pos = btn.position
			_dragged = false
		else:
			if not _dragged:
				_try_pick(btn.position)
		return

	var motion := event as InputEventMouseMotion
	if motion != null and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if (motion.position - _press_pos).length() > DRAG_THRESHOLD_PX:
			_dragged = true


func _try_pick(screen_pos: Vector2) -> void:
	if active_camera == null:
		return
	var viewport := active_camera.get_viewport()
	if viewport == null:
		return

	var root := _model_root()
	if root == null:
		return

	var ray_origin := active_camera.project_ray_origin(screen_pos)
	var ray_dir := active_camera.project_ray_normal(screen_pos)

	var best_dist := INF
	var best_node: MeshInstance3D = null

	for child: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or not mi.visible:
			continue
		var local_origin := mi.global_transform.affine_inverse() * ray_origin
		var local_dir := mi.global_transform.basis.inverse() * ray_dir
		var aabb := mi.get_aabb()
		# intersects_ray returns Variant: null = miss, Vector3 = hit point (Godot 4 API).
		# SEAM: duck-typed return from AABB.intersects_ray — Variant-typed by engine contract.
		@warning_ignore("return_value_discarded")
		var hit_result: Variant = aabb.intersects_ray(local_origin, local_dir)
		if hit_result == null:
			continue
		# Confirmed non-null; safe to convert. Vector3 constructor accepts a Variant Vector3.
		# SEAM: engine Variant → Vector3 — AABB.intersects_ray guarantees Vector3 when non-null.
		@warning_ignore("unsafe_cast")
		var hit_local: Vector3 = hit_result as Vector3
		var hit_world := mi.global_transform * hit_local
		var dist := ray_origin.distance_to(hit_world)
		if dist < best_dist:
			best_dist = dist
			best_node = mi

	if best_node == null:
		return

	var gid := GlobalIdHelper.globalid_for_node(best_node)
	if gid.length() == _GLOBALID_LEN:
		emit_signal("element_picked", gid)


# Locate the ModelHost node in the current scene (unique name "ModelHost").
# Returns null when no model is loaded — pick silently does nothing.
func _model_root() -> Node3D:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return null
	var found := scene_root.find_child("ModelHost", true, false)
	if found is Node3D:
		return found as Node3D
	return null
