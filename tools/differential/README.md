# Differential harness v0

The Phase 0 harness executes a pinned upstream `just` binary and a MoonJust
binary in separate copies of the same fixture. It captures raw and normalized
stdout/stderr, exit status, and the resulting filesystem tree.

Run the harness self-test on every platform with a POSIX shell:

```bash
./tools/differential/self_test.sh
```

Run the ten baseline cases against real binaries:

```bash
moon build --target native cmd/just
./tools/differential/run.sh \
  --upstream /path/to/just-1.57.0/target/debug/just \
  --candidate _build/native/debug/build/cmd/just/just.exe
```

Each case contains:

- `argv.txt`: one argument per line; an empty file means no arguments.
- `stdin`: bytes sent to stdin.
- `env.list`: one non-secret `NAME=value` assignment per line.
- `tree/`: initial working tree.
- `expectation`: either `match` or `difference`.
- `compat-id`: required when a difference is expected.

The only v0 normalization replaces the isolated working directory with
`<CASE_ROOT>`. Raw artifacts are retained alongside normalized files. Adding a
normalizer requires a reviewed compatibility change.

The v0 tree snapshot records directory, regular-file hash, and symlink target.
Permissions, mtimes, process trees, signals, and TTY behavior are added in the
later platform harness; v0 must not be cited as evidence for those surfaces.
