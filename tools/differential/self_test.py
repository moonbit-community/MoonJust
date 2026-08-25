#!/usr/bin/env python3
"""Validate the differential harness's self-test contract portably."""

from __future__ import annotations

import tempfile
import subprocess
import sys
from pathlib import Path


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="moonjust-diff-self-test-") as raw:
        root = Path(raw)
        cases = root / "cases.toml"
        cases.write_text(
            "schema_version = 3\nupstream = 'self-test'\n\n"
            "[[case]]\nid = 'MJ-COMPAT-SELF-MATCH'\n"
            "directory = '01-match'\nowner_area = 'differential-harness'\n"
            "status = 'match'\ncompare = ['status', 'stdout', 'stderr', 'tree']\nupstream_tests = []\n",
            encoding="utf-8",
        )
        cases.write_text(
            cases.read_text(encoding="utf-8")
            + "\n[[case]]\nid = 'MJ-COMPAT-SELF-DIFF'\n"
            + "directory = '02-diff'\nowner_area = 'differential-harness'\n"
            + "status = 'expected-difference'\ncompare = ['status', 'stdout', 'stderr', 'tree']\n"
            + "upstream_tests = []\nallowed_difference = 'product-identity'\n",
            encoding="utf-8",
        )
        (root / "cases/01-match").mkdir(parents=True)
        (root / "cases/02-diff").mkdir(parents=True)
        for case in ("01-match", "02-diff"):
            (root / "cases" / case / "argv.txt").write_text(
                "--different\n" if case == "02-diff" else "", encoding="utf-8"
            )
            (root / "cases" / case / "stdin").write_text("", encoding="utf-8")
            (root / "cases" / case / "env.list").write_text("", encoding="utf-8")
            (root / "cases" / case / "expectation").write_text(
                "difference\n" if case == "02-diff" else "match\n", encoding="utf-8"
            )
            (root / "cases" / case / "compat-id").write_text(
                f"MJ-COMPAT-SELF-{'DIFF' if case == '02-diff' else 'MATCH'}\n", encoding="utf-8"
            )
        upstream = root / "upstream.py"
        candidate = root / "candidate.py"
        body = "#!/usr/bin/env python3\nimport sys\nprint('candidate' if sys.argv[1:] == ['--different'] else 'same')\n"
        upstream.write_text(body.replace("candidate", "upstream"), encoding="utf-8")
        candidate.write_text(body, encoding="utf-8")
        command = [
            sys.executable,
            str(Path(__file__).with_name("run.py")),
            "--upstream", sys.executable,
            "--upstream-script", str(upstream),
            "--candidate", sys.executable,
            "--candidate-script", str(candidate),
            "--manifest", str(cases),
            "--cases", str(root / "cases"),
            "--artifacts", str(root / "artifacts"),
        ]
        result = subprocess.run(command, check=False, text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
    print("differential self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
