# Per-element inspection panel

**Goal** — Click a 3D element in the viewer → a HUD panel shows that element's STATIC metadata (identity + maintenance/warranty fields from the property sidecar), distinct from the live-tag green→red overlay.

**Scope (in)**
- **Pick:** click a mesh → resolve its GlobalId via the EXISTING join rule (`binding_map.gd._globalid_from_name`: node-or-parent name, 22-char prefix). Physics raycast: generate a collision body per mesh at model load, cast a ray from the cursor through the active `Camera3D`.
- **Sidecar reader:** load `models/<name>_props.json` once; look up the picked GlobalId → `{ifc_class, name, psets}`.
- **Panel:** a CanvasLayer panel (sibling of the existing HUD `Readout`) showing a CURATED field list for the picked element; empty/hidden until a pick; dismiss on click-empty or Esc.
- **Faithful render (accuracy goal):** display exactly what the sidecar holds — a missing field shows "—", a placeholder string shows verbatim. Never fabricate or infer a value.

**Scope (out)**
- Raw pset dump / collapsible full-pset view — Later; v1 is the curated set only.
- Schema enrichment (real warranty dates, service-history log, review-data source) — its own data-sourcing project, not this panel.
- Highlighting/outlining the picked mesh — Later (nice, not required for inspection).
- MultiMesh-instance picking (optimized scenes) — v1 targets un-instanced named `MeshInstance3D` nodes (the duplex); instanced-field pick is Later.

**Frame budget** — n/a. Panel is event-driven HUD + one-time per-mesh collision-body build on load; not a render-throughput change. The existing frame-budget gate still applies to the scene unchanged. (If collision-body build ever measurably costs load time on a large model, bench it then — not a v1 concern on the 295-mesh duplex.)

**Binding map** — n/a for the data-binding runtime. The panel REUSES the same GlobalId join key but reads the property SIDECAR, not `binding_map.json`. No new tag bindings, no DataBus touch. Curated field map (sidecar pset path → panel label):

| Panel label | Sidecar source |
|---|---|
| Name | top-level `name` |
| IFC class | top-level `ifc_class` |
| Tag number | `PSet_Revit_Other.TagNumber` |
| Serial number | `PSet_Revit_Other.SerialNumber` |
| Asset ID | `PSet_Revit_Other.AssetIdentifier` |
| Installed | `PSet_Revit_Other.InstallationDate` |
| Warranty start | `PSet_Revit_Other.WarrantyStartDate` |

Field map is DATA (a const dict or a small `design/panel-fields.json`), not per-field `if` chains — same discipline as the binding map. Missing pset/key → "—".

**Acceptance**
- **Pick resolves:** a click on a rendered mesh yields a non-empty GlobalId that is a key in `<name>_props.json` — assert ≥ 95% of visible meshes resolve to a sidecar key when picked (same JOIN ratio the join gate already proves; picking must not regress it).
- **Panel populates:** after a pick, the panel's Name and IFC-class lines equal the sidecar's `name`/`ifc_class` for that GlobalId (headless-checkable: drive the pick seam programmatically with a known GlobalId, assert panel field values == sidecar values).
- **Faithful render:** for an element missing `PSet_Revit_Other`, the maintenance rows read "—" (no crash, no fabricated value).
- **No live-path regression:** `twin-verify` binding smoke still `BIND-SMOKE: OK`; the panel adds no DataBus consumer.
- **Pick vs camera:** dragging to orbit/pan does NOT trigger a pick (pick fires on click-release without drag) — _human F5_.
- **Panel renders legibly over the scene** — _human F5_.

**Skill notes**
- `twin-import` — owns the GlobalId join rule (node-or-parent, 22-char prefix) and the sidecar shape (`{ifc_class, name, psets, quantities}` keyed by GlobalId). The panel must reuse this join, not invent a second lookup.
- `twin-verify` — join-coverage gate proves pickable meshes carry resolvable GlobalIds; run after the pick slice. Panel/overlay change → re-run binding smoke (must stay OK; panel is not a DataBus consumer).
- `xenodot:godot-code-rules` — typed GDScript, DataBus (if ever touched) by PATH not global. Panel does not touch DataBus.
- `xenodot:godot-composition` — pick handler as its own node (signals up: emits `element_picked(globalid)`); panel a separate node consuming it. Do not fold pick logic into `main.gd` or the camera rig.
- Camera rig already owns mouse drag (`core/camera_rig.gd`); the pick input must coexist — fire on click WITHOUT drag, and not consume the orbit/pan gestures.

**Later**
- Raw/collapsible full-pset view under the curated header.
- Highlight/outline the picked element.
- Enrichment source for real maintenance/service-history values (placeholder → real).
- MultiMesh-instance picking for optimized scenes (resolve instance index → `twin_globalids[index]`).
- Show the element's live tag value in the panel if it is bound (join panel ↔ binding map).

**Open questions** — none; scope locked via interview (physics pick, curated fields, enrichment parked, accuracy is the goal).

## Slice decomposition (ordered)

1. **Pick → GlobalId** (domain: **overlay**, touches scene input) — physics raycast: build per-mesh collision at model load, cursor ray through the active camera, resolve hit → GlobalId via the existing join rule; emit `element_picked(globalid)`. Coexist with camera-rig mouse (no pick on drag). Verify with the join-coverage gate + a headless pick-seam assert.
2. **Sidecar reader + curated field map** (domain: **binding**/data — sidecar, not the live map) — load `<name>_props.json` once, look up GlobalId, map psets → curated field list via the data-driven field map; missing → "—".
3. **Panel UI** (domain: **overlay**) — CanvasLayer panel sibling to the HUD, populated from slice 2 on the slice-1 signal; dismiss on click-empty/Esc; faithful render.
