# Upstream snapshot tools

`generate_snapshot.sh` verifies the pinned `just 1.57.0` commit, compiles its
test targets, and generates the sorted registration list used by the
compatibility mapping.

Use an existing checkout:

```bash
./tools/upstream/generate_snapshot.sh /path/to/just-1.57.0
```

Or let the script create and clean a temporary clone:

```bash
./tools/upstream/generate_snapshot.sh
```

The command fails rather than updating the snapshot if the commit or expected
2,417 registrations differ. Review and update the baseline through a dedicated
compatibility PR; do not change the expected count to make CI green.

`test_map.py` generates one deterministic JSONL row for every pinned
registration. Phase 3-5 rows are `covered-by` and carry an executable
`suite`/`test_name` anchor. The verifier reads the referenced MoonBit source and
checks that the named test declaration exists. Later phase rows remain
`planned`; both planned and excluded rows retain explicit tracking owners.

Regenerate and verify the map with:

```bash
python3 tools/upstream/test_map.py --write
python3 tools/upstream/test_map.py
```

The real oracle is built from the same pinned source with:

```bash
./tools/upstream/build_oracle.sh
```

The builder verifies the annotated tag's peeled commit, `Cargo.lock` digest,
release version, and emits the resulting binary digest. It never accepts a
downloaded or prebuilt `just` executable as compatibility evidence.
