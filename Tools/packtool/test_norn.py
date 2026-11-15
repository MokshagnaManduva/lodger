#!/usr/bin/env python3
"""Acceptance checks on the compiled art, hit masks and complete pack graph."""
from pathlib import Path
import json
import subprocess
import sys
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "Packs/Norn"


class NornAcceptance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pack = json.loads((PACK / "pack.json").read_text())
        cls.atlases = {}
        cls.frames = {}
        for name, texture in cls.pack['textures'].items():
            art = np.asarray(Image.open(PACK / texture['file']).convert('RGBA'))
            cls.atlases[name] = art
            cls.frames[name] = [art[r*128:(r+1)*128, c*128:(c+1)*128]
                               for r in range(texture['rows']) for c in range(texture['columns'])]
        cls.art = cls.atlases['body']
        cls.cells = cls.frames['body']

    def test_schema_assets_and_reachability(self):
        subprocess.run([sys.executable, str(ROOT / "Tools/packtool/packtool.py"),
                        "validate", str(PACK)], check=True)

    def test_transparency_palette_and_safe_margin(self):
        colors = set()
        for name, art in self.atlases.items():
            tex = self.pack['textures'][name]
            self.assertEqual(art.shape, (tex['rows']*128, tex['columns']*128, 4))
            self.assertEqual(set(np.unique(art[:, :, 3])), {0, 255})
            colors.update(map(tuple, np.unique(art[art[:, :, 3] > 0, :3], axis=0)))
            for i, cell in enumerate(self.frames[name]):
                with self.subTest(texture=name, cell=i):
                    ys, xs = np.where(cell[:, :, 3] > 0)
                    self.assertGreater(len(xs), 2000)
                    self.assertGreaterEqual(min(xs.min(), ys.min()), 8)
                    self.assertLessEqual(max(xs.max(), ys.max()), 119)
        # New motion art must use the same palette as the original body.
        self.assertLessEqual(len(colors), 32)

    def test_ground_registration_and_airborne_tuck(self):
        # Reading/crouching must not sink through the floor, nor walk poses float.
        for i in [*range(12), 14, 15]:
            ys = np.where(self.cells[i][:, :, 3] > 0)[0]
            self.assertEqual(int(ys.max()) + 1, self.pack['stage']['ground']['y'], i)
        self.assertLess(np.where(self.cells[12][:, :, 3] > 0)[0].max(), 106)
        for cell in self.frames['sleep']:
            self.assertEqual(int(np.where(cell[:, :, 3] > 0)[0].max()) + 1, 114)
        for cell in self.frames['held']:
            self.assertLess(int(np.where(cell[:, :, 3] > 0)[0].max()) + 1, 114)

    def test_no_single_frame_clips_and_six_drawn_motion_poses(self):
        for name, clip in self.pack['clips'].items():
            with self.subTest(clip=name):
                self.assertGreaterEqual(len(clip['frames']), 2)
                cells = self.frames[clip['texture']]
                self.assertGreaterEqual(len({cells[f['cell']].tobytes() for f in clip['frames']}), 2)
        for name in ['sleep', 'held', 'fall']:
            clip = self.pack['clips'][name]
            self.assertEqual(clip['loop'], 'forever')
            self.assertEqual(len(clip['frames']), 6)
            cells = self.frames[clip['texture']]
            # Exclude the floating root: all six character poses must change.
            self.assertEqual(len({cells[f['cell']][:, 45:112].tobytes() for f in clip['frames']}), 6)

    def test_walk_is_four_drawn_leg_poses(self):
        clip = self.pack['clips']['tiptoe']
        legs = [self.frames[clip['texture']][f['cell']][85:114, 45:104].tobytes()
                for f in clip['frames']]
        self.assertEqual(len(set(legs)), 4)

    def test_polished_grounded_sequences_and_endpoints(self):
        def rendered(name):
            clip = self.pack['clips'][name]
            return [self.frames[clip['texture']][f['cell']] for f in clip['frames']]
        for name in ['tiptoe', 'greet', 'settle', 'read', 'wake']:
            for frame in rendered(name):
                self.assertEqual(int(np.where(frame[:, :, 3] > 0)[0].max()) + 1, 114, name)
        # Exact rendered continuity at boundaries, including after the transfer.
        for end, start in [('greet', 'idle'), ('settle', 'read'), ('wake', 'idle')]:
            np.testing.assert_array_equal(rendered(end)[-1], rendered(start)[0])
        np.testing.assert_array_equal(rendered('read')[0], rendered('wake')[0])
        self.assertGreaterEqual(len({f.tobytes() for f in rendered('greet')}), 7)
        self.assertGreaterEqual(len({f.tobytes() for f in rendered('settle')}), 6)
        # Sitting/standing must no longer borrow the impact/landing drawing.
        for name in ['settle', 'wake']:
            self.assertTrue(all(not np.array_equal(f, self.cells[14]) for f in rendered(name)))

    def test_mask_decoder_matches_every_visible_pixel(self):
        for name, path in self.pack['hitMasks'].items():
            with self.subTest(texture=name):
                self.check_mask((PACK / path).read_bytes(), self.frames[name])

    def check_mask(self, data, cells):
        self.assertEqual(data[:5], b'LMSK\x01')
        offset = 5

        def number():
            nonlocal offset
            value = shift = 0
            while True:
                b = data[offset]
                offset += 1
                value |= (b & 127) << shift
                if b < 128:
                    return value
                shift += 7

        self.assertEqual((number(), number(), number()), (128, 128, len(cells)))
        for cell in cells:
            runs = [number() for _ in range(number())]
            decoded = np.concatenate([np.full(n, i % 2, dtype=bool) for i, n in enumerate(runs)])
            np.testing.assert_array_equal(decoded, (cell[:, :, 3] > 0).ravel())
        self.assertEqual(offset, len(data))

    def test_preview_matches_runtime_and_sources(self):
        np.testing.assert_array_equal(np.asarray(Image.open(PACK / "preview.png")), self.cells[0])
        # The looks are derived from the compiled palette at build time; everything
        # else in the runtime manifest is the authored source, unchanged.
        authored = {k: v for k, v in self.pack.items() if k != 'appearance'}
        self.assertEqual(authored, json.loads((PACK / 'reference/runtime-v1/pack.source.json').read_text()))
        self.assertEqual([c['id'] for c in self.pack['appearance']], ['potion'])
        preview = json.loads((PACK / 'runtime.js').read_text().split('window.NORN_DRAFTS = ', 1)[1].rstrip(';\n'))
        for study in preview:
            clip = self.pack['clips'][study['id']]
            texture = self.pack['textures'][clip['texture']]
            self.assertEqual(study['src'], texture['file'])
            self.assertEqual((study['columns'], study['rows']), (texture['columns'], texture['rows']))
            self.assertEqual(study['cells'], [f['cell'] for f in clip['frames']])
            self.assertEqual(study['frames'], [f['ms'] for f in clip['frames']])


if __name__ == '__main__':
    unittest.main()
