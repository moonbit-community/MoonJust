#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("verify_manifest.py")
SPEC = importlib.util.spec_from_file_location("moonjust_verify_manifest", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
verify = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify)


class VerifyManifestTest(unittest.TestCase):
    def test_release_approved_difference_requires_exact_policy_metadata(self) -> None:
        row = {
            "id": "JUST-1.57.0-2235",
            "disposition": "unsupported",
            "tracking": "ADR-0019",
            "evidence": [
                "docs/adr/0019-direct-child-process-lifecycle.md",
                "tools/upstream/run_official_harness.py",
            ],
        }
        self.assertTrue(verify.is_release_approved_difference(row))
        row["tracking"] = "unreviewed"
        self.assertFalse(verify.is_release_approved_difference(row))

    def test_incomplete_release_message_is_stable_and_actionable(self) -> None:
        rows = [
            {"id": "JUST-1.57.0-0022", "owner_area": "semantic-loader"},
            {"id": "JUST-1.57.0-0023", "owner_area": "semantic-loader"},
            {"id": "JUST-1.57.0-0410", "owner_area": "lexer"},
        ]
        self.assertEqual(
            verify.incomplete_release_message(rows),
            "strict release evidence is incomplete for 3 registrations "
            "(lexer=1, semantic-loader=2); first IDs: "
            "JUST-1.57.0-0022, JUST-1.57.0-0023, JUST-1.57.0-0410",
        )


if __name__ == "__main__":
    unittest.main()
