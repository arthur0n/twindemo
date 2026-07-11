# overlay/inspect_panel.gd — property inspector panel.
# On element_picked(globalid) calls the SidecarReader and renders the returned
# {label, value} rows in order. Dismiss on empty-space left-click or Esc (Esc only
# when the camera is in ORBIT mode — FLY Esc is the camera-rig's to consume first).
#
# Add as a child of Main (a sibling of Overlay). Wire picker + camera_rig from main.gd.
class_name InspectPanel
extends CanvasLayer

## Emitted after the panel is shown for a new element (useful for testing).
signal panel_opened(globalid: String)
## Emitted when the panel is dismissed.
signal panel_closed

const SidecarReaderScript := preload("res://core/sidecar_reader.gd")
const CameraRigScript := preload("res://core/camera_rig.gd")

# Row layout config — font sizes and colours.
const _HEADER_FONT_SIZE := 15
const _ROW_FONT_SIZE := 13
const _LABEL_COLOR := Color(0.65, 0.68, 0.72)
const _VALUE_COLOR := Color(0.92, 0.94, 0.97)

## Background colour of the panel card.
@export var bg_color: Color = Color(0.08, 0.09, 0.12, 0.92)
## Accent colour used for the GlobalId sub-label.
@export var accent_color: Color = Color(0.55, 0.75, 0.95)

# References set externally by main.gd after _ready.
var _picker: ElementPicker = null
var _camera_rig: CameraRigScript = null
var _reader: SidecarReaderScript = null
var _visible_panel: bool = false

@onready var _panel: Panel = $Panel
@onready var _rows_container: VBoxContainer = $Panel/VLayout/Scroll/Rows
@onready var _title_label: Label = $Panel/VLayout/Header/TitleLabel
@onready var _gid_label: Label = $Panel/VLayout/Header/GidLabel


func _ready() -> void:
	_panel.visible = false
	_apply_panel_style()


## Called by main.gd after both the picker and camera_rig are known.
func wire(picker: ElementPicker, camera_rig: CameraRigScript, reader: SidecarReaderScript) -> void:
	_picker = picker
	_camera_rig = camera_rig
	_reader = reader
	_picker.element_picked.connect(_on_element_picked)


## Returns true when the panel is currently visible.
func is_open() -> bool:
	return _visible_panel


func _unhandled_input(event: InputEvent) -> void:
	if not _visible_panel:
		return

	# Esc: dismiss only when camera is in ORBIT (FLY captures Esc before us).
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.physical_keycode == KEY_ESCAPE:
			if _camera_rig == null or _camera_rig.mode == CameraRigScript.Mode.ORBIT:
				_hide_panel()
				get_viewport().set_input_as_handled()
		return

	# Left-click on empty space (not on the panel itself) → dismiss.
	var btn := event as InputEventMouseButton
	if btn != null and btn.pressed and btn.button_index == MOUSE_BUTTON_LEFT:
		if not _panel.get_global_rect().has_point(btn.position):
			_hide_panel()
			get_viewport().set_input_as_handled()


func _on_element_picked(globalid: String) -> void:
	if _reader == null or not _reader.is_loaded():
		return
	var rows := _reader.fields_for(globalid)
	_populate(globalid, rows)
	_panel.visible = true
	_visible_panel = true
	emit_signal("panel_opened", globalid)


func _hide_panel() -> void:
	_panel.visible = false
	_visible_panel = false
	emit_signal("panel_closed")


func _populate(globalid: String, rows: Array[Dictionary]) -> void:
	_title_label.text = "Element"
	_gid_label.text = globalid

	# Clear previous rows.
	for child: Node in _rows_container.get_children():
		child.queue_free()

	if rows.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(no fields)"
		empty_label.add_theme_color_override("font_color", _LABEL_COLOR)
		_rows_container.add_child(empty_label)
		return

	for row: Dictionary in rows:
		var label_str: String = str(row.get("label", ""))
		var value_str: String = str(row.get("value", "—"))
		_rows_container.add_child(_make_row(label_str, value_str))


func _make_row(label_text: String, value_text: String) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", _LABEL_COLOR)
	lbl.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size = Vector2(100.0, 0.0)

	var val := Label.new()
	val.text = value_text
	val.add_theme_color_override("font_color", _VALUE_COLOR)
	val.add_theme_font_size_override("font_size", _ROW_FONT_SIZE)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	hbox.add_child(lbl)
	hbox.add_child(val)
	return hbox


func _apply_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", style)
	_title_label.add_theme_font_size_override("font_size", _HEADER_FONT_SIZE)
	_gid_label.add_theme_color_override("font_color", accent_color)
	_gid_label.add_theme_font_size_override("font_size", 10)
