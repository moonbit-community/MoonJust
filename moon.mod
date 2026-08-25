name = "ZSeanYves/MoonJust"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/moonbit-community/MoonJust"

license = "Apache-2.0"

keywords = [ "command-runner", "just", "task-runner", "wasm" ]

preferred_target = "wasm"

description = "A MoonBit implementation of the just command runner"

import {
  "moonbitlang/async@0.21.0",
  "moonbitlang/x@0.5.1",
  "moonbitlang/regexp@0.3.5",
}

options(
  exclude: [
    "AGENTS.md",
    "CONTRIBUTING.md",
    "compat/",
    "docs/adr/",
    "docs/reports/",
    "docs/spikes/",
    "spikes/",
    "tests/",
    "tools/",
  ],
)
