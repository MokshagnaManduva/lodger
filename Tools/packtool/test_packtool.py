#!/usr/bin/env python3
"""Negative tests for packtool validate.

A linter that never fails is worthless. Each case below mutates a known-good
manifest in one specific way and asserts that the intended check fires.

    python3 Tools/packtool/test_packtool.py
"""
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import packtool  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
KLIEN = ROOT / "Packs" / "klien"
MIN = ROOT / "Tests" / "Fixtures" / "test.solidsquare"


def run(pack: dict, root: Path) -> packtool.Report:
    rep = packtool.Report()
    if packtool.check_schema(pack, rep):
        packtool.check_references(pack, root, rep, assets=False)
        packtool.check_idle_policy(pack, rep)
        packtool.check_anchors(pack, rep)
        packtool.check_reachability(pack, rep)
    return rep


def expect(name: str, rep: packtool.Report, needle: str, kind: str = "error") -> bool:
    pool = rep.errors if kind == "error" else rep.warnings
    hit = any(needle in m for m in pool)
    print(f"  {'PASS' if hit else 'FAIL'}  {name}")
    if not hit:
        print(f"        expected an {kind} containing {needle!r}; got:")
        for m in pool or ["<none>"]:
            print(f"          - {m}")
    return hit


def main() -> int:
    # The full blueprint exercises walk, sleep, sockets and audio. Keep those
    # negative tests independent of the smaller playable idle milestone.
    base = json.loads((KLIEN / "reference/planned-pack.json").read_text())
    minimal = json.loads((MIN / "pack.json").read_text())
    ok = True

    print("baseline")
    rep = run(copy.deepcopy(base), KLIEN)
    good = not rep.errors
    print(f"  {'PASS' if good else 'FAIL'}  full Klien blueprint is clean (assets aside)")
    if not good:
        for e in rep.errors:
            print(f"        - {e}")
    ok &= good

    rep = run(copy.deepcopy(minimal), MIN)
    good = not rep.errors
    print(f"  {'PASS' if good else 'FAIL'}  minimum viable pack validates "
          f"(one texture, one clip, one state)")
    if not good:
        for e in rep.errors:
            print(f"        - {e}")
    ok &= good

    print("\nRule 2 - quiescent state discipline")
    p = copy.deepcopy(base)
    p["states"]["asleep"]["next"] = [{"state": "idle", "weight": 1}]
    ok &= expect("quiescent state with 'next' is rejected", run(p, KLIEN), "cannot schedule")

    p = copy.deepcopy(base)
    p["states"]["asleep"]["duration"] = {"minMs": 1000, "maxMs": 2000}
    ok &= expect("quiescent state with 'duration' is rejected", run(p, KLIEN), "requires a timer")

    p = copy.deepcopy(base)
    p["states"]["asleep"]["motion"] = {"type": "walk", "speed": 10}
    ok &= expect("quiescent state with motion is rejected", run(p, KLIEN), "display link")

    p = copy.deepcopy(base)
    p["states"]["asleep"]["clip"] = "tip_hat"
    ok &= expect("quiescent state on a finite clip is rejected", run(p, KLIEN), "non-looping")

    print("\nanchor discipline")
    p = copy.deepcopy(base)
    del p["clips"]["idle"]["frames"][1]["anchors"]["orbit"]
    ok &= expect("missing anchor on a reachable frame is rejected", run(p, KLIEN),
                 "absent on frame(s) [1]")

    p = copy.deepcopy(base)
    p["clips"]["idle"]["frames"][1]["anchors"]["orbit"] = {"x": 90, "y": 52}
    ok &= expect("anchor drift is warned about", run(p, KLIEN), "jumps", kind="warning")

    print("\nreferences")
    p = copy.deepcopy(base)
    p["states"]["idle"]["next"][0]["state"] = "nope"
    ok &= expect("dangling next-state reference is rejected", run(p, KLIEN), "unknown state 'nope'")

    p = copy.deepcopy(base)
    p["clips"]["idle"]["frames"][0]["cell"] = 999
    ok &= expect("cell outside the atlas grid is rejected", run(p, KLIEN), "outside")

    p = copy.deepcopy(base)
    p["parts"][2]["bind"]["anchor"] = "nonexistent"
    ok &= expect("socket bound to an undeclared anchor is rejected", run(p, KLIEN), "absent on frame(s)")

    print("\ncapability gating")
    p = copy.deepcopy(base)
    p["requires"] = ["audio"]
    ok &= expect("surface 'windowTop' without the windowEdges capability is rejected",
                 run(p, KLIEN), "windowEdges")

    p = copy.deepcopy(base)
    p["requires"] = ["windowEdges"]
    ok &= expect("declaring sounds without the audio capability is rejected",
                 run(p, KLIEN), "does not require the 'audio'")

    print("\nstate graph")
    p = copy.deepcopy(base)
    p["states"]["orphan"] = {"clip": "idle", "next": [{"state": "idle", "weight": 1}]}
    ok &= expect("unreachable state is warned about", run(p, KLIEN), "unreachable", kind="warning")

    p = copy.deepcopy(base)
    p["states"]["stuck"] = {"clip": "idle"}
    p["states"]["idle"]["next"].append({"state": "stuck", "weight": 1})
    ok &= expect("dead-end state is rejected", run(p, KLIEN), "dead end")

    print("\nschema")
    p = copy.deepcopy(base)
    p["states"]["idle"]["interrupts"][0]["on"] = {"pointer.telepathy": 5}
    ok &= expect("event outside the closed vocabulary is rejected", run(p, KLIEN), "schema")

    p = copy.deepcopy(base)
    p["states"]["idle"]["next"][0]["when"] = {"eval": "mascot.environment.cursor.y < 100"}
    ok &= expect("expression-language guard is rejected", run(p, KLIEN), "schema")

    print(f"\n{'ALL TESTS PASSED' if ok else 'FAILURES ABOVE'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
