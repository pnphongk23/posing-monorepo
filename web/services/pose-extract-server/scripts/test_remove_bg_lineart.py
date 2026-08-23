import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from remove_bg_lineart import remove_white_background


class RemoveWhiteBackgroundTests(unittest.TestCase):
    def test_preserves_rgb_transparency_and_antialiasing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = np.full((12, 12, 4), 255, dtype=np.uint8)
            source[..., 3] = 255
            source[2:10, 2] = [20, 80, 210, 255]  # colored line
            source[2:10, 3] = [235, 235, 235, 255]  # anti-aliased edge
            source[5, 5] = [245, 245, 245, 255]  # near-white background
            src = root / "source.png"
            dst = root / "result.png"
            Image.fromarray(source, "RGBA").save(src)

            remove_white_background(src, dst)
            result = np.asarray(Image.open(dst).convert("RGBA"))

            self.assertEqual(tuple(result[4, 2, :3]), (20, 80, 210))
            self.assertGreaterEqual(int(result[4, 2, 3]), 250)
            self.assertGreater(int(result[4, 3, 3]), 0)
            self.assertLess(int(result[4, 3, 3]), 192)
            self.assertEqual(int(result[0, 0, 3]), 0)
            self.assertEqual(int(result[5, 5, 3]), 0)

    def test_quality_gate_rejects_one_mp_scattered_noise(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = np.full((1024, 1024, 4), 255, dtype=np.uint8)
            for y, x in ((10, 10), (100, 200), (250, 400), (400, 700),
                         (600, 50), (700, 800), (850, 300), (1000, 900)):
                source[y, x] = [20, 20, 20, 255]
            src = root / "noise.png"
            dst = root / "result.png"
            Image.fromarray(source, "RGBA").save(src)

            with self.assertRaisesRegex(ValueError, "quality gate"):
                remove_white_background(src, dst)
            self.assertFalse(dst.exists())

    def test_quality_gate_accepts_sparse_pose_like_stroke(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = np.full((1024, 1024, 4), 255, dtype=np.uint8)
            source[300:620, 512] = [35, 80, 190, 255]
            source[300:620, 513] = [210, 220, 235, 255]
            src = root / "sparse-pose.png"
            dst = root / "result.png"
            Image.fromarray(source, "RGBA").save(src)

            remove_white_background(src, dst)
            result = np.asarray(Image.open(dst).convert("RGBA"))
            self.assertGreaterEqual(int(np.count_nonzero(result[..., 3] >= 160)), 300)
            self.assertEqual(tuple(result[400, 512, :3]), (35, 80, 190))

    def test_source_alpha_is_applied_once_and_colored_edges_survive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = np.full((16, 16, 4), 255, dtype=np.uint8)
            source[4:12, 4] = [30, 90, 180, 128]
            source[4:12, 5] = [210, 220, 240, 200]
            src = root / "alpha.png"
            dst = root / "result.png"
            Image.fromarray(source, "RGBA").save(src)

            remove_white_background(src, dst)
            result = np.asarray(Image.open(dst).convert("RGBA"))
            self.assertEqual(tuple(result[8, 4, :3]), (30, 90, 180))
            self.assertEqual(int(result[8, 4, 3]), 128)
            self.assertEqual(tuple(result[8, 5, :3]), (210, 220, 240))
            self.assertGreater(int(result[8, 5, 3]), 0)


if __name__ == "__main__":
    unittest.main()
