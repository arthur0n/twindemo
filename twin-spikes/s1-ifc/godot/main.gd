extends Node3D
# SPIKE S1 render evidence: load GLB, frame it, save a screenshot, quit.

const GLB := "res://../duplex.glb"
const SHOT := "res://../screenshot.png"


func _ready() -> void:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(ProjectSettings.globalize_path(GLB), state)
	if err != OK:
		push_error("GLB load failed")
		get_tree().quit(1)
		return
	var scene := gltf.generate_scene(state)
	add_child(scene)

	# Bounding box of everything.
	var aabb := AABB()
	var first := true
	for m in find_children("*", "MeshInstance3D", true, false):
		var b: AABB = m.global_transform * m.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.14, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	var center := aabb.get_center()
	var dist: float = aabb.get_longest_axis_size() * 0.55
	cam.position = center + Vector3(dist * 0.8, dist * 0.55, dist * 0.8)
	add_child(cam)
	cam.look_at(center)
	cam.current = true

	for i in 8:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(SHOT))
	print("SCREENSHOT_SAVED size=%dx%d" % [img.get_width(), img.get_height()])
	get_tree().quit(0)
