#!/usr/bin/env python3
"""
tests/test_semver.py - Comprehensive Unit Tests for SemVer 2.0.0 Engine
"""

import unittest
import sys
import os

# Import semver engine from tools/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import semver

class TestSemVerEngine(unittest.TestCase):

    def test_parse_and_format_semver(self):
        self.assertEqual(semver.parse_semver("0.0.0"), (0, 0, 0))
        self.assertEqual(semver.parse_semver("v1.2.3"), (1, 2, 3))
        self.assertEqual(semver.parse_semver("0.17.0"), (0, 17, 0))
        self.assertEqual(semver.format_semver(0, 17, 0), "0.17.0")
        with self.assertRaises(ValueError):
            semver.parse_semver("invalid")

    def test_commit_type_parsing(self):
        self.assertEqual(semver.get_commit_type("feat: add feature"), "feat")
        self.assertEqual(semver.get_commit_type("fix: resolve bug"), "fix")
        self.assertEqual(semver.get_commit_type("docs(readme): update guide"), "docs")
        self.assertEqual(semver.get_commit_type("chore: bump deps"), "chore")
        self.assertIsNone(semver.get_commit_type("invalid commit message"))

    def test_breaking_change_detection(self):
        self.assertTrue(semver.is_breaking_change("feat!: breaking change in cascade api"))
        self.assertTrue(semver.is_breaking_change("fix(core)!: breaking fix"))
        self.assertTrue(semver.is_breaking_change("feat: add feature\n\nBREAKING CHANGE: changes public api"))
        self.assertTrue(semver.is_breaking_change("fix: bug\n\nBREAKING-CHANGE: removes option"))
        self.assertFalse(semver.is_breaking_change("feat: normal feature without breaking"))
        self.assertFalse(semver.is_breaking_change("fix: standard bugfix"))

    def test_version_bumping_rules(self):
        # 0.0.0 baseline
        v0 = (0, 0, 0)

        # feat: bumps minor from 0.0.0 -> 0.1.0
        v1 = semver.bump_version(v0, "feat: first feature")
        self.assertEqual(v1, (0, 1, 0))

        # fix: bumps patch from 0.1.0 -> 0.1.1
        v2 = semver.bump_version(v1, "fix: patch issue")
        self.assertEqual(v2, (0, 1, 1))

        # chore: bumps patch from 0.1.1 -> 0.1.2
        v3 = semver.bump_version(v2, "chore: maintenance update")
        self.assertEqual(v3, (0, 1, 2))

        # feat: bumps minor from 0.1.2 -> 0.2.0 (resets patch)
        v4 = semver.bump_version(v3, "feat: second feature")
        self.assertEqual(v4, (0, 2, 0))

        # breaking: bumps major from 0.2.0 -> 1.0.0 (resets minor & patch)
        v5 = semver.bump_version(v4, "feat!: major architecture redesign")
        self.assertEqual(v5, (1, 0, 0))

    def test_conventional_commit_regex(self):
        valid = [
            "feat: add feature",
            "fix: bugfix",
            "perf: optimize loop",
            "refactor: clean up modules",
            "docs: update index",
            "test: add unit test",
            "chore: configure git hook",
            "feat(ui): add modal window",
            "fix(watcher)!: breaking fix"
        ]
        for msg in valid:
            self.assertIsNotNone(semver.CONVENTIONAL_REGEX.match(msg), f"Should match: {msg}")

        invalid = [
            "fixed bug",
            "Update README",
            "WIP",
            ": missing type",
            "feat no colon",
            "random: invalid type"
        ]
        for msg in invalid:
            self.assertIsNone(semver.CONVENTIONAL_REGEX.match(msg), f"Should not match: {msg}")

    def test_history_replay_integrity(self):
        history = semver.replay_history()
        self.assertGreaterEqual(len(history), 27)
        # Check first commit is 0.1.0
        self.assertEqual(history[0][1], "0.1.0")
        # Check commit 27 is 0.17.0
        self.assertEqual(history[26][1], "0.17.0")

if __name__ == "__main__":
    unittest.main()
