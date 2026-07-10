# Plant demo asset — sourcing spike verdicts (Phase 1)

Roadmap Nice-to-Have #8. Spike run 2026-07-09/10 on the seat. Framework branch
`feat/plant-demo-asset` (off `40ddfa3`) created for Phase 2; **this spike commits only to
the seat** (`twindemo/twin-spikes/plant-sourcing/`). Nothing vendored into the framework yet.

Bar (from the plan): converts via `tools/ifc_convert.py` with GlobalId join ≥95%; industrial
entity census; clear license (UNCLEAR = OUT); vendorable ≤~15 MB else download-with-sha256;
acceptance criterion 3 wants **≥6 tags across ≥3 equipment classes, pump/tank/valve at minimum**.

## Decision: **TRACK B — synthetic plant IFC** (headline asset). Track A parked.

No real public model qualifies as a *good plant demo asset*. The plant-flavored real models
split into two failure modes, neither of which is a practically-sized, pump/tank/valve-rich
plant:

- **Clinic HVAC** clears every *mechanical* gate (CC0, converts, 100% join, 6.1 MB GLB) but is
  **air-side only** — fans / VAV dampers / AHUs / chiller, **zero pumps/tanks/valves**. Fails
  acceptance criterion 3 and the DEMO_TAGS story (pump temp/flow, tank level, valve position).
- **Clinic MEP** has literal pump/valve/tank and converts at 100% join, but is **125 MB IFC /
  25.4 MB GLB / 53 MB sidecar** (>>15 MB; download-only, clean-stranger friction), carries only
  **1 pump**, and reads as *hospital plumbing*, not an industrial plant.

Track B delivers what neither real model does: literal `IfcPump`/`IfcTank`/`IfcValve`/
`IfcFlowSegment`, **parametric count** (rich pump rows + tank farm → strong DEMO_TAGS story),
tiny asset, **self-owned honest-synthetic license**, a **scale knob** for marketing shots, and
the **best optimizer instancing showcase** (pipe runs = repeated geometry by design). The
de-risk stub is proven: authored IFC4 with real GlobalIds + property sets, converts, **joins
2/2 (100%)**. Ships labeled "synthetic demonstration model" everywhere (plan's honesty rule);
roadmap tick records the synthetic outcome.

**Fallback if the orchestrator prefers a real public model despite the tradeoffs:** the
**Clinic HVAC** (CC0, 6.1 MB GLB — actually vendorable, 100% join) is the only real option that
is practically sized; its binding map would bind fan rpm / damper position / AHU temp / duct
flow (NOT pump/tank/valve), so criterion 3 would need re-reading as "≥3 flow-equipment classes".

## Verdict table

| Candidate | URL — status | License | Size IFC→GLB | Header/Schema | Census (plant classes) | Convert | Join | Verdict |
|---|---|---|---|---|---|---|---|---|
| **Clinic HVAC** `NBU_MedicalClinic_Eng-HVAC.ifc` | in tib.eu DURAARK zip — **LIVE 200** | **CC0** (DURAARK / re3data r3d100012506) | 27.4 MB → 6.1 MB | ISO ✓ / IFC2X3 | FlowMovingDevice 8 (fans), FlowController 115 (VAV dampers), FlowSegment 1548 (ducts), FlowTerminal 440, EnergyConversion 3 (AHU/chiller). **pump/tank/valve = 0** | ✓ 10.9 s, 3967 shapes | **3967/3967 (100%)** | **FAILS crit-3**: air-side only, no pump/tank/valve. (Qualifies on pipeline+license+size — the real-model fallback.) |
| **Clinic MEP-Opt** `NBU_MedicalClinic_Eng-MEP-Optimized.ifc` | same zip — **LIVE 200** | **CC0** | 125.8 MB → 25.4 MB (+53 MB sidecar) | ISO ✓ / IFC2X3 | FlowMovingDevice 137, FlowController 173, FlowSegment 5952 (pipes), FlowTerminal 3053, **FlowStorage 1 (tank)**. Literal: **1 M_Inline Pump, 172 M_Ball Valve, 1 M_Water Heater** | ✓ 61.3 s, 16538 shapes | **16538/16538 (100%)** | **FAILS size**: 125 MB IFC / 25.4 MB GLB >> 15 MB; pumps sparse (1); hospital plumbing, not a plant. |
| Clinic MEP full `NBU_MedicalClinic_Eng-MEP.ifc` | same zip | CC0 | 207.3 MB | ISO ✓ / IFC2X3 | richer than Opt | not run (size) | — | **FAILS size** (worse than Opt). |
| Clinic ELE / CON / Arch | same zip | CC0 | 12–19 MB | ISO ✓ / IFC2X3 | electrical / structural / architectural | not run | — | **OUT**: no plant equipment. |
| **buildingSMART canonical Clinic** artifact URLs | `projects.buildingsmartalliance.org/files/?artifact_id=4289…4292,3451,4288` | — | — | — | — | — | — | **DEAD** (curl exit 000 — host down / DNS fail). The documented dead-URL trap, confirmed. |
| xBIM `XBimDemo/Xbim.TestApp` siblings | github — **LIVE** | sample/test | — | — | only `Duplex_A_20110907.ifc` + `OneWallTwoWindows.ifc` | — | — | **OUT**: no plant/MEP sibling (only the Duplex precedent lives here). |
| Auckland Open IFC Model Repo | `openifcmodel.cs.auckland.ac.nz` — **LIVE 200** | per-model, not stated on landing | — | — | **JS SPA** — per-model list needs the app's API; not curl/WebFetch-walkable | — | — | **UNVERIFIED** (live but not enumerable in-timebox). Fallback source for a future session. |
| buildingsmart-community/Community-Sample-Test-Files | github — **LIVE** | **CC-BY-4.0** (clear) | small samples | — | mixed IFC2X3/IFC4 concept samples | — | — | **OUT**: no qualifying plant model surfaced (single-concept fixtures, not a plant). |
| bimdata `BIMData-Research-and-Development` IFC list | github — **LIVE** | not stated (aggregator) | pointers only | — | pointed to the DURAARK Clinic zip above | — | — | Useful index; license lives at the DURAARK source (CC0). |
| **Track B stub** `plant_stub.ifc` (authored) | seat evidence | **self-owned / synthetic** | 2.5 KB → 2 KB | ISO ✓ / IFC4 | **1 IfcPump + 1 IfcTank**, real GlobalIds, Pset_PumpCommon/Pset_TankCommon | ✓ 0.0 s, 2 shapes | **2/2 (100%)** | **DE-RISKED** — synthetic authoring + convert + join proven. |

## License verification (Clinic family — the real candidates)

- **CC0 (public domain)** per re3data.org repository **r3d100012506** ("DURAARK datasets",
  Data licenses: CC0). The Clinic is the buildingSMART/NIBS "Common BIM Files" Medical Clinic,
  redistributed by DURAARK — same public-sample family as the vendored Duplex, but with a
  *stronger, explicit* license than the Duplex's own soft terms.
- **Caveat for the orchestrator's Phase-1 license re-check:** the DURAARK project site
  (`duraark.eu`) is **dead** (ECONNREFUSED); the CC0 statement is asserted by re3data and the
  data is mirrored by **TIB** (German National Library of Science & Technology). TIB's own
  boilerplate CC0 covers "metadata and thumbnails"; the *dataset* CC0 is the re3data record.
  Credible and documentable, but confirm re3data r3d100012506 before Phase 2 builds on it.

## Track B stub — de-risk output (the guaranteed fallback)

```
$ python gen_plant_stub.py evidence/plant_stub.ifc
WROTE evidence/plant_stub.ifc
TANK_GUID=3sPkXmJdv56xUvAl2tciGH
PUMP_GUID=1$EK4rg$92yvUy2mL2QZ0_
$ head -c 13 evidence/plant_stub.ifc  → ISO-10303-21;
$ python ifc_convert.py evidence/plant_stub.ifc …
opened evidence/plant_stub.ifc schema=IFC4
GLB written — 2 shapes;  sidecar — 2 elements
$ check_twin_join.gd → SIDECAR_KEYS=2  JOIN 2/2 (100.0%)  JOIN-GATE: OK
```

Gotcha recorded: **`IfcTank`/`IfcPump` do not exist in IFC2X3** (they are IFC4+; in IFC2X3 they
are generic `IfcFlowStorageDevice`/`IfcFlowMovingDevice` + ObjectType). The stub authors **IFC4**
so the plant vocabulary is literal. This is why the real Clinic IFC2X3 models express pumps/tanks
as generic flow classes — a binding map over them must inspect Name/ObjectType.

## Dead / problematic URLs — DO NOT RE-WALK

| URL | Status | Note |
|---|---|---|
| `http://projects.buildingsmartalliance.org/files/?artifact_id=4289` (Clinic-IFC) | **DEAD** curl 000 | host down. Same for 4290, 4291, 4292, 3451, 4288. |
| `http://duraark.eu/data-repository/` | **DEAD** ECONNREFUSED | DURAARK project site gone; data survives at TIB mirror. |
| `http://openifcmodel.cs.auckland.ac.nz/` | LIVE 200 but **JS SPA** | landing page has no model list in HTML; enumeration needs the app API. Not a dead URL — a walk-cost trap. |

## Working URLs (verified LIVE this spike)

| URL | Status | Bytes | sha256 |
|---|---|---|---|
| `https://tib.eu/data/duraark/BuildingData/01_IFC/NBU_MedicalClinic_ifc.zip` | **200** | 82,736,494 | `32b5f8008a39bd7510adc8cae35179ad40a48d13a339e6aa0208ef43d6220a5c` |
| `NBU_MedicalClinic_Eng-HVAC.ifc` (in zip) | — | 27,370,562 | `c54c4541f0397f2240ab9cd013e1b89dd59c6a7dd2d067e5e8f876bcb9ac51f2` |
| `NBU_MedicalClinic_Eng-MEP-Optimized.ifc` (in zip) | — | 125,780,663 | `42891896e8b538ef9ad2b37fa9e22c8958724fb5c15e1735b100adcc440a9f06` |

## What Phase 2 needs (Track B)

Generator spec sketch (`gen_plant_ifc.py`, extends the proven stub → IFC4, seat-side, runs in
`.venv-ifc`):

- **Parametric tank farm / pump skid**: `--tanks N` (`IfcTank` + `Pset_TankCommon`: capacity,
  service), `--pumps M` in rows (`IfcPump` + `Pset_PumpCommon`: flow, head, service, line id),
  connecting **pipe runs** (`IfcFlowSegment`, repeated geometry → instancing), inline **valves**
  (`IfcValve` + position), each with a real `ifcopenshell.guid.new()` GlobalId + real extruded
  geometry (the stub's `box_rep` pattern → cylinders for tanks/pipes in Phase 2).
- **Scale knob** = the N/M args (small default for the vendored/fast asset; a big preset for
  marketing shots + the optimizer instancing showcase).
- Binding map (`binding_map.plant.example.json`) authored against the generated GlobalIds:
  ≥6 tags across pump (temp/flow/rpm) + tank (level) + valve (position) — the DEMO_TAGS
  vocabulary, ≥3 equipment classes. Ranges double as sim ranges (existing contract).
- Everything labeled "synthetic demonstration model"; NOTICE.md gets a generator entry (not a
  provenance/mirror entry). Keep the generator on the seat until Phase 3 SEAMS protect-list.
- Proven now: IFC4 authoring + `ifc_convert.py` + 100% join all work unmodified.

## Evidence in this dir

- `gen_plant_stub.py` — the de-risk generator (IFC4, IfcTank+IfcPump+psets).
- `evidence/plant_stub.{ifc,glb,_props.json}` — stub artifacts (tiny, committed).
- `evidence/census.txt`, `evidence/join_results.txt`, `evidence/{hvac,mep}_convert.log`.
- Large real-model artifacts (82 MB zip, 6.1/25.4 MB GLBs, 53 MB sidecar) stayed in scratch —
  NOT committed. Re-fetch from the tib.eu URL + sha256 above if Phase 2 wants the HVAC fallback.
