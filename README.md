# MoonJust

[![CI](https://github.com/moonbit-community/MoonJust/actions/workflows/ci.yml/badge.svg)](https://github.com/moonbit-community/MoonJust/actions/workflows/ci.yml)

MoonJust is a pure MoonBit implementation of the user-visible behavior of
[just](https://github.com/casey/just). It is a binary-only project for Native
and linear-memory Wasm targets, with compatibility pinned to official
just 1.57.0.

The current product version is 0.1.2. It has no library
facade: the root package is the executable and everything below internal/ is an
implementation detail.

## Highlights

- Parses, formats, checks, queries, and executes justfiles.
- Supports imports, modules, dotenv, recipe parameters, dependencies,
  line/script recipes, backticks, builtins, working-directory rules, bounded
  jobs, captured/live output, and persistent recipe caching.
- Runs on Linux, macOS, and Windows Native targets and under a capable MoonBit
  Wasm host.
- Keeps filesystem, environment, terminal, clock, cache, and process effects
  behind explicit Host capabilities.
- Uses pure MoonBit package tests and black-box differential runners; no Python,
  Rust, shell, or C helper implements MoonJust behavior or verification.
- Preserves measured startup, Wasm host-call, dry-run planner, and Windows path
  optimizations through the current architecture.

## Quick Start

Install the latest matching MoonBit toolchain, then run from the repository:

~~~bash
moon update
moon run --target native . -- --version
moon run --target native . -- --help
~~~

Create a justfile:

~~~make
default: build

build profile="debug":
  echo "building {{profile}}"

test: build "release"
  echo "testing"
~~~

Then invoke a recipe through MoonJust:

~~~bash
moon run --target native . -- build release
moon run --target native . -- --list
moon run --target native . -- --dry-run test
~~~

For repeated use, build a release executable:

~~~bash
moon build --release --target native .
_build/native/release/build/MoonJust.exe --version
~~~

When using MoonX, write MoonX's separator once before MoonJust's arguments:

~~~bash
moonx ZSeanYves/MoonJust@0.1.2 -- build
moonx ZSeanYves/MoonJust@0.1.2 -- --version
~~~

The recipe name is passed directly; it does not need another `--`.

The Wasm artifact is built with:

~~~bash
moon build --release --target wasm .
~~~

and is written to _build/wasm/release/build/MoonJust.wasm. Wasm execution
depends on the filesystem, environment, and process capabilities granted by the
chosen MoonBit host. Building as Wasm does not sandbox child processes.

## Supported Behavior

| Area | Current implementation |
| --- | --- |
| Language | UTF-8 byte spans, lexer, parser, attributes, expressions, recipes, formatter, Markdown extraction |
| Project loading | justfile discovery, explicit/stdin input, imports, optional imports, modules, canonical graph identity |
| Evaluation | lazy variables, recipe arguments, settings, 83 builtins, host-gated effects, SemVer, regexp, hashing |
| Queries | check, format, init, list, show, summary, usage, groups, variables, evaluate, dump, JSON inspection |
| Execution | dependencies, bounded jobs, line/script recipes, dry-run, captured/live output, cancellation, cache |
| Environment | dotenv discovery and commands, overrides, shell/tempdir, child environment, project/recipe directories |
| Platforms | Linux, macOS, Windows Native; linear-memory Wasm through MoonBit host adapters |

A justfile is executable code. Review untrusted files and use an operating-system
or container sandbox when isolation is required; see SECURITY.md.

## Compatibility

The oracle is official just 1.57.0 at upstream commit
e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f.

The maintained black-box corpus contains 1,417 executable scenarios. Across
the platform-complete corpus, 1,411 are byte-exact matches and six are
explicit known differences:

- --version and --help retain MoonJust product identity;
- one unstable-function error has MoonJust diagnostic presentation;
- three invalid dotenv option combinations are rejected at the same semantic
  boundary with different diagnostic presentation.

Known differences name the affected output field and pin candidate bytes by
SHA-256. A changed diagnostic therefore fails instead of being accepted by a
broad substring rule. Shell completion is not part of the current compatibility
claim, and raw signal behavior remains limited to the direct-child lifecycle
described by the historical ADRs.

The pinned upstream inventory contains 2,417 test identities. The strict
report has 2,362 executed identities (2,358 exact and four pinned known
differences), 34 completion exclusions, 21 runtime signal exclusions, and zero
unclassified identities. CI invokes the same `--strict-coverage` check. A Unix
run reports 1,410 exact black-box matches because the one Windows-only case is
skipped there; the case is executed on the Windows job. This platform skip does
not change the 2,417-row strict inventory.

Recorded official snapshots are supplementary audit material. Two datetime
fixtures contain date-sensitive output and must be regenerated or normalized
when the calendar changes; the live official 1.57.0 process remains the
authoritative comparison. The optional `--verify-snapshots` flag is therefore
not a substitute for the live differential run.

## Architecture

MoonJust follows one forward-only execution chain:

~~~text
main
  -> application.classify_request
  -> application.prepare_project
  -> project.load_snapshot
  -> query | planner
  -> runtime.execute_plan
  -> application.render_response
  -> main.write_and_exit
~~~

Project loading cannot start a process, query cannot mutate the project,
planning cannot execute commands, and runtime cannot reload or reparse a
justfile. Native/Wasm differences are selected at the root or Host leaves.

The complete package map and invariants are in docs/ARCHITECTURE.md.

## Repository Map

| Path | Responsibility |
| --- | --- |
| main.mbt, runtime_*.mbt | Root executable, target selection, final output and exit |
| internal/application | Request routing, project preparation, orchestration, response/error mapping |
| internal/project | Immutable project input, loaded graph, compilation, working-directory facts |
| internal/query | Read-only query models, deterministic ordering, rendering support |
| internal/planner | Dependency traversal, recipe expansion, dry-run and execution-plan construction |
| internal/runtime | Coordination, process lifecycle, output, cancellation and cache execution |
| internal/host | Capability contracts plus fs, native, process, wasm, and testkit adapters |
| internal/lexer through internal/evaluator | Language front end, semantic model, values and builtins |
| tests | MoonBit behavior, compatibility, platform and paired benchmark runners |
| docs/development | Historical ADRs and delivery reports |
| docs/maintenance | Current maintenance work records |

## Development and Verification

Use the latest MoonBit toolchain, matching CI:

~~~bash
moon update
moon check --target native
moon check --target wasm
moon test --target native
moon test --target wasm
moon info && moon fmt
moon publish --dry-run
~~~

To compare a release build with official just, install exactly just 1.57.0,
then run the MoonBit tools:

~~~bash
cargo install just --version 1.57.0 --locked
moon build --release --target native .
moon build --release --target native ./tests/benchmark

moon run --target native ./tests/compat -- \
  --candidate _build/native/release/build/MoonJust.exe \
  --official just \
  --verify-snapshots --strict-coverage \
  --coverage-report _build/coverage.json

moon run --target native ./tests/platform -- \
  --candidate _build/native/release/build/MoonJust.exe \
  --official just

_build/native/release/build/tests/benchmark/benchmark.exe \
  --candidate _build/native/release/build/MoonJust.exe \
  --official just \
  --target native \
  --profile full --enforce \
  --output _build/performance-gate-native.json

_build/native/release/build/tests/benchmark/benchmark.exe \
  --candidate _build/wasm/release/build/MoonJust.wasm \
  --candidate-runner moonrun \
  --official just \
  --target wasm \
  --profile full --enforce \
  --output _build/performance-gate-wasm.json
~~~

The compatibility runner compares only declared observable behavior: exit
status, stdout, stderr, merged output, filesystem effects, and live-output
observations. The benchmark first verifies behavior equivalence, then executes
interleaved paired processes and reports median/p95 ratios, batch ratios, raw
samples, fixture setup, and calibration data in schema 2 JSON. `smoke` uses one
batch of five pairs for pull requests; `full` uses three batches of fifteen
pairs and is run by the scheduled/manual performance workflow with `--enforce`.
The benchmark runner itself is built once and invoked directly, while each
candidate and official sample remains a real independent CLI process. The
`run-noops` workload is calibrated per runner to an official duration between
32ms and 500ms; failure to find a valid scale is reported instead of skipped.

## Documentation

- docs/ARCHITECTURE.md: current package ownership and execution invariants.
- docs/maintenance/REFACTOR_REPORT.md: performance recovery, logic rewrite,
  compatibility, and validation record.
- docs/development/: historical ADRs, phase reports, and release-era evidence.
- CHANGELOG.md: version and user-visible change history.
- CONTRIBUTING.md: contribution and verification workflow.

## License

MoonJust is licensed under Apache-2.0. Pinned upstream test names and fixtures
retain their provenance in tests/compatibility/upstream/NOTICE.md.
MoonJust is independent of and not endorsed by the upstream just project.
