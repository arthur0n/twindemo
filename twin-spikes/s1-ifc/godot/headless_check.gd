extends SceneTree
# SPIKE S1 headless check: load GLB at runtime, count meshes, join GlobalIds
# against the property sidecar JSON. Run:
#   Godot --headless --path godot -s headless_check.gd

const GLB := "res://../duplex.glb"
const SIDECAR := "res://../duplex_props.json"


func _init() -> void:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(ProjectSettings.globalize_path(GLB), state)
	if err != OK:
		push_error("GLB load failed: %s" % err)
		quit(1)
		return
	var scene := gltf.generate_scene(state)
	get_root().add_child(scene)

	var meshes: Array[Node] = []
	_collect(scene, "MeshInstance3D", meshes)
	print("MESH_COUNT=%d" % meshes.size())

	var side: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(ProjectSettings.globalize_path(SIDECAR))
	)
	print("SIDECAR_KEYS=%d" % side.size())

	# Join success rate over ALL mesh nodes (parent node of a mesh may carry
	# the guid when the glTF node had children; check node then parent).
	var joined := 0
	var misses: Array[String] = []
	var joined_walls: Array = []
	for m in meshes:
		var guid := _guid_for(m, side)
		if guid != "":
			joined += 1
			if side[guid]["ifc_class"] == "IfcWallStandardCase" or side[guid]["ifc_class"] == "IfcWall":
				joined_walls.append([m.name, guid])
		else:
			misses.append(str(m.name))
	print("JOIN=%d/%d" % [joined, meshes.size()])
	if misses.size() > 0:
		print("MISS_SAMPLE=", misses.slice(0, 5))

	# THE JOIN demo: 3 sampled nodes (prefer walls for IsExternal pset).
	var picks: Array = joined_walls.slice(0, 2)
	for m in meshes:
		var g := _guid_for(m, side)
		if g != "" and side[g]["ifc_class"] == "IfcDoor":
			picks.append([m.name, g])
			break
	for p in picks:
		var rec: Dictionary = side[p[1]]
		print("--- node '%s' -> GlobalId %s" % [p[0], p[1]])
		print("    ifc_class=%s name=%s" % [rec["ifc_class"], rec["name"]])
		var psets: Dictionary = rec["psets"]
		for pset_name in psets:
			print("    pset %s: %s" % [pset_name, JSON.stringify(psets[pset_name])])
	quit(0)


func _guid_for(n: Node, side: Dictionary) -> String:
	# Node names may be Godot-sanitized (e.g. trailing dedup suffixes) or the
	# guid may sit on the parent grouping node.
	var cands := [str(n.name), str(n.get_parent().name) if n.get_parent() else ""]
	for c in cands:
		if side.has(c):
			return c
		# Godot uniquifies duplicate sibling names as "name2" etc; guid is 22 chars.
		if c.length() > 22 and side.has(c.substr(0, 22)):
			return c.substr(0, 22)
	return ""


func _collect(n: Node, klass: String, out: Array[Node]) -> void:
	if n.is_class(klass):
		out.append(n)
	for c in n.get_children():
		_collect(c, klass, out)
