# core/globalid.gd — IFC GlobalId join helpers: shared by binding_map.gd and the picker.
# The ONE join rule for this viewer (design: pick-inspect-core.md "Reuse check").
# All functions are static — instantiate-free; call as GlobalIdHelper.func_name().
class_name GlobalIdHelper
extends RefCounted

## IFC GlobalId length in characters (buildingSMART base64 alphabet).
## Godot's name-dedup can suffix a node name, so the join key is the 22-char prefix.
const GLOBALID_LEN := 22

## The IFC base64 alphabet used in buildingSMART GlobalIds.
## Chars outside this set disqualify a candidate.
const GLOBALID_CHARS := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$"


## Extract the GlobalId carried by `node_name`, or "" if it isn't one.
## Godot dedup can suffix ("SomeGuid@2"), so we take the 22-char prefix and
## confirm every character is in the IFC base64 alphabet — this keeps
## WorldEnvironment / CameraRig / etc. out of the index.
static func globalid_from_name(node_name: String) -> String:
	if node_name.length() < GLOBALID_LEN:
		return ""
	var prefix := node_name.substr(0, GLOBALID_LEN)
	for i: int in GLOBALID_LEN:
		if GLOBALID_CHARS.find(prefix[i]) == -1:
			return ""
	return prefix


## Resolve the GlobalId for `node`, checking the node's own name first, then its
## parent's name (the sidecar join rule from twin-import: a mesh may be a child of
## the named grouping node).
## Returns "" when neither the node nor its parent carries a valid GlobalId.
static func globalid_for_node(node: Node3D) -> String:
	var gid := globalid_from_name(node.name)
	if gid != "":
		return gid
	var parent := node.get_parent()
	if parent != null:
		gid = globalid_from_name(parent.name)
	return gid
