extends Node3D
## web_bench.gd — browser fps-ceiling overlay for the twin viewer (Phase 1, Nice-to-Have #6).
##
## Loads one bench scene (duplex | city), injects a fixed camera vantage (street | aerial —
## the SAME coordinates as the native optimizer benchmark so columns are comparable), wires the
## real DataBus + binding runtime so measurement runs with LIVE binding active, then measures
## Engine.get_frames_drawn() deltas + frame time over a fixed window and emits ONE
##   BENCH: {json}
## line via JavaScriptBridge.console.log (scraped by the CDP driver) AND paints it on-screen as
## text (read from a screenshot for browsers with no console access, e.g. Safari).
##
## Config comes from the URL query in a web build (?scene=duplex&vantage=street&build=threads),
## or from `--scene= --vantage= --build=` user args on desktop (sanity runs). Fixed vantage
## coordinates and warmup/measure windows keep every run honest and repeatable.

const DataBusScript := preload("res://core/data_bus.gd")
const BindingMapScript := preload("res://core/binding_map.gd")

const DEFAULT_WARMUP_S := 3.0
const DEFAULT_MEASURE_S := 8.0
const CAM_FAR_M := 12000.0
const UP_PARALLEL_DOT := 0.999
const SNAP_FPS := 0.1
const SNAP_MS := 0.01
const MSEC_PER_SEC := 1000.0
const USEC_PER_SEC := 1_000_000.0
const MIN_DRAWN := 1.0

# scene -> res path. `city` = c2-optimized (instanced, ~1k objects, natively at the display cap);
# `ucity` = the many-unique-mesh worst case (28,600 individual meshes, no instancing) — the heavy
# GPU stress that actually breaks the frame-time cap, so the ceiling has a sub-cap differentiator.
const SCENES := {
	"duplex": "res://models/duplex.tscn",
	"city": "res://models/city.scn",
	"ucity": "res://models/ucity.scn",
}

# scene -> vantage -> "X,Y,Z:LX,LY,LZ" (position : look-at target).
# duplex vantages are the AABB-derived ones from the vis-range sweep; city vantages are the
# native optimizer-benchmark coordinates (byte-identical to twin-optimizer-benchmark-2026-07-08).
const VANTAGES := {
	"duplex": {
		"street": "4.4,1.7,-12:4.4,1.7,24",
		"aerial": "-40,55,-35:4.4,3.7,8.9",
	},
	"city": {
		"street": "139.5,1.7,135:139.5,1.7,0",
		"aerial": "-65,260,-65:135,15,135",
	},
	"ucity": {
		"street": "139.5,1.7,135:139.5,1.7,0",
		"aerial": "-65,260,-65:135,15,135",
	},
}

var scene_name := "duplex"
var vantage_name := "street"
var build_label := "unknown"
var warmup_s := DEFAULT_WARMUP_S
var measure_s := DEFAULT_MEASURE_S

var _data_bus: DataBusScript
var _binder: BindingMapScript
var _hud: Label
var _load_ms := 0.0
var _first_frame_seen := false


func _ready() -> void:
	_read_config()
	_build_env()
	_load_scene()
	_apply_vantage()
	_wire_binding()
	_build_hud()
	_data_bus = get_node("/root/DataBus")
	# Viewport render-time measurement — the sub-cap differentiator. When rAF/vsync pins fps at
	# the 120 Hz display cap, gpu_ms/cpu_ms still separate a light scene from a heavy one (same
	# logic as the native bench_scene.gd). Returns 0 if the WebGL2 backend lacks timer queries.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	# HUD ticker so a human watching sees it is alive before the BENCH line lands.
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	add_child(t)
	t.timeout.connect(_tick_hud)
	_run()


func _read_config() -> void:
	var q := _query_params()
	scene_name = q.get("scene", _arg("scene", "duplex"))
	vantage_name = q.get("vantage", _arg("vantage", "street"))
	build_label = q.get("build", _arg("build", "unknown"))
	warmup_s = float(q.get("warmup", _arg("warmup", str(DEFAULT_WARMUP_S))))
	measure_s = float(q.get("measure", _arg("measure", str(DEFAULT_MEASURE_S))))
	if not SCENES.has(scene_name):
		scene_name = "duplex"
	if not VANTAGES[scene_name].has(vantage_name):
		vantage_name = "street"


## URL query params (web only), lowercased keys. Empty on desktop.
func _query_params() -> Dictionary:
	var out := {}
	if not OS.has_feature("web"):
		return out
	var raw: Variant = JavaScriptBridge.eval("window.location.search", true)
	if typeof(raw) != TYPE_STRING:
		return out
	var s: String = raw
	if s.begins_with("?"):
		s = s.substr(1)
	for pair: String in s.split("&", false):
		var kv := pair.split("=")
		if kv.size() == 2:
			out[kv[0].to_lower()] = kv[1]
	return out


func _arg(key: String, fallback: String) -> String:
	var prefix := "--%s=" % key
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback


func _build_env() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.shadow_enabled = false  # match native bench methodology (shadows off)
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


func _load_scene() -> void:
	var packed: PackedScene = load(SCENES[scene_name])
	if packed == null:
		push_error("web_bench: cannot load scene %s" % SCENES[scene_name])
		return
	var inst := packed.instantiate()
	inst.name = "Model"
	add_child(inst)


func _apply_vantage() -> void:
	var spec: String = VANTAGES[scene_name][vantage_name]
	var parts := spec.split(":")
	var cam := Camera3D.new()
	cam.far = CAM_FAR_M
	add_child(cam)
	cam.position = _vec3(parts[0])
	var dir := _vec3(parts[1]) - cam.position
	var up := Vector3.UP
	if absf(dir.normalized().dot(Vector3.UP)) > UP_PARALLEL_DOT:
		up = Vector3.FORWARD
	cam.basis = Basis.looking_at(dir, up)
	cam.make_current()


func _vec3(csv: String) -> Vector3:
	var n := csv.split(",")
	return Vector3(float(n[0]), float(n[1]), float(n[2]))


## Wire the SAME binding runtime the house viewer uses, so the measure window runs with live
## binding active. Only the duplex carries a matching binding map; the city resolves 0 (its
## synthetic node names are not the duplex GlobalIds) — recorded honestly per-run.
func _wire_binding() -> void:
	_binder = BindingMapScript.new()
	_binder.name = "BindingMap"
	add_child(_binder)
	_binder.load_map("res://binding_map.json")
	_binder.build_index(get_node("Model"))


func _build_hud() -> void:
	# The BENCH json is also painted on-screen and WRAPPED to the viewport width, so a browser
	# with no console access (Safari) is read from a screenshot instead of scraped.
	_hud = Label.new()
	_hud.position = Vector2(8, 8)
	_hud.size = Vector2(1264, 704)
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_theme_color_override("font_color", Color(1, 1, 0.6))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 8)
	_hud.add_theme_font_size_override("font_size", 22)
	add_child(_hud)


func _tick_hud() -> void:
	if _first_frame_seen:
		return
	_hud.text = "%s / %s / %s\nwarming up… %.0f fps  bindings %d/%d" % [
		build_label, scene_name, vantage_name,
		Engine.get_frames_per_second(),
		_binder.resolved_count, _binder.total_count,
	]


func _process(_delta: float) -> void:
	if not _first_frame_seen:
		_first_frame_seen = true
		_load_ms = _js_now()


func _run() -> void:
	await _wait_s(warmup_s)
	var row := await _measure_window()
	_emit(row)


func _wait_s(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < s * MSEC_PER_SEC:
		await get_tree().process_frame


func _measure_window() -> Dictionary:
	var frames := 0
	var dc := 0.0
	var prim := 0.0
	var obj := 0.0
	var gpu := 0.0
	var cpu := 0.0
	var vp_rid := get_viewport().get_viewport_rid()
	var drawn0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_usec()
	while true:
		await get_tree().process_frame
		frames += 1
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		if Time.get_ticks_usec() - t0 >= measure_s * USEC_PER_SEC:
			break
	var el := (Time.get_ticks_usec() - t0) / USEC_PER_SEC
	var f := float(frames)
	var drawn := float(Engine.get_frames_drawn() - drawn0)
	var bus: Dictionary = _data_bus.stats()
	return {
		"build": build_label,
		"scene": scene_name,
		"vantage": vantage_name,
		"fps": snappedf(drawn / el, SNAP_FPS),
		"process_fps": snappedf(f / el, SNAP_FPS),
		"frame_ms": snappedf(el * MSEC_PER_SEC / maxf(drawn, MIN_DRAWN), SNAP_MS),
		"gpu_ms": snappedf(gpu / maxf(drawn, MIN_DRAWN), SNAP_MS),
		"cpu_ms": snappedf(cpu / maxf(drawn, MIN_DRAWN), SNAP_MS),
		"draw_calls": int(dc / f),
		"primitives": int(prim / f),
		"objects_rendered": int(obj / f),
		"bindings_resolved": _binder.resolved_count,
		"bindings_total": _binder.total_count,
		"bus_frames_received": bus.get("frames_received", 0),
		"bus_frames_expected": bus.get("frames_expected", 0),
		"bus_drops": bus.get("drops", 0),
		"bus_latency_avg_ms": bus.get("latency_avg_ms", 0.0),
		"bus_up": _data_bus.is_up(),
		"load_to_first_frame_ms": snappedf(_load_ms, 0.1),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"webgl_renderer": _webgl_renderer(),
		"cross_origin_isolated": _coi(),
		"processor_count": OS.get_processor_count(),
		"godot_static_mem_mb": snappedf(float(OS.get_static_memory_usage()) / 1048576.0, 0.1),
		"warmup_s": warmup_s,
		"measure_s": measure_s,
	}


func _emit(row: Dictionary) -> void:
	var js_row := JSON.stringify(row)
	_hud.text = "BENCH: " + js_row
	print("BENCH: ", js_row)
	if OS.has_feature("web"):
		# JSON.stringify(js_row) yields a quoted JS string literal; log it prefixed.
		JavaScriptBridge.eval("console.log('BENCH: ' + %s)" % JSON.stringify(js_row), true)


func _js_now() -> float:
	if not OS.has_feature("web"):
		return float(Time.get_ticks_msec())
	var v: Variant = JavaScriptBridge.eval("performance.now()", true)
	return float(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else 0.0


func _webgl_renderer() -> String:
	if not OS.has_feature("web"):
		return RenderingServer.get_video_adapter_name()
	var expr := (
		"(function(){try{var c=document.createElement('canvas');"
		+ "var g=c.getContext('webgl2')||c.getContext('webgl');"
		+ "var e=g.getExtension('WEBGL_debug_renderer_info');"
		+ "return String(g.getParameter(e?e.UNMASKED_RENDERER_WEBGL:g.RENDERER));"
		+ "}catch(err){return 'unknown';}})()"
	)
	var v: Variant = JavaScriptBridge.eval(expr, true)
	return str(v) if typeof(v) == TYPE_STRING else "unknown"


func _coi() -> bool:
	if not OS.has_feature("web"):
		return false
	var v: Variant = JavaScriptBridge.eval("self.crossOriginIsolated === true", true)
	return v == true
