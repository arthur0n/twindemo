# web-ceiling spike — Phase 1 evidence (measure the browser WASM fps ceiling)

Roadmap Nice-to-Have #6 (web/Grafana embed), Phase 1. SEAT-local evidence; nothing here lands in
the framework (Phase 3 promotes the recipe + `serve_coi` tool, scope per this outcome). The
framework branch `feat/web-embed` was created empty off `main@71e90da` for Phase 3 — Phase 1 needed
NO framework changes.

## Pre-declared usability floor (named BEFORE measuring, per the plan)

**The embeddable (no-threads) variant is "usable" iff it holds ≥30 fps at the street vantage on the
optimized duplex with live binding active.** City scenes inform scale guidance but do not gate.

## Machine / methodology / caveats

- Apple M3 Pro, macOS (Darwin 25.5), **120 Hz ProMotion** display. ONE machine.
- Godot **4.6.3.stable** (`/Applications/Godot.app`), web export templates 4.6.3.stable installed.
- Browsers: **Chrome 150.0.7871.49** (measured), **Safari 26.5.2** (BLOCKED — see below). Firefox
  not installed (opportunistic only; not attempted).
- Chrome driven HEADED via the DevTools Protocol (`driver/chrome_bench.mjs`, Node 22 global
  WebSocket, no deps) so the GPU is real: every run's `webgl_renderer` reads
  **"ANGLE (Apple, ANGLE Metal Renderer: Apple M3 Pro)"** — NOT SwiftShader. Web driver is
  `opengl3` (Godot's **Compatibility / WebGL2** backend); native reference is **Metal / Forward+**.
  This backend gap (WebGL2 Compatibility vs Metal Forward+) is inherent to Godot web export and is
  the headline reason web ≠ native.
- **vsync / cap discipline (carried from native):** browsers present via `requestAnimationFrame`,
  which caps at the display refresh (120 Hz). So `fps` saturates at 120 and `frame_ms` floors at
  8.33 ms on any scene the GPU can keep up with — `fps` alone cannot differentiate light scenes.
  The sub-cap differentiator is **`cpu_ms`** (viewport measured CPU render time). Note
  `gpu_ms` reads **0.0** on both the Metal desktop and the WebGL2 web backend here (Godot's
  viewport GPU timer is unimplemented/zero on these backends), so `cpu_ms` + `frame_ms` carry the
  sub-cap signal, exactly as `bench_scene.gd` intends.
- Warmup 3 s / measure 8 s per run. Live binding ACTIVE every run: DataBus autoload connects to the
  seeded sim (`house/tools/sim/server.js --map binding_map.json`, `ws://localhost:8765`, 6 tags,
  10 Hz), the real `binding_map.gd` runtime resolves + drives albedo/label writes per frame.

## What was built (seat-local, `twin-spikes/web-ceiling/`)

- `viewer/` — spike Godot project (extends the s3-scale lineage): `web_bench.gd` overlay
  (frames-drawn deltas + frame_ms + cpu_ms over the window, one `BENCH: {json}` line via
  `JavaScriptBridge` console.log AND painted on-screen wrapped for screenshot-read), real
  `core/data_bus.gd` + `core/binding_map.gd` + `overlay/tag_label_3d.gd` + `binding_map.json`
  copied from the house viewer, three imported scenes, two export presets (threads / no-threads).
- Scenes: `duplex.tscn` (= `twin-build-validate/.../Duplex_A_20110907_opt.tscn`, 261 nodes, IFC
  GlobalIds preserved so all 6 bindings resolve), `city.scn` (= house-twin c2-optimized
  `city_before` via `--chunks=2`, instanced ~1.3k objects — the plan's "natively at the cap" case),
  `ucity.scn` (= house-twin `--min-instances=100000`, **28,600 individual meshes, no instancing** —
  added as the heavy GPU stress that actually breaks the frame-time cap, so the ceiling has a
  measurable point). The 6 duplex GlobalIds happen to exist in the synthetic city scenes too, so
  binding genuinely resolves 6/6 on every scene (verified: no "resolved 0 targets" warnings).
- `serve.py` — COI static server (`COOP:same-origin` + `COEP:require-corp`, curl-verified on both
  build ports).
- `driver/chrome_bench.mjs` (BENCH scrape + JS-heap via `Performance.getMetrics`),
  `driver/chrome_console.mjs` (auto-attach to iframes, collect console+exceptions — for Grafana).
- `results/chrome_raw.jsonl` (raw per-run BENCH+MEM), `results/chrome_summary.json`.

## Matrix — Chrome 150, headed, real GPU (ANGLE Metal / WebGL2 Compatibility)

2 builds × 3 scenes × 2 vantages = **12/12 cells run**. `bind`=bindings resolved, `busRx`=live
frames received in the window, `drop`=dropped frames, `heap`=JS heap used (MB).

```
build      scene  vant       fps frame_ms  cpu_ms objects  draws     prims  bind  busRx drop load_ms heap
nothreads  duplex street   120.0     8.33    0.58     345    302     27828   6/6    654    0     733  10.3
nothreads  duplex aerial   120.0     8.33    0.58     345    302     27828   6/6    654    0     726  10.3
nothreads  city   street   120.0     8.33    1.07     594    534   1389408   6/6    654    0     773  17.6
nothreads  city   aerial   120.0     8.33    1.86    1284   1164   2782800   6/6    654    0     779  19.5
nothreads  ucity  street    60.8    16.45    9.97   11869  10195    806204   6/6    660    0     918  16.2
nothreads  ucity  aerial    17.9    56.00   40.27   40700  35000   2782800   6/6    655    0     954  16.2
threads    duplex street   120.0     8.33    0.71     345    302     27828   6/6    648    0     771  10.6
threads    duplex aerial   120.0     8.33    0.71     345    302     27828   6/6    654    0     758  10.6
threads    city   street   120.1     8.33    1.20     594    534   1389408   6/6    654    0     824  15.6
threads    city   aerial   120.0     8.33    2.20    1284   1164   2782800   6/6    654    0     826  20.0
threads    ucity  street    60.1    16.64   10.53   11869  10195    806204   6/6    661    0     979  20.1
threads    ucity  aerial    16.7    60.01   43.58   40700  35000   2782800   6/6    661    0     985  17.6
```

## Floor verdict (Chrome)

**PASS — decisively.** No-threads / duplex / street, live-bound: **120.0 fps** (display-capped),
frame_ms 8.33, **cpu_ms 0.58**, bindings 6/6, 654 live frames received, 0 drops. The ≥30 fps floor
is cleared by ~4x, and the 0.58 ms CPU cost sits ~14x under the 8.33 ms display budget — the duplex
does not stress the browser at all. (Safari unverifiable on this machine — see blockers; the floor
verdict is Chrome-only and stated as such.)

## Threads vs no-threads delta

**None beyond run-to-run noise, at every cell.** ucity aerial 16.7 (threads) vs 17.9 (no-threads)
fps, cpu 43.6 vs 40.3 ms; duplex 0.71 vs 0.58 ms. Godot 4's web renderer runs the render loop
single-threaded regardless of `thread_support`, so `thread_support=true` buys **no rendering fps** for
these scenes — it only adds SharedArrayBuffer (which forces COI headers and kills Grafana embedding).
**The embeddable no-threads variant costs nothing in fps.**

## The ceiling (native vs web)

Duplex and the instanced c2-city peg the 120 Hz cap on both variants (cpu 0.6–2.2 ms) — the browser
is not the bottleneck for realistic single-building / instanced-city twins on this GPU. The ceiling
appears only on the **many-unique-mesh worst case** (ucity, 28,600 individual meshes):

| scene / vantage | native cpu_ms* | native fps* | web cpu_ms | web fps | penalty |
|---|---|---|---|---|---|
| ucity / street (11.9k obj drawn) | ~0.99 | (capped/high) | ~10.0–10.5 | ~60 | ~10x cpu |
| ucity / aerial (40.7k obj drawn) | ~4.13 | 163 (uncapped) | ~40–44 | ~17 | ~10x cpu, ~9x fps |

*native numbers from `twin-spikes/vis-range-sweep/NOTES.md` (ucity "off", same coordinates, Metal /
Forward+, uncapped session). The WASM + WebGL2-Compatibility path costs **~10x the native CPU render
time**; on a heavy heterogeneous scene that drops aerial from a comfortable native rate to ~17 fps.
This scopes the recipe (see outcome) — instance / optimize heavy scenes before shipping to web.

## Load / transfer size / memory

| build | wasm | pck (3 scenes) | js | total core | load→1st frame (Chrome) | JS heap (duplex) |
|---|---|---|---|---|---|---|
| threads   | 35.3 MB | 4.5 MB | 0.35 MB | **40.1 MB** | ~0.77 s | 10.6 MB |
| nothreads | 36.0 MB | 4.5 MB | 0.32 MB | **40.7 MB** | ~0.73 s | 10.3 MB |

The pck carries all THREE test scenes (duplex 0.45 + city 2.5 + ucity 1.7 MB); a single-scene deploy
pck ≈ 0.45 MB → **~38 MB total**, matching the Phase-0 boot spike. JS heap stays modest (10–20 MB;
ucity ~16–20 MB). Load-to-first-frame < 1 s on localhost (wasm compile dominates; network transfer of
~38–40 MB is the real-world variable, not measured here — localhost only).

## Grafana iframe attempts (local Grafana OSS 13.0.2, docker) — BOTH recorded

Grafana run: `docker run -p 3001:3000 -e GF_PANELS_DISABLE_SANITIZE_HTML=true
-e GF_AUTH_ANONYMOUS_ENABLED=true -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin grafana/grafana-oss`. Two
dashboards provisioned via API, each a text/HTML panel embedding one variant's `<iframe>`
(`?scene=duplex&vantage=street`). Loaded in Chrome, iframe console auto-attached and scraped.

- **threads-in-Grafana → DOA (as predicted).** Godot's own boot check throws, console verbatim:
  > `The following features required to run Godot projects on the Web are missing:`
  > `SharedArrayBuffer - Check that the web server configuration sends the correct headers.`
  Grafana's top-level document is not `crossOriginIsolated` (it serves no COEP), so the iframe never
  gets SharedArrayBuffer regardless of the build's own COI headers. Empirically confirms the
  spec-reading in the plan.
- **no-threads-in-Grafana → BOOTS, fully live.** BENCH line emitted from inside the Grafana iframe:
  **120 fps, cpu 0.6 ms, bindings 6/6, 654 live frames received, 0 drops.** The OpenTwins-equivalent
  in-iframe embed works at the display cap with live data flowing.

## Safari — BLOCKED (recorded, not faked)

Safari measurement is blocked by THREE independent non-interactive barriers, none grantable to an
automated shell:
1. **AppleScript automation** (`osascript` set-URL / activate) → `AppleEvent timed out (-1712)` —
   the Automation TCC permission for controlling Safari is not granted.
2. **`screencapture`** (the plan's screenshot-read fallback for the on-screen BENCH text) → returns
   an **all-black frame** — the Screen Recording TCC permission is not granted to the process. A
   control capture of the plain desktop was also black, confirming it is the permission, not Safari.
3. **safaridriver WebDriver** — daemon starts and answers `/status`, but session creation returns
   *"You must enable 'Allow remote automation' in the Developer section of Safari Settings"* — an
   interactive Safari Develop setting (and `safaridriver --enable` needs sudo).

All three require GUI/admin interaction. Safari (the SAB/WASM worst case and the browser a
stakeholder will open) is therefore **UNVERIFIED on this machine** — a stated caveat, not a result.

## Provisional outcome: FULL GRAFANA RECIPE (no-threads embeddable variant)

The pre-declared floor passes by ~4x (no-threads duplex street live-bound = 120 fps capped, 0.58 ms
cpu), the no-threads build boots and runs fully live-bound **inside a real Grafana text/HTML-panel
iframe** at the 120 Hz cap, and `thread_support` offers **zero fps advantage** — so nothing is
sacrificed by shipping the embeddable variant as the primary recipe. Two caveats bound it, to be
written into the Phase-3 docs from these numbers: (1) a **scale ceiling** — heavy many-unique-mesh
scenes (28.6k individual meshes) fall to ~17 fps at aerial at ~10x the native CPU cost, so the recipe
ships with "instance/optimize heavy scenes; instanced/c2-style cities at ~1.3k objects hold the cap";
(2) **Safari is unverified here** — the recipe should state Chrome-measured numbers and flag Safari as
untested pending a machine with the TCC permissions. The threads variant remains the documented
companion-tab / own-domain-with-COI path for anyone who wants it, but it is not required and gains
nothing on fps. Matches the plan's first outcome (embeddable variant usable → full recipe).

## Reproduce

```
# 0. re-copy the scene inputs (gitignored — identical to these tracked sources)
cp twin-build-validate/models/Duplex_A_20110907_opt.tscn twin-spikes/web-ceiling/viewer/models/duplex.tscn
cp house-twin/models/vissweep/c2_off.scn                 twin-spikes/web-ceiling/viewer/models/city.scn
cp house-twin/models/vissweep/ucity_off.scn              twin-spikes/web-ceiling/viewer/models/ucity.scn
# 1. sim (live data source)
cd house && node tools/sim/server.js --map binding_map.json --port 8765 &
# 2. export builds
cd twin-spikes/web-ceiling/viewer
$GODOT --headless --path . --export-release "Web-threads"
$GODOT --headless --path . --export-release "Web-nothreads"
# 3. COI serve
python3 ../serve.py ../builds/threads 8071 &
python3 ../serve.py ../builds/nothreads 8072 &
# 4. Chrome matrix (headed CDP scrape)
node driver/chrome_bench.mjs "http://localhost:8072/index.html?scene=duplex&vantage=street&build=nothreads"
# 5. Grafana attempts
docker run -d -p 3001:3000 -e GF_PANELS_DISABLE_SANITIZE_HTML=true -e GF_AUTH_ANONYMOUS_ENABLED=true \
  -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin grafana/grafana-oss   # + provision dashboards via API
node driver/chrome_console.mjs "http://localhost:3001/d/twinthreads/twin-threads-embed?kiosk" 26
```
