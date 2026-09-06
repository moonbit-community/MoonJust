# MoonX published-artifact gate

This document describes the release-only test that starts a published
MoonJust module through MoonX. It is separate from the ordinary source,
Native, local Wasm, and `moonrun` compatibility checks.

The test implementation is pure MoonBit. The executable is
`tests/moonx`, and it starts external programs through the MoonBit process API.
It does not construct shell command strings and does not use Python, Shell,
Rust, or C test helpers.

## Correct MoonX argument form

Pass MoonJust's arguments directly after the exact MoonCake coordinate:

```bash
moonx --target wasm ZSeanYves/MoonJust@0.1.2 --version
moonx --target wasm ZSeanYves/MoonJust@0.1.2 --summary
moonx --target wasm ZSeanYves/MoonJust@0.1.2 --list
moonx --target wasm ZSeanYves/MoonJust@0.1.2 build
```

Do not insert a standalone `--` between the coordinate and MoonJust's
arguments. The `--` in the outer `moon run ... --` command below belongs to
MoonBit's executable argument boundary, not to MoonX.

The `--` visible in verbose `moonrun <artifact> -- <args>` output belongs to
Moonrun's own argument boundary. It is not needed in the user-facing MoonX
command.

## Local smoke test

The current published version can be checked with:

```bash
moon run --target native ./tests/moonx -- \
  --candidate ZSeanYves/MoonJust@0.1.2 \
  --target wasm \
  --suite smoke \
  --report _build/moonx-smoke-report.json
```

Expected result:

```text
PASS version identity match
PASS help compatible option surface
PASS default-recipe match
PASS summary match
PASS list match
PASS show match
PASS execute match
PASS recipe-failure expected failure
PASS recipe-parameters match
PASS forwarded-dash-arguments match
PASS dry-run match
PASS fmt-check-unformatted expected failure
PASS fmt-check-formatted match
PASS quiet silent match
PASS no-deps match
PASS working-directory-relative-path match
PASS parallel match
PASS dotenv match
PASS no-dotenv expected failure
PASS cache first/hit/no-cache/clean match
```

The `no-dotenv` case is expected to fail inside the justfile because the
fixture references an unset variable. The expected result of the case is the
same non-zero status and stderr as official `just`; the test command itself
still passes.

## Test coverage

The smoke suite compares the published MoonX candidate with official
`just 1.57.0` where behavior is expected to match. It also checks MoonJust's
product identity independently. Each execution captures status, stdout,
stderr, and a normalized filesystem tree in an isolated temporary directory.

The suite covers:

- version and help identity;
- summary, list, recipe execution, dry-run, and quiet output;
- dependency suppression;
- working-directory resolution, relative paths, and parallel execution;
- dotenv and `--no-dotenv` behavior;
- cache first-run, cache hit, `--no-cache`, and `--clean` behavior;
- exact stdout/stderr separation and exit status.

The full suite additionally reuses the existing strict compatibility corpus:

```bash
moon run --target native ./tests/moonx -- \
  --candidate ZSeanYves/MoonJust@0.1.3-rc.1 \
  --target wasm \
  --suite full \
  --report _build/moonx-release-report.json
```

The full mode passes `moonx --target wasm <coordinate>` as the candidate
command to the existing MoonBit compatibility runner. The corpus is split
into eight stable MoonBit shards and the results are joined only after every
shard completes. It does not duplicate the expected files under
`tests/differential/cases`.

## Expected results for common commands

| Command | Expected result |
| --- | --- |
| `--fmt --check` on an unformatted file | Non-zero status and formatting diff |
| `--fmt --check` on a formatted file | Status 0 and no diff |
| `--quiet` | Suppressed command echo; an empty output can be correct |
| `--no-dotenv` with a required variable | Non-zero status and undefined-variable diagnostic |
| `--dry-run` | Exact stdout/stderr comparison; stderr is not duplicated |
| `--no-deps` | Only the requested recipe's effects; a fresh temp directory is required |
| cache first run | Recipe executes and cache is written |
| cache second run | Official and candidate both report a cache hit |
| cache with `--no-cache` | Recipe executes without using the stored entry |
| cache `--clean` | Cache entries are removed successfully |

## Release-candidate flow

The next candidate uses a pre-release version such as
`0.1.3-rc.1`. The version is read from `moon.mod`; the test tool rejects a
coordinate that does not exactly match the module name and version.

The release sequence is:

```text
ordinary MoonBit CI
    -> publish 0.1.3-rc.1 with moon publish --frozen
    -> wait for the MoonCake Wasm asset
    -> run the MoonX full suite
    -> pass the required PR check
    -> merge main
    -> publish 0.1.3 from the merged main head
    -> run the same smoke suite against 0.1.3
```

The MoonCake publication step is protected and manual. The repository does
not publish from untrusted pull-request code.

The required check is named `MoonX published artifact`. Ordinary pull requests
report `not-applicable` without invoking MoonX. Release-candidate pull
requests run the real test. If a MoonCake asset is still being built, the
MoonBit runner performs bounded retries and reports asset readiness separately
from a functional failure.

When `MOON_HOME` is supplied by the caller, the runner reuses it and leaves it
in place. Without it, full mode owns a temporary shared cache and removes only
that temporary directory after the run.

Native compiler warnings are outside this gate. Native functional checks may
still run, but external Native warning output is not treated as a test failure.
