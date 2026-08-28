from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).with_name("optimize_wasm.py")
SPEC = importlib.util.spec_from_file_location("optimize_wasm", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
optimize_wasm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(optimize_wasm)


class OptimizeWasmTests(unittest.TestCase):
    def test_archive_spec_normalizes_supported_architectures(self) -> None:
        linux, linux_digest = optimize_wasm.archive_spec("Linux", "AMD64")
        macos, macos_digest = optimize_wasm.archive_spec("Darwin", "aarch64")
        self.assertEqual(linux, "binaryen-version_132-x86_64-linux.tar.gz")
        self.assertEqual(macos, "binaryen-version_132-arm64-macos.tar.gz")
        self.assertEqual(len(linux_digest), 64)
        self.assertEqual(len(macos_digest), 64)

    def test_archive_spec_rejects_unpinned_platform(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "unavailable"):
            optimize_wasm.archive_spec("Plan9", "mips")

    def test_optimize_is_atomic_and_records_exact_tool(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            source = root / "input.wasm"
            output = root / "output.wasm"
            tool = root / "wasm-opt"
            source.write_bytes(b"\0asm\x01\0\0\0source")
            tool.write_bytes(b"tool")

            def run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
                if command[1:] == ["--version"]:
                    return subprocess.CompletedProcess(
                        command,
                        0,
                        stdout="wasm-opt version 132 (version_132)\n",
                        stderr="",
                    )
                destination = Path(command[command.index("-o") + 1])
                destination.write_bytes(b"\0asm\x01\0\0\0optimized")
                return subprocess.CompletedProcess(command, 0)

            with mock.patch.object(optimize_wasm.subprocess, "run", side_effect=run) as invoked:
                metadata = optimize_wasm.optimize(
                    source,
                    output,
                    cache=root / "cache",
                    wasm_opt=tool,
                )

            self.assertEqual(output.read_bytes(), b"\0asm\x01\0\0\0optimized")
            self.assertEqual(metadata["optimizer_version"], "wasm-opt version 132 (version_132)")
            self.assertEqual(metadata["optimizer_sha256"], optimize_wasm.sha256(tool))
            command = invoked.call_args_list[-1].args[0]
            self.assertIn("-O2", command)
            self.assertIn("--enable-multivalue", command)
            recorded = json.loads(
                optimize_wasm.optimizer_metadata_path(output).read_text(encoding="utf-8")
            )
            self.assertEqual(recorded["output_sha256"], optimize_wasm.sha256(output))
            self.assertEqual(output.stat().st_mode & 0o777, source.stat().st_mode & 0o777)

    def test_metadata_reader_rejects_a_changed_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            artifact = Path(raw) / "candidate.wasm"
            artifact.write_bytes(b"\0asm\x01\0\0\0")
            optimize_wasm.optimizer_metadata_path(artifact).write_text(
                json.dumps(
                    {
                        "optimizer_version": "wasm-opt version 132 (version_132)",
                        "arguments": list(optimize_wasm.OPTIMIZER_ARGUMENTS),
                        "output_sha256": optimize_wasm.sha256(artifact),
                    }
                ),
                encoding="utf-8",
            )
            optimize_wasm.read_optimizer_metadata(artifact)
            artifact.write_bytes(b"changed")
            with self.assertRaisesRegex(RuntimeError, "output hash differs"):
                optimize_wasm.read_optimizer_metadata(artifact)

    def test_optimizer_version_must_match_pin(self) -> None:
        completed = subprocess.CompletedProcess(
            ["wasm-opt", "--version"],
            0,
            stdout="wasm-opt version 131 (version_131)\n",
            stderr="",
        )
        with mock.patch.object(optimize_wasm.subprocess, "run", return_value=completed):
            with self.assertRaisesRegex(RuntimeError, "unexpected wasm-opt version"):
                optimize_wasm.verify_optimizer(Path("wasm-opt"))


if __name__ == "__main__":
    unittest.main()
