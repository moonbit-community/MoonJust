from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("signal_policy.py")
SPEC = importlib.util.spec_from_file_location("moonjust_signal_policy", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)


def record(scenario: str, *, reader_eof: bool = True) -> dict[str, object]:
    return {
        "schema_version": 1,
        "policy": "async-only",
        "scenario": scenario,
        "direct_child_wait_status": {"reaped": True, "mapped_exit_status": 0},
        "timed_out": not reader_eof,
        "reader_eof": reader_eof,
        "pipe_holders": [] if reader_eof else [{"pid": 2, "fd": 1}],
    }


class SignalPolicyTest(unittest.TestCase):
    def test_direct_child_matrix_accepts_shared_pipe_observation(self) -> None:
        policy.validate(
            [
                record("normal"),
                record("direct-signal"),
                record("cancellation"),
                record("background", reader_eof=False),
                record("detached", reader_eof=False),
            ]
        )

    def test_direct_child_matrix_rejects_unreaped_child(self) -> None:
        rows = [record(scenario) for scenario in policy.SCENARIOS]
        rows[0]["direct_child_wait_status"] = {"reaped": False}
        with self.assertRaises(RuntimeError):
            policy.validate(rows)


if __name__ == "__main__":
    unittest.main()
