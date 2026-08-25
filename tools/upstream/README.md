# Upstream snapshot tools

`generate_snapshot.py` verifies the pinned `just 1.57.0` commit, compiles its
test targets, and generates the sorted registration list used by the
compatibility mapping.

Use an existing checkout:

```bash
python3 tools/upstream/generate_snapshot.py /path/to/just-1.57.0
```

Or let the script create and clean a temporary clone:

```bash
python3 tools/upstream/generate_snapshot.py
```

The command fails rather than updating the snapshot if the commit or expected
2,417 registrations differ. Review and update the baseline through a dedicated
compatibility PR; do not change the expected count to make CI green.

`test_map.py` generates one deterministic JSONL row for every pinned
registration using schema version 4. Differential rows name a case executed against
the official, native and wasm binaries. Contract rows carry a stable contract
case ID plus an executable `suite`/`test_name` anchor, and each generated area
case explicitly lists its upstream registration. The verifier reads the
referenced MoonBit source and checks that the named declaration exists.
Completion and maintenance rows remain explicit and are never counted as
compatibility passes. Contract anchors must be unique, independently runnable
MoonBit tests; a broad test name cannot stand in for multiple upstream cases.

Regenerate and verify the map with:

```bash
python3 tools/upstream/test_map.py --write
python3 tools/upstream/test_map.py
```

The real oracle is built from the same pinned source with:

```bash
python3 tools/upstream/build_oracle.py
```

The builder verifies the annotated tag's peeled commit, `Cargo.lock` digest,
release version, and emits the resulting binary digest. It never accepts a
downloaded or prebuilt `just` executable as compatibility evidence.

Run the strict official integration differential with:

```bash
python3 tools/upstream/run_official_harness.py
```

The default command writes a machine-readable candidate report below
`_build/upstream-harness/` and fails on every unapproved difference. Results
are classified as `exact`, `diagnostic-exact`, `diagnostic-semantic`,
`product-identity`, `excluded-completion`, `upstream-ignored`,
`not-applicable`, or `failed`.
Exceptions are exact test IDs in
`tests/upstream/just-1.57.0/compatibility-exceptions.toml`; wildcards are not
accepted.

Replacing the committed oracle is deliberately verbose and is allowed only
after every strict gate passes. The command prints the complete unified diff
before writing:

```bash
python3 tools/upstream/run_official_harness.py \
  --audit-write \
  --approve-audit-write e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f
```
