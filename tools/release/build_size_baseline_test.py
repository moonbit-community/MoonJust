#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("build_size_baseline.py")
SPEC = importlib.util.spec_from_file_location("moonjust_size_baseline", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
size_baseline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(size_baseline)


class BuildSizeBaselineTest(unittest.TestCase):
    def test_run_preserves_stdout_and_stderr_on_failure(self) -> None:
        with self.assertRaisesRegex(
            RuntimeError,
            r"(?s)command failed \(7\):.*stdout:\s+baseline-out.*stderr:\s+baseline-err",
        ):
            size_baseline.run(
                [
                    sys.executable,
                    "-c",
                    "import sys; print('baseline-out'); "
                    "print('baseline-err', file=sys.stderr); sys.exit(7)",
                ],
            )

    def test_archive_staging_is_repeatable(self) -> None:
        with tempfile.TemporaryDirectory(prefix="moonjust-size-test-") as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            for name, contents in {
                "LICENSE": "license\n",
                "NOTICE": "notice\n",
                "README.mbt.md": "readme\n",
                "SECURITY.md": "security\n",
                "CHANGELOG.md": "change\n",
            }.items():
                (source / name).write_text(contents, encoding="utf-8")
            native = source / "just"
            native.write_bytes(b"native")
            first = root / "first.tar.gz"
            second = root / "second.tar.gz"
            repo = Path(__file__).parents[2]
            size_baseline.stage_archive(repo, source, native, "linux-x86_64", first)
            size_baseline.stage_archive(repo, source, native, "linux-x86_64", second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(size_baseline.sha256(first), size_baseline.sha256(second))

    def test_run_exposes_structured_command_failure(self) -> None:
        records: list[dict[str, object]] = []
        with self.assertRaises(size_baseline.CommandFailure) as context:
            size_baseline.run(
                [sys.executable, "-c", "import sys; print('lexscan'); sys.exit(2)"],
                records=records,
                phase="baseline-build-native",
            )
        error = context.exception
        self.assertEqual(error.returncode, 2)
        self.assertEqual(records[0]["phase"], "baseline-build-native")
        self.assertEqual(records[0]["returncode"], 2)

    def test_async_021_abi_patch_is_explicit_and_local(self) -> None:
        with tempfile.TemporaryDirectory(prefix="moonjust-abi-patch-") as temporary:
            root = Path(temporary)
            source_dir = root / "src/host_process"
            source_dir.mkdir(parents=True)
            (source_dir / "process.mbt").write_text(
                'extern "C" fn kind(fd : Int) -> Int = "moonbitlang_async_kind_of_fd"\n',
                encoding="utf-8",
            )
            c_file = source_dir / "signal_forward.c"
            c_file.write_text("#include <moonbit.h>\n", encoding="utf-8")
            patches = size_baseline.apply_toolchain_compatibility_patches(root)
            self.assertEqual([patch["id"] for patch in patches], [
                "async-021-fd-kind-symbol",
            ])
            self.assertIn("moonbitlang_async_kind_of_fd", c_file.read_text())
            self.assertEqual(size_baseline.apply_toolchain_compatibility_patches(root), [])

    def test_lexscan_failure_is_not_treated_as_infrastructure(self) -> None:
        error = RuntimeError("error: [4222] Invalid lexscan target")
        self.assertEqual(
            size_baseline.failure_classification(error, []),
            "baseline-build-failed",
        )

    def test_build_failure_has_no_comparable_assets(self) -> None:
        error = size_baseline.CommandFailure(
            ["moon", "build"], 255, "", "compiler failed"
        )
        self.assertEqual(
            size_baseline.failure_classification(
                error,
                [{"phase": "baseline-build-native", "returncode": 255}],
            ),
            "baseline-build-failed",
        )

    def test_baseline_work_path_is_stable_and_scoped(self) -> None:
        repo = Path("/workspace/moonjust")
        self.assertEqual(
            size_baseline.baseline_work_path(repo, "linux-x86_64"),
            repo / "_build/dependency-normalized-baseline/linux-x86_64",
        )
        with self.assertRaisesRegex(ValueError, "invalid baseline platform"):
            size_baseline.baseline_work_path(repo, "../../outside")


if __name__ == "__main__":
    unittest.main()
