#!/usr/bin/env python3
"""merge.py — authoritative fade-sweep analysis + retention math (open item #6, Phase 2).

STREET cpu is taken from the INTERLEAVED REPEAT arrays (json/repeat/<config>.json), NOT the single
sequential pass (json/ucity_street.json). Why: this session's presentation is display-capped at
120 Hz (frame_ms 8.33 flat) and the render load is ~1-2 ms out of an 8.33 ms budget, so the single
pass drifted NON-PHYSICALLY (fade configs read LOWER cpu than their no-fade base despite rendering
MORE objects). Interleaving each config across cycles cancels the monotonic thermal drift and
restores the physical ordering (base < fade5 < fade12). The two families were benched in separate
thermal blocks, so each family's retention uses ITS OWN off baseline: off.json rows 0-3 = the
aggressive block, rows 4-7 = the coarser block (append order, asserted below).

AERIAL is the single sequential pass (json/ucity_aerial.json) — reliable there: every vis config
renders an IDENTICAL 12700 objects (the whole scene is past even end+margin from 374 m up, so the
fade band contains nothing), cpu is flat within noise, fade is FREE at aerial. Objects/draws/prims
are deterministic per-frame counts (not timings) and are the backbone metric; cpu corroborates.

Retention (rule clause b): win_with_fade / win_without_fade vs the SAME-block off.
  nofade_win = off - base ; fade_win = off - fade ; retention = fade_win / nofade_win
  fade_cost  = fade - base (>0 = fade costs cpu; the mechanism: fade renders the crossing objects
               with alpha, so objects_rendered/draw_calls/primitives RISE with margin).
Rule (aggressive tier, street): adopt-with-fade iff retention >= 0.80 AND the pop is eliminated.
"""
import json, os, statistics as st

HERE = os.path.dirname(os.path.abspath(__file__))
NOISE_MS = 0.03
# cross-session anchor (vis-range-sweep, SEPARATE session, uncapped): the required cross-session view
XSESSION = {"street": {"off": 0.99, "aggressive_win": 0.45}, "aerial": {"off": 4.13, "aggressive": 1.20}}
FAMILIES = {"aggressive": ["aggressive", "aggressive_fade5", "aggressive_fade12"],
            "coarser": ["coarser", "coarser_fade5", "coarser_fade12"]}
OFF_SLICE = {"aggressive": slice(0, 4), "coarser": slice(4, 8)}  # off.json append order


def cpu_arr(cfg):
    return [r["cpu_ms"] for r in json.load(open(os.path.join(HERE, "json", "repeat", f"{cfg}.json")))]


def rep(cfg):
    r = json.load(open(os.path.join(HERE, "reports", f"ucity_{cfg}.json")))
    return {"vis_ranges_set": r["vis_ranges_set"], "vis_fade_margin": r["vis_fade_margin"],
            "vis_fade_mode": r["vis_fade_mode"]}


def one_bench(cfg, vantage):  # deterministic per-frame counts from the single sequential pass
    rows = json.load(open(os.path.join(HERE, "json", f"ucity_{vantage}.json")))
    order = ["off", "aggressive", "aggressive_fade5", "aggressive_fade12",
             "coarser", "coarser_fade5", "coarser_fade12"]
    return rows[order.index(cfg)]


def stat(a):
    return {"median": round(st.median(a), 3), "min": round(min(a), 3), "n": len(a)}


def main():
    off_all = cpu_arr("off")
    assert len(off_all) == 8, f"off.json has {len(off_all)} rows, expected 8 (2 blocks x 4 cyc)"
    summary = {"noise_floor_ms": NOISE_MS, "cross_session_anchor": XSESSION,
               "method": "street=interleaved-repeat medians; aerial=single-pass; deterministic obj/draw/prim",
               "street": {}, "aerial": {}}

    for fam, cfgs in FAMILIES.items():
        off = off_all[OFF_SLICE[fam]]
        off_s = stat(off)
        base_cfg = cfgs[0]
        base = cpu_arr(base_cfg)
        rows = []
        for cfg in cfgs:
            arr = cpu_arr(cfg)
            r = rep(cfg)
            b = one_bench(cfg, "street")
            rec = {"config": cfg, **r, "cpu": stat(arr),
                   "objects_rendered": b["objects_rendered"], "draw_calls": b["draw_calls"],
                   "primitives": b["primitives"]}
            for est in ("median", "min"):
                nofade_win = off_s[est] - stat(base)[est]
                fade_win = off_s[est] - rec["cpu"][est]
                rec[f"nofade_win_{est}"] = round(nofade_win, 3)
                rec[f"fade_win_{est}"] = round(fade_win, 3)
                rec[f"retention_{est}"] = round(fade_win / nofade_win, 3) if abs(nofade_win) > 1e-9 else None
            rec["fade_cost_median"] = round(rec["cpu"]["median"] - stat(base)["median"], 3)
            rec["d_objects_vs_base"] = rec["objects_rendered"] - one_bench(base_cfg, "street")["objects_rendered"]
            if cfg != base_cfg:
                rmed, rmin = rec["retention_median"], rec["retention_min"]
                rec["retention_verdict"] = ("PASS>=80%" if rmed >= 0.80 and rmin >= 0.80
                                            else "BORDERLINE" if (rmed >= 0.80) != (rmin >= 0.80)
                                            else "FAIL<80%")
            rows.append(rec)
        summary["street"][fam] = {"off_cpu": off_s, "rows": rows}

    # aerial context (single pass; fade band empty from 374 m -> fade is free)
    aerial = []
    for cfg in ["off"] + FAMILIES["aggressive"] + FAMILIES["coarser"]:
        b = one_bench(cfg, "aerial"); r = rep(cfg)
        aerial.append({"config": cfg, **r, "cpu_ms": b["cpu_ms"],
                       "objects_rendered": b["objects_rendered"], "draw_calls": b["draw_calls"]})
    summary["aerial"] = aerial

    with open(os.path.join(HERE, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)

    print("== ucity/STREET (interleaved-repeat; per-family own OFF) ==")
    for fam in FAMILIES:
        blk = summary["street"][fam]
        print(f"\n-- {fam} tier --  OFF cpu median={blk['off_cpu']['median']} min={blk['off_cpu']['min']} (n={blk['off_cpu']['n']})")
        print(f"{'config':<18}{'ranged':>7}{'margin':>7}{'cpu_med':>8}{'cpu_min':>8}{'objects':>8}{'Δobj':>7}{'draws':>7}"
              f"{'cost_med':>9}{'ret_med':>8}{'ret_min':>8}  verdict")
        for r in blk["rows"]:
            rm = f"{r['retention_median']*100:.0f}%" if r.get("retention_median") is not None else "-"
            rn = f"{r['retention_min']*100:.0f}%" if r.get("retention_min") is not None else "-"
            v = r.get("retention_verdict", "no-fade base")
            print(f"{r['config']:<18}{r['vis_ranges_set']:>7}{r['vis_fade_margin']:>7.0f}"
                  f"{r['cpu']['median']:>8.2f}{r['cpu']['min']:>8.2f}{r['objects_rendered']:>8}{r['d_objects_vs_base']:>7}"
                  f"{r['draw_calls']:>7}{r['fade_cost_median']:>9.3f}{rm:>8}{rn:>8}  {v}")

    print("\n== ucity/AERIAL (single-pass; context — fade band empty, fade FREE) ==")
    print(f"{'config':<18}{'ranged':>7}{'margin':>7}{'cpu_ms':>8}{'objects':>9}{'draws':>7}")
    base_obj = aerial[0]["objects_rendered"]
    for r in aerial:
        print(f"{r['config']:<18}{r['vis_ranges_set']:>7}{r['vis_fade_margin']:>7.0f}{r['cpu_ms']:>8.2f}"
              f"{r['objects_rendered']:>9}{r['draw_calls']:>7}")
    print("\nwrote summary.json")


if __name__ == "__main__":
    main()
