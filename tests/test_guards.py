"""The core's guards: numbers, written dates, clipped texts, shortened paths."""
import os
import sys
import unittest
from datetime import datetime
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from something import guards  # noqa: E402

INSTANT = 1791349200          # 2026-10-07T05:00:00Z


class Values(unittest.TestCase):
    def test_number(self):
        for hostile in (True, False, -1, float("nan"), float("inf"), "3", None, 1e15, 10 ** 400):
            self.assertIsNone(guards.number(hostile), hostile)
        self.assertEqual((guards.number(0), guards.number(2.5)), (0, 2.5))
        self.assertIs(guards.number(0), 0)                      # zero is a number, not an absence

    def test_iso(self):
        self.assertEqual(datetime.fromisoformat(guards.iso(INSTANT)).timestamp(), INSTANT)
        self.assertIsNotNone(datetime.fromisoformat(guards.iso(INSTANT)).tzinfo)
        for hostile in (None, True, "12", -1, float("nan"), 1e15):
            self.assertIsNone(guards.iso(hostile), hostile)

    def test_clip(self):
        self.assertEqual(guards.clip("  welcome \n", 10), "welcome")
        self.assertEqual(guards.clip("welcome", 7), "welcome")
        self.assertEqual(guards.clip("welcome", 4), "wel…")
        self.assertEqual(guards.clip("up down", 4), "up…")      # no whitespace before the cut
        self.assertEqual((guards.clip(None, 4), guards.clip(12, 4)), ("", ""))

    def test_tilde(self):
        with mock.patch.dict(os.environ, {"HOME": "/h"}):
            self.assertEqual([guards.tilde(p) for p in ("/h/y", "/h", "/hX/y", "/elsewhere/h/y")],
                             ["~/y", "~", "/hX/y", "/elsewhere/h/y"])
            for hostile in (None, "", 3, ["/h"]):
                self.assertIsNone(guards.tilde(hostile), hostile)


if __name__ == "__main__":
    unittest.main()
