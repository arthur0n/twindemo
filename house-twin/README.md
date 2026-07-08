# house-twin — smart-home digital-twin viewer (demo)

A live, scrubbable digital twin of the standard **Duplex_A** BIM model. Real IFC geometry,
real streaming telemetry, deterministic playback. This is the end-to-end test-drive project for
the xenodot-forge twin viewer — point the framework web UI at it, or run the viewer directly.

Godot 4.6.3 · Node 22. Set `GODOT=/Applications/Godot.app/Contents/MacOS/Godot`.

## Test-drive in 30 seconds

Two terminals from the project root:

```
# 1. start the seeded data source (WebSocket on ws://localhost:8765)
node tools/sim/server.js --map binding_map.json

# 2. launch the viewer (connects LIVE by default — green HUD)
$GODOT --path .
```

The duplex loads, the HUD reads `LIVE`, and 8 bindings paint themselves from the stream. Stop
the sim and the HUD goes `OFFLINE` red; restart it and it reconnects on its own.

## What you are looking at (the binding story)

Eight home telemetry tags bound to REAL elements of the Duplex model by their IFC GlobalId. Six
paint an element's colour (`albedo_ramp`); two float a status label above a door (`label`). The
full mapping — tag, GlobalId, range, ramp — lives in `binding_map.json`, documented per row.

- `living_room.temp`, `kitchen.temp`, `bedroom_1.temp`, `bedroom_2.temp` — each zone's
  temperature (18-30 C) painted on its exterior brick wall, cold blue to warm red. Together they
  read as a whole-house heat map.
- `boiler.temp` — 40-80 C on the foundation wall by the utility area (hotter range, same ramp).
- `solar.output_w` — rooftop PV output (0-5000 W) on the flat roof slab, dark slate to bright amber.
- `entrance_door.open`, `patio_door.open` — open state (0-1) as a floating label above each door,
  green when closed, red when open.

The sim derives its tag list and each tag's range straight from `binding_map.json`, so the data
and the geometry can never drift apart.

## Replay a recording (history scrub)

A 120-second fixture is bundled at `recordings/house-day.ndjson` (seed 42, 10 Hz, 9600 frames —
byte-reproducible). Load it by passing it on the command line:

```
$GODOT --path . -- --recording=recordings/house-day.ndjson
```

The HUD turns amber `PLAYBACK`, a timeline bar appears at the bottom, and the recording plays
through the SAME binding runtime live data uses — bindings and labels can't tell the difference.
No sim needed for playback. (You can also uncomment `recording=` under `[twin]` in `viewer.cfg`,
but the default boot is LIVE on purpose so you see the live path first.)

## Controls

- `Tab` — toggle camera between ORBIT (left-drag rotate, wheel zoom) and FLY (mouse look, WASD to
  move, Q/E down/up, Shift faster, Esc back to orbit). Fly inside to see interior detail.
- `Space` — play/pause (only while the timeline bar is visible, i.e. in playback).
- Timeline bar — drag the slider to scrub; the speed button cycles 0.25x / 0.5x / 1x / 2x / 4x.

## Verify it works

```
GODOT=/Applications/Godot.app/Contents/MacOS/Godot TWIN_BENCH=1 tools/verify_twin.sh
```

Gates the whole pipeline: GlobalId join coverage (100%), the live binding smoke (seeded sim ->
DataBus -> painted geometry), playback determinism (same fixture + seeks -> identical hash), and
the frame budget (`frame_budget_ms=16.7` in `viewer.cfg`; measured ~6 ms / 170 fps windowed).
Drop `TWIN_BENCH=1` in a headless/CI context — the frame-budget leg then SKIPs loudly (it needs a
real window).

## Regenerating the model

The GLB + sidecar under `models/` are runtime-loaded and NOT committed (see `.gitignore`). To
rebuild them from the source IFC (needs a Python 3.12 venv with `ifcopenshell==0.8.5`):

```
python tools/ifc_convert.py path/to/Duplex_A_20110907.ifc --glb models/duplex.glb --sidecar models/duplex_props.json
```

Node names carry the IFC GlobalIds — that is the join key everything else binds through.

## Driving it from the framework web UI

The web UI streams a real source into the viewer through the framework's `/twin-data` relay
(configured by `.xenodot.json` `twin.sourceUrl`). For this demo the "real source" is the seeded
sim above: start `node tools/sim/server.js --map binding_map.json` first, then the relay fans its
frames out to the browser/viewer clients. The viewer's default `url` (`ws://localhost:8765` in
`viewer.cfg`) already points at the sim, so a direct `$GODOT --path .` run needs nothing else.
