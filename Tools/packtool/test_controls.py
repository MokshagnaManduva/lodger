#!/usr/bin/env python3
"""packtool validate must agree with the engine loader about tuning controls."""
import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Tools/packtool"))
import packtool  # noqa: E402

BASE = json.loads((ROOT / "Tests/Fixtures/test.solidsquare/pack.json").read_text())
SLIDER = {"label": "S", "min": 0.5, "max": 2, "default": 1}
ZERO = {"label": "Z", "min": 0, "max": 2, "default": 1}
TOGGLE = {"type": "toggle", "label": "T", "default": True}
BOTH = {"s": SLIDER, "z": ZERO, "t": TOGGLE}


def flag(name):
    return {"flag": {"name": name, "value": True}}


def click(when):
    return [{"on": "pointer.click", "state": "resting", "when": when}]


def errors(version, tuning, interrupts, mutate=None):
    pack = copy.deepcopy(BASE)
    pack["format"] = version
    pack["tuning"] = tuning
    pack["states"]["resting"]["interrupts"] = interrupts
    if mutate:
        mutate(pack)
    rep = packtool.Report()
    if packtool.check_schema(pack, rep):
        packtool.check_controls(pack, rep)
    return rep.errors


class Controls(unittest.TestCase):
    def test_valid_forms(self):
        self.assertEqual(errors(2, BOTH, click(flag("t"))), [])
        self.assertEqual(errors(2, BOTH, click({"not": {"all": [flag("t")]}})), [])
        self.assertEqual(errors(2, BOTH, [{"on": {"user.idle": {"knob": "s"}}, "state": "resting"}]), [])

    def test_flag_must_name_a_toggle(self):
        self.assertTrue(errors(2, BOTH, click(flag("missing"))))
        self.assertTrue(errors(2, BOTH, click({"any": [{"not": flag("s")}]})))

    def test_threshold_must_name_a_positive_slider(self):
        for name in ("t", "missing", "z"):
            self.assertTrue(errors(2, BOTH, [{"on": {"user.idle": {"knob": name}}, "state": "resting"}]), name)

    def test_weight_by(self):
        def walker(knob):
            def mutate(pack):
                pack["states"]["resting"] = {"clip": "still", "duration": {"minMs": 100, "maxMs": 200},
                                             "next": [{"state": "resting", "weight": 1, "weightBy": knob}]}
            return mutate
        self.assertEqual(errors(2, BOTH, [], walker("z")), [])
        self.assertTrue(errors(2, BOTH, [], walker("t")))
        self.assertTrue(errors(2, BOTH, [], walker("missing")))
        self.assertTrue(errors(1, {"z": ZERO}, [], walker("z")))

    def test_malformed_controls(self):
        self.assertTrue(errors(2, {"t": dict(TOGGLE, min=0)}, click(flag("t"))))
        self.assertTrue(errors(2, {"t": dict(TOGGLE, default=1)}, click(flag("t"))))
        self.assertTrue(errors(2, {"s": dict(SLIDER, default=9)}, click({"lowPower": True})))

    def test_format_one(self):
        self.assertEqual(errors(1, {"s": SLIDER}, click(flag("anything"))), [])
        self.assertTrue(errors(1, BOTH, click({"lowPower": True})))
        self.assertTrue(errors(1, {"s": dict(SLIDER, group="G")}, click({"lowPower": True})))
        self.assertTrue(errors(1, {"s": SLIDER}, [{"on": {"user.idle": {"knob": "s"}}, "state": "resting"}]))
        self.assertTrue(errors(1, {"s": SLIDER}, [{"on": "controls.changed", "state": "resting"}]))
        self.assertEqual(errors(2, BOTH, [{"on": "controls.changed", "state": "resting", "when": flag("t")}]), [])


class ReferenceLooks(unittest.TestCase):
    """The bundled characters' appearance options must act on colours that exist."""

    def test_recolor_sources_exist_in_the_art(self):
        import looks
        for pack_dir in sorted((ROOT / "Packs").glob("*/pack.json")):
            pack = json.loads(pack_dir.read_text())
            choices = pack.get("appearance", [])
            self.assertTrue(choices, f"{pack_dir.parent.name} offers no looks")
            used = {looks.hex_color(c) for c in
                    looks.atlas_colors(pack_dir.parent / t["file"] for t in pack["textures"].values())}
            rep = packtool.Report()
            packtool.check_appearance(pack, rep)
            self.assertEqual(rep.errors, [])
            for choice in choices:
                default = next(o for o in choice["options"] if o["id"] == choice["default"])
                self.assertFalse(default.get("recolor"), "the default look must be the art as drawn")
                for option in choice["options"]:
                    if option is default:
                        continue
                    sources = set(option["recolor"])
                    self.assertTrue(sources & used, f"{choice['id']}/{option['id']} changes nothing")
                    self.assertGreaterEqual(len(sources & used), len(sources) // 2,
                                            f"{choice['id']}/{option['id']} names colours the art does not use")
                    for source, target in option["recolor"].items():
                        self.assertNotEqual(source, target)


if __name__ == "__main__":
    unittest.main()
