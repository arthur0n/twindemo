extends SceneTree
## scripts/shot_city.gd — capture a PNG of a bare 3D scene from an injected vantage camera
## (Phase 5 W2 before/after showcase). The shipped tools/capture_screenshot.gd targets the viewer's
## SubViewport pixelation rig (main.tscn); the city_*.scn benchmark scenes are plain Node3D trees
## with their own light+environment, so this loads the scene, injects a Camera3D at the same
## X,Y,Z:LX,LY,LZ vantage grammar bench_scene.gd uses, lets the frame settle, and saves the window
## viewport as a PNG.
##
## Usage (NO --headless — the Dummy renderer saves a blank image):
##   $GODOT --path . --resolution 1280x720 -s scripts/shot_city.gd -- \
##       <scene.scn> --vantage X,Y,Z:LX,LY,LZ --out <abs path.png> [--settle 30]
##
## Output: `SHOT: OK <scene> -> <png>` (exit 0) or `SHOT: FAIL — <reason>` (exit 1).

## Frames to render before capture so shader compile / streaming / first-frame spikes settle. 30 is
## generous for these static scenes and matches the "warm up" discipline of the bench harness.
const DEFAULT_SETTLE_FRAMES := 30

## Far plane (metres) of the injected camera — building-scale twins span hundreds of metres; 12 km
## clears any overview shot. Mirrors bench_scene.gd CAM_FAR_M so shots and benches match.
const CAM_FAR_M := 12000.0

## |dir . UP| above this counts as looking straight up/down, where Basis.looking_at degenerates;
## swap in a non-parallel up first. 0.999 ~= within ~2.6 deg of vertical (same guard as bench).
const UP_PARALLEL_DOT := 0.999

var scene_path := ""
var vantage := ""
var out_path := ""
var settle := DEFAULT_SETTLE_FRAMES
var _frames := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("SHOT: FAIL — headless renderer saves a blank image; run with a display")
		quit(1)
		return
	_parse_args()
	if scene_path == "" or out_path == "" or vantage == "":
		print("SHOT: FAIL — <scene> --vantage X,Y,Z:LX,LY,LZ --out <path.png> all required")
		quit(1)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		print("SHOT: FAIL — cannot load %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())
	_inject_camera()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		match a:
			"--vantage":
				i += 1
				vantage = args[i]
			"--out":
				i += 1
				out_path = args[i]
			"--settle":
				i += 1
				settle = int(args[i])
			_:
				if scene_path == "":
					scene_path = a if a.begins_with("res://") else "res://" + a
		i += 1


func _inject_camera() -> void:
	var parts := vantage.split(":")
	if parts.size() != 2:
		print("SHOT: FAIL — --vantage wants X,Y,Z:LX,LY,LZ, got '%s'" % vantage)
		quit(1)
		return
	var cam := Camera3D.new()
	cam.far = CAM_FAR_M
	root.add_child(cam)
	cam.position = _vec3(parts[0])
	# Basis.looking_at is pure math (Node3D.look_at no-ops during SceneTree init); guard the
	# straight-down case where the direction is parallel to UP.
	var dir := _vec3(parts[1]) - cam.position
	var up := Vector3.UP
	if absf(dir.normalized().dot(Vector3.UP)) > UP_PARALLEL_DOT:
		up = Vector3.FORWARD
	cam.basis = Basis.looking_at(dir, up)
	cam.make_current()


func _vec3(csv: String) -> Vector3:
	var n := csv.split(",")
	return Vector3(float(n[0]), float(n[1]), float(n[2]))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < settle:
		return false
	_capture()
	return true


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT: FAIL — viewport image is null (renderer not ready?)")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var err := img.save_png(out_path)
	if err != OK:
		print("SHOT: FAIL — save_png error %d for %s" % [err, out_path])
		quit(1)
		return
	print("SHOT: OK %s -> %s (%dx%d)" % [scene_path, out_path, img.get_width(), img.get_height()])
	quit(0)
