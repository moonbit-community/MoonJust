#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("dependency_fingerprint.py")
SPEC = importlib.util.spec_from_file_location("moonjust_dependency_fingerprint", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
fingerprint = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fingerprint)


class DependencyFingerprintTest(unittest.TestCase):
    def write_index(self, moon_home: Path, records: list[dict[str, str]]) -> None:
        index = moon_home / "registry/index/user/moonbitlang/example.index"
        index.parent.mkdir(parents=True)
        index.write_text(
            "".join(json.dumps(record) + "\n" for record in records),
            encoding="utf-8",
        )

    def test_latest_record_uses_publication_time(self) -> None:
        with tempfile.TemporaryDirectory(prefix="moonjust-registry-") as temporary:
            home = Path(temporary)
            self.write_index(
                home,
                [
                    {
                        "name": "moonbitlang/example",
                        "version": "1.0.0",
                        "checksum": "old",
                        "created_at": "2026-01-01T00:00:00Z",
                    },
                    {
                        "name": "moonbitlang/example",
                        "version": "1.1.0",
                        "checksum": "new",
                        "created_at": "2026-02-01T00:00:00Z",
                    },
                ],
            )
            self.assertEqual(
                fingerprint.latest_registry_record("moonbitlang/example", home),
                {
                    "module": "moonbitlang/example",
                    "version": "1.1.0",
                    "checksum": "new",
                },
            )

    def test_stale_candidate_dependency_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="moonjust-dependency-") as temporary:
            moon_mod = Path(temporary) / "moon.mod"
            moon_mod.write_text(
                'name = "example/project"\n\nimport {\n'
                '  "moonbitlang/example@1.0.0",\n}\n',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "not latest"):
                fingerprint.assert_declares_dependency_set(
                    moon_mod,
                    [
                        {
                            "module": "moonbitlang/example",
                            "version": "1.1.0",
                            "checksum": "new",
                        }
                    ],
                )

    def test_normalization_only_rewrites_direct_versions(self) -> None:
        with tempfile.TemporaryDirectory(prefix="moonjust-normalize-") as temporary:
            moon_mod = Path(temporary) / "moon.mod"
            moon_mod.write_text(
                'name = "example/project"\n\nimport {\n'
                '  "moonbitlang/example@1.0.0",\n}\n',
                encoding="utf-8",
            )
            fingerprint.normalize_direct_dependencies(
                moon_mod,
                [
                    {
                        "module": "moonbitlang/example",
                        "version": "1.1.0",
                        "checksum": "new",
                    }
                ],
            )
            self.assertIn("moonbitlang/example@1.1.0", moon_mod.read_text())


if __name__ == "__main__":
    unittest.main()
