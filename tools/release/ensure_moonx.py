#!/usr/bin/env python3
"""Ensure that the MoonX command resolves to the installed Moon executable."""

from __future__ import annotations

import os
import shutil
from pathlib import Path


def main() -> int:
    existing = shutil.which("moonx")
    if existing:
        print(shutil.which("moonx"))
        return 0
    moon = shutil.which("moon")
    if moon is None:
        raise SystemExit("Release CI setup failed: moon is not installed")
    source = Path(moon)
    destination = source.with_name("moonx.exe" if os.name == "nt" else "moonx")
    if destination.exists() or destination.is_symlink():
        destination.unlink()
    if os.name == "nt":
        shutil.copy2(source, destination)
    else:
        destination.symlink_to(source)
    print(shutil.which("moonx") or destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
