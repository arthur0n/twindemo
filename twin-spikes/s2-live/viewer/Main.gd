# Main.gd — spawns one colored box + Label3D per tag, subscribes to DataBus,
# ramps color green->red by normalized value, logs latency per frame,
# screenshots mid-run, writes a stats report and quits after RUN_SECONDS.
extends Node3D

const RUN_SECONDS := 30.0
const SCREENSHOT_AT := 15.0
const OUT_DIR := "/Users/arthurnunes/Library/MRHEWBUC-LOCAL/mercenary/twin-spikes/s2-live/artifacts"

# tag -> [min, max] for the color ramp (matches sim ranges)
const TAG_RANGES := {
	"pump_1.temp": [40.0, 90.0],
	"pump_2.temp": [40.0, 90.0],
	"valve_3.pressure": [1.0, 8.0],
	"tank_1.level": [0.0, 100.0],
	"motor_2.rpm": [900.0, 1800.0],
}

var _boxes := {}   # tag -> {mat: StandardMaterial3D, label: Label3D}
var _hud: Label
var _elapsed := 0.0
var _shot_taken := false

func _ready() -> void:
	# camera + light
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.5, 10)
	cam.look_at_from_position(cam.position, Vector3.ZERO)
	add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)

	# one box + Label3D per tag
	var tags := TAG_RANGES.keys()
	tags.sort()
	for i in tags.size():
		var tag: String = tags[i]
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.position = Vector3((i - (tags.size() - 1) / 2.0) * 2.6, 0, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.3, 0.3)
		mesh.material_override = mat
		add_child(mesh)

		var label := Label3D.new()
		label.text = tag + "\n--"
		label.position = mesh.position + Vector3(0, 1.5, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 56
		label.outline_size = 14
		add_child(label)
		_boxes[tag] = {"mat": mat, "label": label}

	# 2D HUD: connection + running stats
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	_hud.text = "connecting..."
	canvas.add_child(_hud)

	DataBus.tag_update.connect(_on_tag_update)
	DataBus.connection_changed.connect(func(up: bool):
		print("[viewer] connection %s" % ("UP" if up else "DOWN")))

func _on_tag_update(tag: String, value: float, seq: int, latency_ms: float) -> void:
	print("[viewer] %s v=%.2f seq=%d latency=%.2fms" % [tag, value, seq, latency_ms])
	if not _boxes.has(tag):
		return
	var box: Dictionary = _boxes[tag]
	var r: Array = TAG_RANGES[tag]
	var t: float = clampf((value - r[0]) / (r[1] - r[0]), 0.0, 1.0)
	box["mat"].albedo_color = Color(t, 1.0 - t, 0.1)  # green -> red ramp
	box["label"].text = "%s\n%.2f  (%.0f ms)" % [tag, value, latency_ms]

func _process(delta: float) -> void:
	_elapsed += delta
	var s: Dictionary = DataBus.stats()
	_hud.text = "t=%.1fs  recv=%d  drops=%d  lat avg=%.1fms max=%.1fms" % [
		_elapsed, s["frames_received"], s["drops"], s["latency_avg_ms"], s["latency_max_ms"]]

	if not _shot_taken and _elapsed >= SCREENSHOT_AT:
		_shot_taken = true
		_take_screenshot()

	if _elapsed >= RUN_SECONDS:
		set_process(false)
		_finish()

func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + "/screenshot.png"
	var err := img.save_png(path)
	print("[viewer] screenshot %s -> %s" % [("saved" if err == OK else "FAILED err=%d" % err), path])

func _finish() -> void:
	var s: Dictionary = DataBus.stats()
	s["run_seconds"] = snappedf(_elapsed, 0.1)
	var json := JSON.stringify(s, "  ")
	var f := FileAccess.open(OUT_DIR + "/report.json", FileAccess.WRITE)
	if f:
		f.store_string(json)
		f.close()
	print("S2_REPORT " + JSON.stringify(s))
	get_tree().quit()
