#!/usr/bin/env python3
import argparse
import contextlib
import functools
import http.server
import os
import pathlib
import shutil
import subprocess
import tempfile
import threading


def run_moonx(
    registry: pathlib.Path,
    coordinate: str,
    policy: pathlib.Path,
    expect_success: bool,
) -> subprocess.CompletedProcess[str]:
    handler = functools.partial(
        http.server.SimpleHTTPRequestHandler,
        directory=str(registry),
    )
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        with tempfile.TemporaryDirectory(prefix="moonjust-moonx-home-") as moon_home:
            environment = os.environ.copy()
            environment["MOON_HOME"] = moon_home
            environment["MOONCAKES_REGISTRY"] = (
                f"http://127.0.0.1:{server.server_address[1]}"
            )
            result = subprocess.run(
                [
                    "moonx",
                    "--experimental-policy",
                    str(policy),
                    coordinate,
                    "--version",
                ],
                text=True,
                capture_output=True,
                env=environment,
                timeout=60,
            )
        server.shutdown()
        thread.join(timeout=5)
    if (result.returncode == 0) != expect_success:
        raise SystemExit(
            "Phase 11 MoonX staging error:\n"
            f"status={result.returncode}\nstdout={result.stdout}\nstderr={result.stderr}"
        )
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--registry", type=pathlib.Path, required=True)
    parser.add_argument("--coordinate", required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    registry = args.registry.resolve()
    policy = repo / "policies" / "deny.toml"

    success = run_moonx(registry, args.coordinate, policy, True)
    if not success.stdout.startswith("moonjust "):
        raise SystemExit("Phase 11 MoonX staging error: version output differs")

    with tempfile.TemporaryDirectory(prefix="moonjust-bad-registry-") as raw:
        bad_registry = pathlib.Path(raw)
        shutil.copytree(registry / "assets", bad_registry / "assets")
        sidecars = list((bad_registry / "assets").rglob("*.sha256"))
        if len(sidecars) != 1:
            raise SystemExit("Phase 11 MoonX staging error: expected one checksum sidecar")
        sidecars[0].write_text("0" * 64 + "  just.wasm\n")
        failure = run_moonx(bad_registry, args.coordinate, policy, False)
        if "checksum mismatch" not in failure.stderr:
            raise SystemExit(
                "Phase 11 MoonX staging error: corrupt checksum did not report mismatch"
            )

    print("Phase 11 MoonX staging verified: cold download, checksum, execution, corruption rejection")


if __name__ == "__main__":
    main()
