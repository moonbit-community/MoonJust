#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("runner.py")
SPEC = importlib.util.spec_from_file_location("moonjust_runner", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class RunnerTest(unittest.TestCase):
    def test_modes_are_layered_and_deterministic(self) -> None:
        self.assertEqual(runner.mode_commands("fast")[0], ("moon", "fmt", "--check"))
        self.assertIn(
            (
                "moon",
                "check",
                "--target",
                "all",
                "--warn-list",
                "+73",
                "--deny-warn",
            ),
            runner.mode_commands("fast"),
        )
        self.assertLess(len(runner.mode_commands("fast")), len(runner.mode_commands("verify")))
        self.assertEqual(runner.mode_commands("verify"), runner.mode_commands("verify"))
        self.assertIn(("./tools/verification/checks/compatibility.sh",), runner.mode_commands("compat"))

    def test_build_registry_claims_a_key_once(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            registry = runner.BuildRegistry(Path(raw))
            first = registry.claim("abc", "native", "release")
            second = registry.claim("abc", "native", "release")
            self.assertEqual(first[0], second[0])
            self.assertTrue(first[1])
            self.assertFalse(second[1])
            self.assertEqual(len(list(Path(raw).glob("*.json"))), 1)

    def test_build_registry_reuses_only_matching_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            artifact = root / "artifact.bin"
            command = (sys.executable, "-c", f"from pathlib import Path; Path({str(artifact)!r}).write_bytes(b'ok')")
            registry = runner.BuildRegistry(root / "registry")
            first = registry.ensure("abc", "native", "debug", command, artifact, root, "moon-test", True)
            second = registry.ensure("abc", "native", "debug", command, artifact, root, "moon-test", True)
            self.assertFalse(first["reused"])
            self.assertTrue(second["reused"])
            artifact.write_bytes(b"changed")
            third = registry.ensure("abc", "native", "debug", command, artifact, root, "moon-test", True)
            self.assertFalse(third["reused"])
            marker = next((root / "registry").glob("*.json"))
            self.assertEqual(json.loads(marker.read_text())["sha256"], runner.sha256(artifact))

    def test_build_key_requires_full_provenance(self) -> None:
        with self.assertRaises(ValueError):
            runner.build_key({"commit_sha": "abc"})

    def test_build_spec_is_target_and_profile_specific(self) -> None:
        command, artifact, flags = runner.build_spec(Path("/repo"), "wasm1", "release")
        self.assertEqual(command[:3], ("moon", "build", "--frozen"))
        self.assertIn("--target", command)
        self.assertEqual(command[command.index("--target") + 1], "wasm")
        self.assertTrue(str(artifact).endswith("_build/wasm/release/build/cmd/just/just.wasm"))
        self.assertIn("--strip", flags)

    def test_evidence_validation_rejects_wrong_head(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "evidence.json"
            path.write_text(
                json.dumps(
                    {
                        "schema_version": 2,
                        "run_id": "run",
                        "stage": "fast",
                        "mode": "fast",
                        "commit_sha": "a" * 40,
                        "tree_sha": "b" * 40,
                        "baseline_sha": None,
                        "host": {},
                        "target": "all",
                        "profile": "debug",
                        "toolchain": {},
                        "dependencies": {},
                        "registry_refs": [],
                        "artifact_hashes": {},
                        "started_at": 0,
                        "duration_ms": 0,
                        "exit_code": 0,
                        "status": "passed",
                        "classification": "correctness",
                        "measurements": {"tasks": []},
                    }
                )
            )
            with self.assertRaises(ValueError):
                runner.validate_evidence(path, "c" * 40)

    def test_windows_shell_probes_use_bash(self) -> None:
        with mock.patch.object(runner.platform, "system", return_value="Windows"):
            command = runner.executable_command(("./tools/verification/checks/platform.sh",))
            self.assertTrue(command[0].lower().endswith(("bash", "bash.exe")))
            self.assertEqual(command[1], "./tools/verification/checks/platform.sh")

    def test_windows_oracle_uses_git_bash_not_wsl(self) -> None:
        with mock.patch.object(runner.platform, "system", return_value="Windows"):
            self.assertEqual(
                runner.oracle_build_command(),
                (r"C:\Program Files\Git\bin\bash.exe", "./tools/upstream/build_oracle.sh"),
            )

    def test_windows_oracle_artifact_uses_exe_suffix(self) -> None:
        with mock.patch.object(runner.platform, "system", return_value="Windows"):
            artifact = runner.official_artifact(Path("/repo"))
            self.assertTrue(str(artifact).endswith("target/release/just.exe"))


if __name__ == "__main__":
    unittest.main()
