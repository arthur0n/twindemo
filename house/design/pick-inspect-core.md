# Pick → GlobalId → property panel (core machinery)

**Goal** — Click a rendered element → the viewer resolves its IFC GlobalId, reads that
element's static properties from the sidecar through a data-driven field map, and shows them
in a HUD panel. All three are REUSABLE core; no house-demo content ships in the code.

**Scope (in)**
- **Pick → GlobalId:** ray through the ACTIVE camera on left-click-release; hit → GlobalId via
  the ONE existing join (see Reuse check); emit `element_picked(globalid: String)`. Suppress on
  drag (a click that moved the mouse past a small pixel threshold is a camera gesture, not a pick).
- **Sidecar reader + field-map indirection:** load `<name>_props.json` once, look up a GlobalId →
  `{ifc_class, name, psets, quantities}`, project psets → an ordered curated field list via a
  DATA-DRIVEN map (`design/panel-fields.json`); a missing pset/key → `"—"`. Reader is core; the
  map file is demo config.
- **Panel UI:** a CanvasLayer panel (sibling of the existing HUD `Overlay`) populated on
  `element_picked` via the reader; dismiss on empty-space click and Esc.

**Scope (out)**
- Any house-specific curated field entries — demo data; the map ships EMPTY or with one neutral
  example row (demos being archived).
- Real field VALUES / enrichment (warranty, service history) — a separate data-sourcing project.
- MultiMesh-instance picking (optimized scenes) — v1 targets un-instanced named `MeshInstance3D`;
  instance-index pick is Later.
- Highlight/outline of the picked mesh — nice, not needed to inspect.
- Raw full-pset dump / collapsible view — Later; v1 is the curated projection only.
- Live tag value in the panel — Later (would join panel ↔ binding map).

**Frame budget** — n/a. Event-driven HUD + one-time per-mesh collision (or AABB) build at model
load; not a render-throughput change. The scene's existing frame-budget gate is unaffected. If the
load-time collision build ever measurably costs on a large model, bench it then (not a v1 concern).

**Binding map** — n/a for the live runtime. This path REUSES the GlobalId join key but reads the
property SIDECAR, never `binding_map.json`; no new tag bindings, no DataBus consumer added. The
**field map is a different artifact** (sidecar pset-path → panel label), and it is DATA, not `if`
chains:

`design/panel-fields.json` (schema v1 — core; SHIP EMPTY or one neutral example):
```json
{
  "version": 1,
  "fields": [
    { "label": "Name",      "source": "name" },
    { "label": "IFC class", "source": "ifc_class" }
  ]
}
```
- `source` is either a top-level sidecar key (`name`, `ifc_class`) or a dotted pset path
  (`<PsetName>.<Key>`). Reader resolves the path; unresolved → `"—"`.
- `fields` is an ORDERED array → the panel renders rows in that order. Every listed field IS
  displayed (worst case "field joined-but-never-shown" is structurally impossible: the map is the
  render list itself). No inline literal thresholds/GlobalIds anywhere — GlobalIds come from picks,
  labels+paths come from this file.
- The two example rows (`name`, `ifc_class`) are sidecar TOP-LEVEL keys present on every element and
  carry no house semantics — the neutral example. A real deployment appends pset rows to this file;
  code never changes.

**Binding map (GlobalId → visual response)** — pick: `hit node → GlobalId (existing join) →
element_picked`. panel: `GlobalId → sidecar record → curated rows → CanvasLayer panel`.

**Acceptance** (bindable assertions)
- **Pick resolves:** driving the pick seam with a hit on a rendered mesh yields a non-empty
  GlobalId that is a key in `<name>_props.json` — JOIN ≥ 95% of visible meshes resolve to a
  sidecar key when picked (the same ratio `check_twin_join.gd` already proves; picking must not
  introduce a second join with a lower ratio).
- **No fire on drag:** a press→move-past-threshold→release does NOT emit `element_picked`; a
  press→release without move DOES. (headless-drivable via synthesized `InputEventMouseButton` +
  `InputEventMouseMotion`; state delta on an emit counter.)
- **Reader projects the map:** for a known GlobalId, the reader returns rows whose `label`/value
  pairs equal the field-map order, with each value == the sidecar value at `source` (or `"—"` when
  absent). Assert programmatically against a fixture sidecar + fixture `panel-fields.json`.
- **Faithful render:** a `source` path with no sidecar value yields exactly `"—"` — no crash, no
  fabricated value (state assert on the reader's output).
- **Panel populates on signal:** emitting `element_picked(gid)` with a known gid sets the panel's
  rows to the reader's output for that gid (headless: connect signal, emit, read panel row Labels).
- **No live-path regression:** `twin-verify` binding smoke stays `BIND-SMOKE: OK` — this path adds
  no DataBus consumer.
- **Esc/click dismiss coexists with camera:** panel-open + ORBIT → Esc closes panel; FLY → Esc
  still exits fly (panel consumes Esc only when open AND `camera_rig.mode == ORBIT`). — _human F5_
  for the live feel; the mode-gated branch itself is unit-assertable.
- **Panel renders legibly over the scene** — _human F5_.

**Reuse check (the one join)** — The viewer has EXACTLY ONE GlobalId join:
`core/binding_map.gd._globalid_from_name` (22-char prefix, IFC base64 alphabet `GLOBALID_CHARS`)
plus the node/parent tree walk in `_walk`; `tools/check_twin_join.gd` applies the identical rule for
the gate. There is no parallel lookup anywhere. **All three slices bind through it** — the pick
resolves hit-node → GlobalId with this exact rule (node name, else parent name, 22-char prefix), the
reader keys the sidecar by that GlobalId, the panel is populated by that same GlobalId. To keep the
rule single-sourced, factor `_globalid_from_name` (+ the node-or-parent candidate logic) into a small
shared helper (e.g. `core/globalid.gd`) that both `binding_map.gd` and the picker call — do NOT
copy-paste the constant/loop. DataBus contract (house/CLAUDE.md) is untouched: no new socket, no new
signal on the bus; the panel is a pure sidecar consumer, consistent with the overlay convention
(CanvasLayer HUD sibling, typed autoload handle by PATH).

**Core-vs-demo boundary**
- Slice 1 (pick): 100% core — no demo data at all.
- Slice 2 (reader + map): reader/lookup/projection = core; `design/panel-fields.json` = demo config,
  shipped empty/one-neutral-example. Code only READS it.
- Slice 3 (panel): 100% core — renders whatever rows the reader returns.

**Skill notes**
- `twin-import` — owns the join rule (node-or-parent, 22-char prefix) and the sidecar shape
  (`{ifc_class, name, psets, quantities}` keyed by GlobalId). Reuse the join, do not invent a second.
- `twin-verify` — join-coverage gate proves pickable meshes carry resolvable GlobalIds; run after
  slice 1. Any overlay/panel change → re-run binding smoke (must stay `BIND-SMOKE: OK`; panel is not
  a DataBus consumer).
- `xenodot:godot-code-rules` — typed GDScript; if DataBus were ever touched, by PATH not the global
  (it is not touched here). File-header + size caps apply to each new script.
- `xenodot:godot-composition` — picker is its own node (signals up: `element_picked`); panel a
  separate node consuming it; reader a plain helper. Do NOT fold pick logic into `main.gd` or the
  camera rig. Camera rig already owns mouse drag — the pick input coexists (fire on click WITHOUT
  drag; never consume orbit/pan gestures; Esc mode-gated).

**Later**
- MultiMesh-instance picking (resolve instance index → `twin_globalids[index]`).
- Highlight/outline the picked element.
- Raw/collapsible full-pset view under the curated header.
- Show the picked element's live tag value if it is bound (join panel ↔ binding map).
- Enrichment source for real property values (placeholder → real).

**Open questions** — none. Forks resolved by default (form tool unavailable at runtime): (a) pick =
builder's choice of physics-body vs ray-vs-AABB, contract locked to active-camera ray + existing
join + no-fire-on-drag; (b) field-map lives in `design/panel-fields.json`, reader reads it; (c) Esc
mode-gated (panel consumes Esc only when open AND camera ORBIT, no camera-rig edit).

## Slice decomposition (ordered)

1. **Pick → GlobalId** — domain **overlay** (touches scene input + a shared join helper).
   Extract `_globalid_from_name` (+ node-or-parent candidate) into `core/globalid.gd`; build the
   picker node (per-mesh collision OR ray-vs-AABB, builder's choice), ray through the ACTIVE camera
   on click-release-without-drag, hit → GlobalId via the helper, emit `element_picked(globalid)`.
   Verify: join-coverage gate + headless pick-seam assert (emit-on-click, no-emit-on-drag).
2. **Sidecar reader + field-map** — domain **binding**/data (sidecar, NOT the live map).
   Load `<name>_props.json` once, look up GlobalId, project psets → ordered rows via
   `design/panel-fields.json`; missing → `"—"`. Ship the map empty/one-neutral-example.
   Verify: headless reader assert against a fixture sidecar + fixture map.
3. **Panel UI** — domain **overlay**. CanvasLayer panel sibling to the HUD; on slice-1's
   `element_picked` call slice-2's reader and render its rows; dismiss on empty-space click and
   (mode-gated) Esc. Verify: headless emit→panel-rows assert; binding smoke stays OK; _human F5_
   for legibility + drag/Esc feel.

**Concurrency:** Slice 1 (`core/globalid.gd`, `core/binding_map.gd` refactor, a new picker node) and
Slice 2 (a new reader helper + `design/panel-fields.json`) have DISJOINT file scopes → can run
concurrent. Slice 3 (panel) depends on BOTH signals (slice 1's `element_picked`) and the reader
(slice 2) → sequential, after both. Slice 1 also touches `binding_map.gd` (extract the helper) so it
is adjacent to any concurrent binding-map work — serialize against that if it exists.
