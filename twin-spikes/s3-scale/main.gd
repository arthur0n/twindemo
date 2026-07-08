extends Node3D
## SPIKE S3 — MultiMesh scale ceiling: single vs region-chunked, frustum+occlusion culling.
## Auto-advances through {mode x count x camera} configs, measures ~8 s each after a 2 s
## warmup, writes results.json incrementally, saves a screenshot per config, then quits.

const CHUNKS := 8                    # 8x8 chunk grid in chunked mode
const SPACING := 2.0                 # world units between instances
const WARMUP_S := 2.0
const MEASURE_S := 8.0
const COUNTS: Array[int] = [100000, 500000, 1000000]
const MODES: Array[String] = ["single", "chunked"]
const CAMS: Array[String] = ["inside", "overview"]

var camera: Camera3D
var gen_root: Node3D
var box_mesh: BoxMesh
var cyl_mesh: CylinderMesh
var results: Array = []

# per-count transform cache (rebuilt when count changes, shared by both modes)
var cache_count := -1
var chunk_box: Array[PackedFloat32Array] = []
var chunk_cyl: Array[PackedFloat32Array] = []
var side_len := 0.0


func _ready() -> void:
	print("[gpu] ", RenderingServer.get_video_adapter_name(), " | ",
		RenderingServer.get_current_rendering_driver_name())
	print("[occlusion] project setting = ",
		ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling"))
	if not OS.has_feature("web"):
		# macOS suspends drawing when the window is fully occluded, which freezes
		# frame_post_draw and turns process-frame FPS into a phantom number. Keep
		# the window on top and frontmost for the whole sweep.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		DisplayServer.window_move_to_foreground()
	_setup_static()
	if OS.has_feature("web"):
		_run_web_demo()
	elif OS.get_cmdline_user_args().has("occ-off"):
		# Control run: frustum-only culling, to isolate occlusion's contribution.
		get_viewport().use_occlusion_culling = false
		_run_occ_off()
	else:
		_run_all()


func _run_occ_off() -> void:
	_gen_cache(1000000)
	_build_scene("chunked")
	_place_camera("inside")
	await _wait_s(WARMUP_S)
	var row := await _measure(1000000, "chunked-occ-off", "inside")
	print("[row] ", JSON.stringify(row))
	var fa := FileAccess.open("res://results_occoff.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify([row], "  "))
	fa.close()
	print("[done] occ-off control complete")
	get_tree().quit()


## Web build: fixed 500k chunked config, overview camera, FPS label, runs forever.
func _run_web_demo() -> void:
	_gen_cache(500000)
	_build_scene("chunked")
	_place_camera("overview")
	var label := Label.new()
	label.position = Vector2(8, 8)
	add_child(label)
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(func() -> void:
		label.text = "500k chunked | %.0f fps | %d draw calls" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _setup_static() -> void:
	gen_root = Node3D.new()
	gen_root.name = "Generated"
	add_child(gen_root)

	box_mesh = BoxMesh.new()  # unit box, scaled per instance
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(0.55, 0.58, 0.62)
	box_mesh.material = box_mat

	cyl_mesh = CylinderMesh.new()  # low-poly "pipe"
	cyl_mesh.radial_segments = 6
	cyl_mesh.rings = 1
	var cyl_mat := StandardMaterial3D.new()
	cyl_mat.albedo_color = Color(0.75, 0.45, 0.2)
	cyl_mesh.material = cyl_mat

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.shadow_enabled = false  # isolate instancing/culling cost from shadow passes
	add_child(light)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	camera = Camera3D.new()
	camera.far = 12000.0
	add_child(camera)
	camera.make_current()

	_build_room()


## Occluder room at world center: 4 walls (one with a doorway) + ceiling.
## Each wall = visible BoxMesh + OccluderInstance3D with a matching BoxOccluder3D.
## No baking needed: explicit occluder shapes work at runtime; baking is only for
## generating occluders from arbitrary meshes.
func _build_room() -> void:
	var walls := [
		# [size, position]
		[Vector3(0.3, 6, 20), Vector3(10, 3, 0)],    # +X wall
		[Vector3(0.3, 6, 20), Vector3(-10, 3, 0)],   # -X wall
		[Vector3(20, 6, 0.3), Vector3(0, 3, -10)],   # -Z wall (solid)
		[Vector3(8, 6, 0.3), Vector3(-6, 3, 10)],    # +Z wall, left of door
		[Vector3(8, 6, 0.3), Vector3(6, 3, 10)],     # +Z wall, right of door (4 u doorway)
		[Vector3(20, 0.3, 20), Vector3(0, 6, 0)],    # ceiling
	]
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.35, 0.37, 0.4)
	for w in walls:
		var size: Vector3 = w[0]
		var pos: Vector3 = w[1]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = wall_mat
		mi.mesh = bm
		mi.position = pos
		add_child(mi)
		var oi := OccluderInstance3D.new()
		var occ := BoxOccluder3D.new()
		occ.size = size
		oi.occluder = occ
		oi.position = pos
		add_child(oi)


func _run_all() -> void:
	for count in COUNTS:
		_gen_cache(count)
		for mode in MODES:
			_build_scene(mode)
			for cam in CAMS:
				_place_camera(cam)
				await _wait_s(WARMUP_S)
				var row := await _measure(count, mode, cam)
				results.append(row)
				_write_results()
				print("[row] ", JSON.stringify(row))
				await _screenshot("%s_%d_%s" % [mode, count, cam])
	print("[done] all configs complete")
	get_tree().quit()


## Deterministic factory layout, generated chunk-wise so chunked mode gets per-chunk
## buffers and single mode concatenates the same data (identical geometry, fair compare).
func _gen_cache(count: int) -> void:
	if cache_count == count:
		return
	var t0 := Time.get_ticks_msec()
	cache_count = count
	chunk_box.clear()
	chunk_cyl.clear()
	var per_chunk := count / (CHUNKS * CHUNKS)
	var grid := int(ceil(sqrt(float(per_chunk))))
	var chunk_side := grid * SPACING
	side_len = chunk_side * CHUNKS
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var n_cyl := int(ceil(per_chunk / 4.0))  # every 4th instance is a pipe
	var n_box := per_chunk - n_cyl
	for cz in CHUNKS:
		for cx in CHUNKS:
			var bb := PackedFloat32Array()
			bb.resize(n_box * 12)
			var cb := PackedFloat32Array()
			cb.resize(n_cyl * 12)
			var ox := (cx - CHUNKS / 2.0) * chunk_side
			var oz := (cz - CHUNKS / 2.0) * chunk_side
			var bi := 0
			var ci := 0
			for i in per_chunk:
				@warning_ignore("integer_division")
				var x := ox + (i % grid) * SPACING + rng.randf_range(-0.4, 0.4)
				@warning_ignore("integer_division")
				var z := oz + (i / grid) * SPACING + rng.randf_range(-0.4, 0.4)
				if i % 4 == 0:
					# horizontal pipe: cylinder axis (Y) rotated onto X, thin + long
					var basis := Basis(Vector3(0, 0, 1), PI / 2.0) \
						* Basis.from_scale(Vector3(0.3, 0.9, 0.3))
					_put(cb, ci, Transform3D(basis, Vector3(x, 2.5, z)))
					ci += 12
				else:
					var h := rng.randf_range(0.5, 3.0)
					var basis := Basis.from_scale(Vector3(
						rng.randf_range(0.6, 1.6), h, rng.randf_range(0.6, 1.6)))
					_put(bb, bi, Transform3D(basis, Vector3(x, h / 2.0, z)))
					bi += 12
			chunk_box.append(bb)
			chunk_cyl.append(cb)
	print("[gen] count=%d per_chunk=%d side=%.0f in %d ms"
		% [count, per_chunk, side_len, Time.get_ticks_msec() - t0])


## MultiMesh.buffer layout for TRANSFORM_3D (no color/custom): 12 floats per instance,
## the 3x4 transform row-major (basis columns x/y/z + origin as 4th column).
func _put(buf: PackedFloat32Array, o: int, xf: Transform3D) -> void:
	var b := xf.basis
	buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = xf.origin.x
	buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = xf.origin.y
	buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = xf.origin.z


func _build_scene(mode: String) -> void:
	var t0 := Time.get_ticks_msec()
	for c in gen_root.get_children():
		gen_root.remove_child(c)
		c.free()
	if mode == "single":
		var all_box := PackedFloat32Array()
		var all_cyl := PackedFloat32Array()
		for buf in chunk_box:
			all_box.append_array(buf)
		for buf in chunk_cyl:
			all_cyl.append_array(buf)
		_add_mmi(box_mesh, all_box)
		_add_mmi(cyl_mesh, all_cyl)
	else:
		for i in chunk_box.size():
			_add_mmi(box_mesh, chunk_box[i])
			_add_mmi(cyl_mesh, chunk_cyl[i])
	print("[scene] mode=%s nodes=%d in %d ms"
		% [mode, gen_root.get_child_count(), Time.get_ticks_msec() - t0])


func _add_mmi(mesh: Mesh, buf: PackedFloat32Array) -> void:
	if buf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = buf.size() / 12  # must be set BEFORE buffer
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gen_root.add_child(mmi)


func _place_camera(cam: String) -> void:
	if cam == "inside":
		camera.position = Vector3(0, 1.7, 0)
		camera.look_at(Vector3(-6, 1.5, -6))  # toward the solid room corner
	else:
		var d := side_len * 0.55
		camera.position = Vector3(d, side_len * 0.5, d)
		camera.look_at(Vector3.ZERO)


func _wait_s(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * 1000.0:
		await get_tree().process_frame


func _measure(count: int, mode: String, cam: String) -> Dictionary:
	var frames := 0
	var dc := 0.0
	var prim := 0.0
	var obj := 0.0
	var tp := 0.0
	var drawn0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	while true:
		await get_tree().process_frame
		frames += 1
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		tp += Performance.get_monitor(Performance.TIME_PROCESS)
		if Time.get_ticks_usec() - t0 >= MEASURE_S * 1e6:
			break
	var el := (Time.get_ticks_usec() - t0) / 1e6
	var f := float(frames)
	var drawn := float(Engine.get_frames_drawn() - drawn0)  # frames actually rendered
	return {
		"mode": mode,
		"count": count,
		"camera": cam,
		"fps": snappedf(drawn / el, 0.1),
		"process_fps": snappedf(f / el, 0.1),
		"frame_ms": snappedf(el * 1000.0 / maxf(drawn, 1.0), 0.01),
		"draw_calls": int(dc / f),
		"primitives": int(prim / f),
		"objects_rendered": int(obj / f),
		"time_process_ms": snappedf(tp / f * 1000.0, 0.01),
	}


func _write_results() -> void:
	var fa := FileAccess.open("res://results.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(results, "  "))
	fa.close()


func _screenshot(name: String) -> void:
	# Bounded wait for a freshly drawn frame; never hang if drawing is suspended
	# (frame_post_draw stops firing when macOS occludes the window).
	var drawn0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == drawn0 and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	if Engine.get_frames_drawn() == drawn0:
		print("[shot] SKIPPED (no frame drawn) ", name)
		return
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://shots/%s.png" % name)
	img.save_png(path)
	print("[shot] ", path)
