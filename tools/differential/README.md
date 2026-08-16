# Differential harness

The harness executes a pinned upstream `just` binary and a MoonJust
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

The baseline normalization replaces the isolated working directory with
`<CASE_ROOT>`. Raw artifacts are retained alongside normalized files. Adding a
normalizer requires a reviewed compatibility change.

The baseline tree snapshot records directory, regular-file hash, and symlink target.
Permissions, mtimes, process trees, signals, and TTY behavior are added in the
platform harness; the baseline snapshot must not be cited as evidence for those
surfaces.

CI runs `tools/differential/real_smoke.sh`, which builds the pinned upstream
source oracle and the current Native candidate before executing every baseline
case. Cases outside the implemented compatibility surface may remain explicit
`XDIFF` entries, but an
unexpected match, difference, timeout, exit status, or fixture-tree change
fails the run.

The ownership and reason for every current `XDIFF` are recorded in
`tests/differential/cases.toml`. A case owned by a completed compatibility area
may not be hidden there as an expected difference; it must be fixed or have a
stable product-identity or diagnostic rationale.
