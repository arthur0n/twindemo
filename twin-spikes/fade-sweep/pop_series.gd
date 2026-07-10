extends SceneTree
## pop_series.gd — dense scripted camera approach down the ucity street axis, capturing one PNG per
## step, for the POP-SERIES proxy (open item #6, rule clause (a)). Renders the WHOLE approach in ONE
## windowed Godot process (load scene once, translate the camera, capture each step) instead of N
## separate launches. A hard-pop config shows an abrupt full-object appearance between consecutive
## frames as objects cross the visibility_range_end cutoff; a working fade spreads that appearance as
## an alpha ramp over the [end, end+margin] band across several frames.
##
## Usage (NO --headless — the Dummy renderer saves blank images):
##   $GODOT --path . --resolution 1280x720 -s scripts/pop_series.gd -- <scene.scn> \
##       --out-dir <abs dir> --x 139.5 --y 1.7 --start-z 126 --end-z 30 --step 3 \
##       --look-ahead 60 [--settle 6]
## Camera at (x, y, z) looks at (x, y, z - look_ahead) so the view direction is a constant straight
## look down -z (pure forward translation) — the only thing that changes frame to frame is objects
## crossing the cull shell. Frames saved as <out-dir>/f_<NNN>_z<zzz>.png. Output per frame:
## `POP: f<NNN> z=<z> -> <png>`; final `POP: DONE <count> frames`.

const CAM_FAR_M := 12000.0
const UP_PARALLEL_DOT := 0.999
const DEFAULT_SETTLE := 6

var scene_path := ""
var out_dir := ""
var cx := 139.5
var cy := 1.7
var start_z := 126.0
var end_z := 30.0
var step := 3.0
var look_ahead := 60.0
var settle := DEFAULT_SETTLE

var _cam: Camera3D
var _positions: Array[float] = []
var _idx := 0
var _wait := 0
var _count := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("POP: FAIL — headless renderer saves blank images; run with a display")
		quit(1)
		return
	_parse_args()
	if scene_path == "" or out_dir == "":
		print("POP: FAIL — <scene> --out-dir <dir> required")
		quit(1)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		print("POP: FAIL — cannot load %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	_cam = Camera3D.new()
	_cam.far = CAM_FAR_M
	root.add_child(_cam)
	_cam.make_current()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var z := start_z
	while z >= end_z - 0.001:
		_positions.append(z)
		z -= step
	_place(_positions[0])


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		match a:
			"--out-dir": i += 1; out_dir = args[i]
			"--x": i += 1; cx = float(args[i])
			"--y": i += 1; cy = float(args[i])
			"--start-z": i += 1; start_z = float(args[i])
			"--end-z": i += 1; end_z = float(args[i])
			"--step": i += 1; step = float(args[i])
			"--look-ahead": i += 1; look_ahead = float(args[i])
			"--settle": i += 1; settle = int(args[i])
			_:
				if scene_path == "":
					scene_path = a if a.begins_with("res://") else "res://" + a
		i += 1


func _place(z: float) -> void:
	_cam.position = Vector3(cx, cy, z)
	var dir := Vector3(cx, cy, z - look_ahead) - _cam.position
	var up := Vector3.UP
	if absf(dir.normalized().dot(Vector3.UP)) > UP_PARALLEL_DOT:
		up = Vector3.FORWARD
	_cam.basis = Basis.looking_at(dir, up)


func _process(_delta: float) -> bool:
	_wait += 1
	if _wait < settle:
		return false
	_wait = 0
	_capture(_positions[_idx])
	_idx += 1
	if _idx >= _positions.size():
		print("POP: DONE %d frames" % _count)
		return true
	_place(_positions[_idx])
	return false


func _capture(z: float) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("POP: FAIL — viewport image null at z=%.0f" % z)
		return
	var png := "%s/f_%03d_z%03d.png" % [out_dir, _idx, roundi(z)]
	img.save_png(png)
	_count += 1
	print("POP: f%03d z=%.0f -> %s" % [_idx, z, png])
