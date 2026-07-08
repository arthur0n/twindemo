# Xenodot Forge — digital-twin viewer, from scratch

This is the complete walkthrough that took an empty folder to a **live, scrubbable digital twin
of a real BIM model** — colored walls driven by streaming telemetry, deterministic playback, and
a green end-to-end gate. Every command and every output snippet below was actually run on macOS
(Godot 4.6.3, Node 22, Python 3.12); the wrinkles are the ones a stranger really hits, with the
fix that cleared each.

You build two things that sit side by side:

```
twindemo/
├── xenodot-forge/   the framework (a clone of this repo)
└── house/           the viewer project the framework scaffolds for you
```

The framework never contains game/twin content — it points at an external project (`house/`
here), reads it in place, and the project stays pure. That is why there are two repos.

---

## Prerequisites

- **Claude Code** — the framework is driven by Claude Code + the bundled `xenodot` plugin. You can
  do the whole pipeline by hand from a terminal (this tutorial does), or drive it from the web UI
  and let the agent Hive run the steps (see *Driving it from the web UI* at the end).
- **Godot 4.x** — 4.6.3 here. Export the path once so every command can find it:
  ```bash
  export GODOT=/Applications/Godot.app/Contents/MacOS/Godot
  ```
- **Node 18+** — 22 here. The framework is plain JS + JSDoc.
- **`uv` + Python 3.12** — only for the IFC import step. `ifcopenshell` ships **no wheel for
  Python 3.14** (the current macOS system Python), so the converter runs in a pinned 3.12 venv.
  `brew install uv python@3.12` covers it.

---

## Step 1 — clone the framework and prove it's green

The framework currently lives in a local repo. Clone it into `twindemo/xenodot-forge`:

```bash
cd twindemo
git clone /Users/you/path/to/xenodot-forge xenodot-forge
# Once it is pushed to GitHub this becomes:
#   git clone https://github.com/arthur0n/xenodot-forge.git xenodot-forge
cd xenodot-forge
npm install
```

`npm install` pulls ~277 packages (a few seconds on a warm cache, up to a minute cold). Then prove
a stranger's install is green:

```bash
npm run validate   # tsc + eslint (zero warnings) + structure/skills/contamination/library checks
npm test           # 93 unit tests + reducer + skills checks
```

Expected tail of `npm test`:

```
# tests 93
# pass 93
# fail 0
```

**Wrinkle I hit (documented in full below):** `npm run validate` first failed on
`plugin/library/verdicts/index.md: stale`. The error tells you the exact fix —
`npm run check:library -- --write` — after which `validate` exits 0. (It was a one-character
escaping drift in a generated index; a known uncommitted fix in the source.)

---

## Step 2 — scaffold the viewer project

From inside the clone, scaffold a **viewer** (the digital-twin flavor) into a sibling folder:

```bash
npm run new -- ../house --viewer
```

This scaffolds `starter-viewer/`, records the project path + type, materializes the plugin's
per-project files, and health-checks. The output confirms the shape:

```
new: scaffolded starter-viewer → .../twindemo/house
  projectType: viewer
materialize: ... tools copied 22/22, twin tools added 15 (0 collision(s)), library created, library-twin created, x-shared-assets created.
doctor: ... ✓ plugin capabilities (20 agents, 47 skills)  ✓ library-twin/ symlinked
doctor: OK
```

What landed and what stayed put:

- The clone gets its **own** `.xenodot.json` (`projectDir` → `twindemo/house`,
  `projectType: viewer`). If you also have the framework checked out elsewhere, that other
  `.xenodot.json` is untouched — each checkout remembers its own project.
- `house/tools/` (the twin tooling: `ifc_convert.py`, `sim/`, `verify_twin.sh`, …) and
  `house/library`, `house/library-twin`, `house/x-shared-assets` are **symlinked/copied and
  gitignored** — framework-generated, never committed into the project.
- The framework's agents/skills are **not** copied into the project. The web UI loads the
  `xenodot` plugin automatically. For terminal Claude Code, doctor prints the one-time install:
  ```
  /plugin marketplace add /path/to/twindemo/xenodot-forge
  /plugin install xenodot@xenodot-forge
  ```
  (Note: the experimental `xenodot-twin` plugin is web-UI-only for now — terminal sessions run
  without the twin skills.)

---

## Step 3 — engine sanity (boot the empty shell)

Before any content, confirm the scaffold boots clean. The viewer with no model draws a lit
placeholder grid:

```bash
cd ../house
$GODOT --headless --path . --quit-after 120
```

Expected: the Godot banner and **nothing else** — zero errors, zero warnings. If you see script
parse errors here, stop and fix them before importing anything.

A useful side effect: this boot writes `.godot/global_script_class_cache.cfg`, which registers the
`class_name` types the tooling uses (`TwinHints`, `TwinChunks`). Doing it now pre-empts the
class-cache wrinkle (see Troubleshooting).

---

## Step 4 — the IFC import (real geometry, real join key)

The twin's spine is one invariant: **the IFC GlobalId is the join key everywhere** — the GLB's
node names carry it, the property sidecar is keyed by it, and live tags bind through it.

**Get a model.** This tutorial uses the standard **Duplex_A** sample. Put it in a `downloads/`
folder at the workspace root (or straight into `house/`):

```bash
mkdir -p ../downloads
cp /path/to/Duplex_A_20110907.ifc ../downloads/
head -c 13 ../downloads/Duplex_A_20110907.ifc    # must print: ISO-10303-21;
```

That header check matters: the canonical buildingSMART sample URLs are **dead** and serve an HTML
error page that "converts" into garbage. A real IFC (a STEP file) starts with `ISO-10303-21;`. A
working mirror for the Duplex model:
`https://raw.githubusercontent.com/andyward/XBimDemo/master/Xbim.TestApp/Duplex_A_20110907.ifc`.

**Build the Python venv** (pinned to 3.12; `.venv` is gitignored by the starter). Keep it *inside*
`house/` — it's a host build toolchain, not project runtime; Godot never touches Python:

```bash
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python ifcopenshell==0.8.5
.venv/bin/python -c "import ifcopenshell; print(ifcopenshell.version)"    # → 0.8.5
```

**Convert** IFC → GLB (node names = GlobalIds) + a property sidecar keyed by the same ids:

```bash
.venv/bin/python tools/ifc_convert.py ../downloads/Duplex_A_20110907.ifc \
  --glb models/duplex.glb --sidecar models/duplex_props.json
```

Expected (≈1 second wall-clock for this 2.3 MB model):

```
opened ../downloads/Duplex_A_20110907.ifc schema=IFC2X3
GLB written: models/duplex.glb — 286 shapes in 0.9s
sidecar: models/duplex_props.json — 295 elements in 0.1s
total wall-clock: 1.0s
```

The GLB + sidecar under `models/` are **gitignored** — they're runtime-loaded data
(`GLTFDocument` at runtime, no editor import), rebuilt from the IFC whenever you need them.

---

## Step 5 — author the bindings and the viewer config

`binding_map.json` maps home telemetry tags to real IFC elements by their 22-char GlobalId. Pull
the ids straight from the sidecar you just generated, and **verify them** before authoring — never
trust ids copied from another model:

```bash
node -e 'const s=require("./models/duplex_props.json"); const id="2O2Fr$t4X7Zf8NOew3FNqI"; console.log(s[id]?.ifc_class, "|", s[id]?.name)'
# → IfcWallStandardCase | Basic Wall:Exterior - Brick on Block:138157
```

This project's story is six bindings — a compact smart home:

- `living_room.temp`, `kitchen.temp`, `bedroom_1.temp` — each zone's temperature (18–30 °C) painted
  on its exterior brick wall, cold blue `#1e63ff` → warm red `#ff2f2f`. Together they read as a
  whole-house heat map from outside.
- `boiler.temp` — 40–80 °C on the foundation wall by the utility area (hotter range, same ramp).
- `solar.output_w` — rooftop PV output 0–5000 W on the flat roof slab, dark slate `#14142a` →
  bright amber `#ffcf3f`.
- `entrance_door.open` — open state (0–1) as a floating label above the door, green `#37d67a`
  when closed, red `#ff5252` when open.

Each row is `{tag, globalid, min, max, response, ramp, …}` where `response` is `albedo_ramp`
(paint the element) or `label` (float a status label). See `house/binding_map.json` for the full,
self-documenting file — the sim derives its tag list and each tag's range **from this file**, so
data and geometry can never drift.

`viewer.cfg` (Godot INI) ties it together. The important bits:

```ini
[viewer]
model="res://models/duplex.glb"
url="ws://localhost:8765"     ; the sim listens here by default

[twin]
binding_map="binding_map.json"
frame_budget_ms=16.7          ; the 60 fps floor the gate checks (1000/60)
; recording= is left UNSET so a plain boot is LIVE
```

---

## Step 6 — record a deterministic fixture

The data source is `tools/sim/server.js` (a seeded WebSocket sim). For scrubbable playback you
synthesize a fixture from the same generator — no network, byte-reproducible per (seed, seconds,
hz):

```bash
mkdir -p recordings
node tools/sim/record.js --out recordings/house-day.ndjson --seconds 60 --map binding_map.json
```

Expected:

```
record: wrote recordings/house-day.ndjson — frames=3600 duration_ms=59900 tags=6 seed=42 ... sha256=361bc6e...
```

`recordings/` is **committed** (unlike `models/`) — the fixture is repo content.

---

## Step 7 — the gate

`tools/verify_twin.sh` is the whole-pipeline gate. Run it with `GODOT` exported. From a session
with a **real display** add `TWIN_BENCH=1` to run the windowed frame-budget leg too:

```bash
TWIN_BENCH=1 tools/verify_twin.sh
```

The legs and what green looks like:

```
verify-twin: PASS format / lint / parse / scenes / scene-errors / smoke   (the static floor)
JOIN: 286/286 (100.0%)
verify-twin: PASS join-coverage (models/duplex.glb vs models/duplex_props.json)
BIND-SMOKE: OK — 6 node target(s), 0 mmi target(s), 90 frames, 0 drops
verify-twin: PASS binding-smoke (binding_map.json @ seed 42, ws://localhost:8899)
verify-twin: PASS playback-determinism (PLAYBACK-HASH: 9e75d12…, seeks=966,1933, --fixed-fps 60)
BENCH: {"fps":1122.3,"frame_ms":0.89,"draw_calls":1028,...}
verify-twin: PASS frame-budget (frame_ms=0.89 <= budget 16.7ms)
verify-twin: OK
```

Notes:

- **join 286/286 (100%)** — every mesh node matched a sidecar key. A low ratio means the GLB was
  built without `use-element-guids`, or GLB and sidecar came from different conversions.
- **BIND-SMOKE** drives the real viewer headless: seeded sim → DataBus → binding → moving albedo.
  It reports `driven=5 … moved=5` for six bindings because one (the door) is a **label**, not a
  paint — that's correct, not a miss.
- Without `TWIN_BENCH=1` (or in headless CI) the frame-budget leg **SKIPs loudly** — a SKIP is not
  a pass. It needs a real window to measure honest frames.

---

## Step 8 — see it

**Live.** Two moves — start the sim, launch the viewer (it connects to `ws://localhost:8765` by
default and paints):

```bash
node tools/sim/server.js --map binding_map.json &      # terminal 1
$GODOT --path .                                         # terminal 2
```

The duplex loads, the HUD reads **LIVE** (green), and the walls paint into a heat map — cool
bedrooms blue, warm living/kitchen red, the solar roof teal, a floating door label. Stop the sim
and the HUD goes **OFFLINE** (red); restart it and the viewer reconnects on its own.

**Playback** (no sim needed) — pass the recording on the command line:

```bash
$GODOT --path . -- --recording=recordings/house-day.ndjson
```

The HUD turns amber **PLAYBACK**, a timeline bar appears at the bottom, and the fixture plays
through the *same* binding runtime live data uses.

Proof captures live in `house/docs/shots/` (`live.png`, `playback.png`).

**Controls:**

- `Tab` — toggle the camera between **ORBIT** (left-drag rotate, wheel zoom) and **FLY** (mouse
  look, WASD move, Q/E down/up, Shift faster, Esc back to orbit). Fly inside for interior detail.
- `Space` — play/pause (only while the timeline bar is visible, i.e. in playback).
- Timeline bar — drag the slider to scrub; the speed button cycles 0.25× / 0.5× / 1× / 2× / 4×.

---

## Driving it from the web UI

Instead of running the steps by hand you can let the agent Hive do them. From the clone:

```bash
npm start                     # serves the web UI, loads the xenodot plugin automatically
```

Open **http://localhost:8338**. (If that port is busy — another session is already serving —
start on another port with `PORT=8339 npm start` and open that instead. The banner prints the URL
and the project it's pointed at.) Then talk to the Hive in plain language, for example:

- *"Import this IFC into the viewer: `downloads/Duplex_A_20110907.ifc` — convert it, verify the
  GlobalId join, and load it at runtime."* → runs the twin-import pipeline (Step 4).
- *"Bind living-room, kitchen and bedroom temperatures, the boiler, the solar roof and the front
  door to real elements, then author `viewer.cfg`."* → the binding work (Step 5).
- *"Record a 60-second fixture and run the twin gate."* → Steps 6–7.

The web UI relays a real data source into the viewer through the framework's `/twin-data` relay;
for this demo the "real source" is the seeded sim, so start
`node tools/sim/server.js --map binding_map.json` first and the frames fan out to the browser.

---

## Wrinkles I actually hit (and the fix for each)

- **Fresh-clone `validate` fails on a stale library index.** `npm run validate` reported
  `plugin/library/verdicts/index.md: stale`. Fix (the error prints it): `npm run check:library --
  --write`, then re-run `validate` (exits 0). Root cause here was a one-char escaping drift in a
  generated index — a known uncommitted fix in the source repo.
- **`--screenshot` fires too fast for live data.** The built-in `--screenshot=<path>` captures
  after ~12 frames (~0.2 s) — faster than a WebSocket connect + the first 10 Hz frame, so an
  automated live shot can catch the walls still grey (`tags: 0 | waiting for data`). For a
  data-painted capture, let the stream flow first (a live window a human screenshots), or lengthen
  the settle. Playback shots don't have this problem — the data is local and paints immediately.
- **Default camera frames the gable end.** The auto-frame points the camera at the model with a
  fixed yaw/pitch, which on this model looks slightly top-down at a short wall — the heat-mapped
  long facade reads as grey until you **orbit** (left-drag) ~90° to face it. See Troubleshooting.
- **Class-cache "not declared" on a virgin project** (see Troubleshooting) — pre-empted by the
  Step 3 boot, but worth knowing.

---

## Troubleshooting

- **HUD says OFFLINE (red).** The sim isn't running. Start it:
  `node tools/sim/server.js --map binding_map.json`. The viewer reconnects on its own once it's up.
- **Grey walls, no heat map.** Either no data has arrived yet (give the live stream a second), or
  the camera is looking at a wall edge-on / at the gable end. **Left-drag to orbit** ~90° to face
  the long facade — the temperature walls light up. `Tab` into FLY mode to move around freely.
- **`Parse Error: Identifier "TwinHints"/"TwinChunks" not declared`** when running the optimizer
  (`tools/optimize_scene.gd`) on a brand-new project. Godot's global `class_name` registry
  (`.godot/global_script_class_cache.cfg`) isn't populated until an import pass runs. Fix with one
  pass, then re-run:
  ```bash
  $GODOT --headless --editor --quit --path .
  ```
  Booting the project once (Step 3) already builds this cache, which is why the gate passes on a
  fresh project. It's a known follow-up that the tools ideally wouldn't need.
- **`pip install ifcopenshell` → no matching distribution.** Your Python is too new (3.14 has no
  wheel). Use the 3.12 venv: `uv venv --python 3.12 .venv && uv pip install --python
  .venv/bin/python ifcopenshell==0.8.5`.
- **Downloaded IFC won't open / parses as garbage.** A dead sample URL served HTML. Check
  `head -c 13 model.ifc` — it must be `ISO-10303-21;`. Use the XBimDemo raw.githubusercontent.com
  mirror.
- **`npm start` port busy.** Port 8338 is the default; another session may already hold it.
  Start on another port: `PORT=8339 npm start`, and open that URL. Nothing else needs to change.
- **Frame-budget leg SKIPs.** That's expected in a headless/CI context — it needs a real display.
  Re-run from a desktop session with `TWIN_BENCH=1 tools/verify_twin.sh`.

---

## Committing and re-pointing the remote

The `house/` project is its own repo — init and commit it (models/, `.venv`, and the
framework-generated `tools/`+`library*` symlinks are already gitignored, so only real project
content is tracked):

```bash
cd house
git init
git add -A
git commit -m "feat(house): smart-home digital-twin viewer over Duplex_A"
```

The framework clone keeps its `origin` pointing at wherever you cloned it from (the local path,
for now). Once the framework is pushed to GitHub, re-point it:

```bash
cd ../xenodot-forge
git remote set-url origin https://github.com/arthur0n/xenodot-forge.git
git remote -v    # confirm
```
