# core/sidecar_reader.gd — load a model's _props.json sidecar, look up a GlobalId,
# and project psets to an ordered field list via design/panel-fields.json.
#
# Usage (compose under any Node; NOT an autoload):
#   var reader := SidecarReader.new()
#   reader.load_files("res://models/duplex_props.json", "res://design/panel-fields.json")
#   var rows := reader.fields_for("2OrWItJ6zAwBNp0OUxK_l8")
#   # rows: Array[Dictionary] — [{"label": String, "value": String}, ...]
#
# Missing sidecar/field-map → push_warning, 0 rows returned, never crashes.
# Unknown globalid → push_warning, 0 rows.
# Unknown source path in the field map → value "—" (faithful per design doc).
class_name SidecarReader
extends RefCounted

const GlobalIdHelperScript := preload("res://core/globalid.gd")
const _GLOBALID_LEN := GlobalIdHelperScript.GLOBALID_LEN
const _GLOBALID_CHARS := GlobalIdHelperScript.GLOBALID_CHARS

const _MISSING := "—"

# Loaded state (empty until load_files succeeds).
var _sidecar: Dictionary = {}
var _fields: Array = []  # Array of {label:String, source:String} Dicts from the map
var _loaded: bool = false


## Load the sidecar and field-map files. Returns true if both loaded cleanly.
## Call once after the model is placed; GlobalId lookups work immediately after.
func load_files(sidecar_path: String, field_map_path: String) -> bool:
	_sidecar = {}
	_fields = []
	_loaded = false
	var ok_s := _load_sidecar(sidecar_path)
	var ok_f := _load_field_map(field_map_path)
	_loaded = ok_s and ok_f
	return _loaded


## True when both files were loaded without error.
func is_loaded() -> bool:
	return _loaded


## Return ordered field rows for `globalid`:
## Array[Dictionary] — each entry {label: String, value: String}.
## Rows follow the field-map order. An absent pset/key yields value "—".
## An unknown globalid yields [] with a push_warning.
func fields_for(globalid: String) -> Array[Dictionary]:
	if not _loaded:
		return []
	if not _sidecar.has(globalid):
		push_warning("sidecar_reader: GlobalId '%s' not in sidecar" % globalid)
		return []
	var record: Dictionary = _sidecar[globalid]
	var out: Array[Dictionary] = []
	for field_entry: Variant in _fields:
		if typeof(field_entry) != TYPE_DICTIONARY:
			continue
		var field_dict: Dictionary = field_entry
		var label: String = str(field_dict.get("label", ""))
		var source: String = str(field_dict.get("source", ""))
		var value := _resolve_source(record, source)
		out.append({"label": label, "value": value})
	return out


## Validate `globalid` looks like an IFC GlobalId (22-char base64 IFC alphabet).
## Used by callers to filter hit-node names before querying.
func is_valid_globalid(candidate: String) -> bool:
	if candidate.length() != _GLOBALID_LEN:
		return false
	for i in _GLOBALID_LEN:
		if _GLOBALID_CHARS.find(candidate[i]) == -1:
			return false
	return true


# --- private ---


func _load_sidecar(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("sidecar_reader: sidecar not found at '%s'" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("sidecar_reader: '%s' is not a JSON object" % path)
		return false
	_sidecar = parsed
	return true


func _load_field_map(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("sidecar_reader: field map not found at '%s'" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("sidecar_reader: field map '%s' is not a JSON object" % path)
		return false
	var root_obj: Dictionary = parsed
	var raw_fields: Variant = root_obj.get("fields")
	if typeof(raw_fields) != TYPE_ARRAY:
		push_warning("sidecar_reader: field map '%s' has no 'fields' array" % path)
		return false
	var fields_arr: Array = raw_fields
	for entry: Variant in fields_arr:
		if typeof(entry) != TYPE_DICTIONARY:
			push_warning("sidecar_reader: field map entry is not an object — skipped")
			continue
		var d: Dictionary = entry
		if typeof(d.get("label")) != TYPE_STRING or typeof(d.get("source")) != TYPE_STRING:
			push_warning("sidecar_reader: field map entry missing label/source — skipped")
			continue
		_fields.append(d)
	return true


# Resolve a source path from a sidecar record.
# source is either a top-level key ("name", "ifc_class") or a dotted pset path
# ("Pset_BeamCommon.Reference"). Returns the string value, or _MISSING when absent.
func _resolve_source(record: Dictionary, source: String) -> String:
	if source.is_empty():
		return _MISSING
	if source.contains("."):
		return _resolve_pset_path(record, source)
	# Top-level key
	var val: Variant = record.get(source)
	if val == null:
		return _MISSING
	return _value_to_string(val)


func _resolve_pset_path(record: Dictionary, source: String) -> String:
	var parts := source.split(".", false, 1)
	if parts.size() != 2:
		return _MISSING
	var pset_name: String = parts[0]
	var key_name: String = parts[1]
	var psets_var: Variant = record.get("psets")
	if typeof(psets_var) != TYPE_DICTIONARY:
		return _MISSING
	var psets: Dictionary = psets_var
	var pset_var: Variant = psets.get(pset_name)
	if typeof(pset_var) != TYPE_DICTIONARY:
		return _MISSING
	var pset: Dictionary = pset_var
	var val: Variant = pset.get(key_name)
	if val == null:
		return _MISSING
	return _value_to_string(val)


func _value_to_string(val: Variant) -> String:
	var t := typeof(val)
	if t == TYPE_STRING:
		# SEAM: Variant confirmed TYPE_STRING by typeof() guard above.
		@warning_ignore("unsafe_cast")
		var s: String = val
		return s
	if t == TYPE_FLOAT:
		# SEAM: Variant confirmed TYPE_FLOAT by typeof() guard above.
		@warning_ignore("unsafe_cast")
		var f: float = val
		# 4 significant figures — readable without excessive precision.
		return "%.4g" % f
	if t == TYPE_INT:
		# SEAM: Variant confirmed TYPE_INT by typeof() guard above.
		@warning_ignore("unsafe_cast")
		var i: int = val
		return str(i)
	if t == TYPE_BOOL:
		# SEAM: Variant confirmed TYPE_BOOL by typeof() guard above.
		@warning_ignore("unsafe_cast")
		var b: bool = val
		return "true" if b else "false"
	return str(val)
