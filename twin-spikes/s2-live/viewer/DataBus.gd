# DataBus.gd — autoload singleton. Live tag stream over WebSocketPeer.
#
# Gotchas handled:
#  - WebSocketPeer.poll() MUST be called every frame or nothing happens.
#  - connect_to_url() is async: returns OK immediately, state goes
#    STATE_CONNECTING -> STATE_OPEN (or CLOSED on failure). Check get_ready_state().
#  - Drain ALL pending packets each frame (get_available_packet_count loop),
#    otherwise a 10 Hz stream backs up behind a 60 fps consumer under hiccups.
#  - Reconnect: a CLOSED peer cannot be reused reliably -> allocate a fresh
#    WebSocketPeer for every connection attempt.
extends Node

signal tag_update(tag: String, value: float, seq: int, latency_ms: float)
signal connection_changed(up: bool)

const URL := "ws://localhost:8765"
const RECONNECT_DELAY := 1.0

var _ws: WebSocketPeer
var _was_open := false
var _reconnect_cooldown := 0.0

# --- stats (read by Main.gd for the report) ---
var frames_received := 0
var drops := 0
var lat_min := INF
var lat_max := 0.0
var lat_sum := 0.0
var reconnects := 0
var _first_seq := {}  # tag -> first seq seen
var _last_seq := {}   # tag -> last seq seen

func _ready() -> void:
	_open_socket()

func _open_socket() -> void:
	_ws = WebSocketPeer.new()  # fresh peer per attempt (see gotcha above)
	var err := _ws.connect_to_url(URL)
	if err != OK:
		push_warning("DataBus: connect_to_url failed (%d), retrying" % err)
		_reconnect_cooldown = RECONNECT_DELAY

func _process(delta: float) -> void:
	if _reconnect_cooldown > 0.0:
		_reconnect_cooldown -= delta
		if _reconnect_cooldown <= 0.0:
			_open_socket()
		return

	_ws.poll()  # mandatory every frame
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				connection_changed.emit(true)
			while _ws.get_available_packet_count() > 0:
				_handle_packet(_ws.get_packet())
		WebSocketPeer.STATE_CLOSED:
			if _was_open:
				_was_open = false
				reconnects += 1
				connection_changed.emit(false)
			_reconnect_cooldown = RECONNECT_DELAY
		_:
			pass  # CONNECTING / CLOSING: just keep polling

func _handle_packet(pkt: PackedByteArray) -> void:
	var data = JSON.parse_string(pkt.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or not data.has("tag"):
		return
	var tag: String = data["tag"]
	var value: float = data["value"]
	var seq: int = int(data["seq"])
	var recv_ms := Time.get_unix_time_from_system() * 1000.0
	var latency := recv_ms - float(data["sent_ms"])  # same machine, same clock

	frames_received += 1
	lat_min = min(lat_min, latency)
	lat_max = max(lat_max, latency)
	lat_sum += latency

	if not _first_seq.has(tag):
		_first_seq[tag] = seq
	elif _last_seq.has(tag) and seq > _last_seq[tag] + 1:
		drops += seq - _last_seq[tag] - 1
	_last_seq[tag] = seq

	tag_update.emit(tag, value, seq, latency)

func frames_expected() -> int:
	var total := 0
	for tag in _first_seq:
		total += int(_last_seq[tag]) - int(_first_seq[tag]) + 1
	return total

func stats() -> Dictionary:
	return {
		"frames_received": frames_received,
		"frames_expected": frames_expected(),
		"drops": drops,
		"reconnects": reconnects,
		"latency_min_ms": (0.0 if frames_received == 0 else snappedf(lat_min, 0.01)),
		"latency_avg_ms": (0.0 if frames_received == 0 else snappedf(lat_sum / frames_received, 0.01)),
		"latency_max_ms": snappedf(lat_max, 0.01),
	}
