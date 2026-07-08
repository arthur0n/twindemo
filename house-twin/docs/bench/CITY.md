# City-block optimisation showcase (Phase 5 W2)

A repeated-BIM stress scene that shows the shipped twin-optimize toolkit turning a naive
28,600-mesh scene into 1,140 region-chunked MultiMeshes — measured before vs after, at two
camera vantages, with the IFC GlobalId join preserved 100%.

## What the demo shows

- **Scene:** one real BIM model (`duplex.glb`, 286 meshes / 224 distinct mesh groups) deep-copied
  into a **10x10 grid at 30 m pitch → 28,600 MeshInstance3Ds** (`models/city_before.scn`), lit by
  one shadowless directional light + flat ambient.
- **Optimise (shipped tool, auto defaults):** `tools/optimize_scene.gd` groups by
  (mesh, material) and collapses every group into region-chunked MultiMeshInstance3D fields. Auto
  grid picks a per-group side from instance count (`--target-per-chunk=32`): the ~100-instance
  groups get a 2x2 grid (4 chunks each), yielding **1,140 MultiMeshes** (in the sane
  ~1,000–1,600 band). Nodes 28,703 → 1,244 (`models/city_after.scn`).
- **Join preserved:** the GlobalId join gate resolves **28,600/28,600 (100%)** on the optimised
  scene via the `twin_globalids` metas each chunk carries.
- **Headline (aerial / overview vantage): 132.6 → 221.2 fps (+67%)**, render-thread submit
  **4.31 → 0.73 ms (−83%)**, objects-rendered **40,500 → 1,594 (−96%)**, draw calls
  **5,579 → 1,594 (−71%)**.

## Reproduce

```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot   # 4.6.3
DUPLEX=/path/to/duplex.glb                            # real BIM source model
STREET="139.5,1.7,135:139.5,1.7,0"                    # eye-level, down a street inside the block
AERIAL="-65,260,-65:135,15,135"                       # high oblique, whole block in frustum

# 1. Generate the 10x10 city (headless)
$GODOT --headless --path . --script scripts/gen_city.gd -- \
    --src=$DUPLEX --out=res://models/city_before.scn --grid=10 --pitch=30.0

# 2. Optimise with the shipped tool at auto defaults (headless)
$GODOT --headless --path . --script tools/optimize_scene.gd -- \
    --in=res://models/city_before.scn --out=res://models/city_after.scn \
    --report=docs/bench/city_report.json

# 3. Join gate on the optimised output (headless) — expect 28,600/28,600 (100%)
$GODOT --headless --path . --script tools/check_twin_join.gd -- \
    --scene=res://models/city_after.scn --sidecar=/path/to/duplex_props.json

# 4. Bench both scenes at both vantages (WINDOWED — needs a display; appends rows to the JSON)
for SCENE in city_before city_after; do for V in "$STREET" "$AERIAL"; do
    $GODOT --path . -s tools/bench_scene.gd -- res://models/$SCENE.scn \
        --vantage "$V" --warmup 2 --measure 8 --out docs/bench/city_bench.json
done; done

# 5. Screenshots (WINDOWED) — 4 PNGs into docs/shots/
$GODOT --path . --resolution 1280x720 -s scripts/shot_city.gd -- \
    res://models/city_after.scn --vantage "$AERIAL" --out $PWD/docs/shots/city_after_aerial.png
```

## The numbers (M3 Pro, Metal / Forward+, 1280x720 window, vsync off, shadows off)

Metric order per row: **fps · frame_ms · cpu_ms (render-thread submit) · draw_calls ·
objects_rendered · primitives**.

Street (eye-level walkthrough inside the block):

- before: 164.7 · 6.07 · 1.59 · 1,828 · 11,829 · 805,674
- after:  146.8 · 6.81 · 0.50 · 773 · 773 · 1,342,936
- delta:  fps −11% · **cpu_ms −69%** · draws −58% · objects −93% · primitives +67%

Aerial (overview, whole block in frustum):

- before: 132.6 · 7.54 · 4.31 · 5,579 · 40,500 · 2,774,000
- after:  221.2 · 4.52 · 0.73 · 1,594 · 1,594 · 2,774,000
- delta:  **fps +67% · cpu_ms −83%** · draws −71% · objects −96% · primitives ±0%

Optimiser report (`docs/bench/city_report.json`): chunks=auto, target_per_chunk=32,
groups 224/224 instanced, multimeshes=1,140, instances_total=28,600, nodes 28,703 → 1,244,
est_draw_items 34,800 → 1,376, occluders/vis-ranges added 0 (no-ops on a fully-instanced scene).

## Caveats — read before quoting a number

- **One machine:** Apple M3 Pro, macOS, Metal (Forward+), Godot 4.6.3, 1280x720 window, 8 s
  measure / 2 s warmup. Recipes generalise; the exact percentages are this machine's.
- **Shadows OFF** (single shadowless directional + flat ambient). Shadow passes would re-rank
  everything — this isolates the instancing cost.
- **fps here was NOT display-capped** (the before-street ran at 164.7, above the 120 Hz ProMotion
  cap), so the raw fps deltas above are real rather than saturated. On a capped run fps pins at
  120 and **`cpu_ms` (render-thread submit) is the honest differentiator** — it drops 69–83% here
  regardless, so it is the metric to trust across hardware.
- **Street fps regressed slightly (−11%) even though CPU submit dropped 69%.** Chunk culling is
  coarser than per-node culling: the auto 2x2 grid pulls whole buildings into the frustum that
  per-node culling would have rejected, so the after draws **+67% more primitives** at street
  level. The M3 Pro is object-count-bound at aerial (where the after wins big) but
  primitive/GPU-bound at street when uncapped. **The primary camera decides the tuning:** a
  walkthrough viewer wants a finer grid (lower `--target-per-chunk`); an overview dashboard is
  happy with the coarse auto default. This run used the auto defaults unchanged.
- **Duplicate GlobalIds:** the 100 copies share each duplex's ids, so the 100% join proves "every
  rendered instance resolves to a property record", not unique-id coverage — a real multi-building
  site needs per-building-unique ids upstream before per-instance data binding.

## Web export (stretch)

A standalone browser build of the optimised city (an orbiting camera around
`models/city_after.scn`, gl_compatibility renderer) is exported to `exports/web/`. Serve it with
the bundled COI-header server (Godot threaded web needs cross-origin isolation):

```sh
cd exports/web && python3 serve.py 8060   # then open http://127.0.0.1:8060/index.html
```

Bundle: **~38 MB total** (index.wasm 37.0 MB, index.pck 2.7 MB, index.js 358 KB, index.html
5.5 KB). Boot check: the server returns HTTP 200 on `index.html` with both
`Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`, the
wasm is reachable (37 MB, 200), and the html references index.js/pck/wasm. (Serve-level check —
a full in-browser render check was not run headlessly.)
