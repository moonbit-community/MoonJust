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
