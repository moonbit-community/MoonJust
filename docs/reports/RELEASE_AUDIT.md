# Release readiness audit

## Current Phase 12 entry

This is the current audit entry for the `main` branch after the Phase 12
source-layout and release-identity closeout. The complete functional and
platform conclusion is consolidated in [`PHASE_12_REPORT.md`](PHASE_12_REPORT.md).

- Upstream: `just 1.57.0`, commit
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Module: `ZSeanYves/MoonJust`, Moon metadata `0.1.0`, product/tag `v0.1.0`
- Stable facade: `ZSeanYves/MoonJust/api`
- Repository URL: `https://github.com/moonbit-community/MoonJust`
- Layout: implementation packages under `src/*`; no repository `internal/*`
- Main pre-close baseline: `6ac1e27ee288957fa9ec956d6847d60e56d8ba09`
- Final main head: the commit containing this audit entry; its full SHA must be
  taken from the post-push exact-head CI/RC evidence
- Completion: excluded by scope
- Accepted MoonX limitation: two Linux invalid UTF-8 cwd rows are
  `not-applicable`
- Accepted process/signal limitation: `signals::forwarding` remains an explicit
  Native direct-child limitation under ADR-0019, and ADR-0020 records the
  approved async-only differences for signal identity, TERM forwarding,
  first-signal ordering, SIGINFO, and signal-specific diagnostics
- Current CI policy: merged Native/Wasm production coverage gates only overall
  coverage at 80%; changed-line, area and frozen package baselines are report
  fields, not failure conditions. Main and release workflows run report-only
  benchmarks on all three supported platforms and gate execution, sample
  completeness and provenance, without authoritative timing thresholds.
- CI orchestration uses Python 3.11 with native Windows path and artifact
  handling. The former host-async lifecycle harness remains isolated as
  historical Unix-only evidence and is not a current release gate.
- Non-host-async Shell helpers, Git Bash fallbacks, and old release wrappers
  have been removed. The active verification surface is `tools/runner.py` and
  dedicated Python tools; the host-async observation harness remains isolated
  historical evidence.
- Coverage merges Native/Wasm raw reports in the evidence aggregation job and
  gates only overall coverage at 80%. Three-platform benchmarks are report-only
  and validate execution, complete samples, and provenance without a timing
  threshold.

## C cleanup closure

The Phase 12 native-host C cleanup removed the project-owned `platform.c`,
`realpath.c`, and `transaction.c`; ADR-0020 removed the final production
signal stub. The production project C inventory is now empty. The two explicitly
isolated `spikes/host-async` probes remain outside production. Third-party
`.mooncakes` sources and generated `_build` files are excluded from this
inventory.

The replacement keeps canonical path resolution, range reads, exclusive
temporary creation, full synchronization, atomic overwrite/no-overwrite,
permission inheritance, read-only rejection, executable handling, cleanup,
Windows wide-character paths, and the documented non-UTF-8 cwd classification.
`api/pkg.generated.mbti` has no declaration or byte changes. The remaining
MoonBit `extern "C"` declarations reference system ABI or approved dependency
backends; no project C shim or new dependency was added.

Local second-pass evidence: host-native 9/9, Native 1110/1110, Wasm 1097/1097,
all-target check with warnings denied, naming and architecture checks, and the
pinned 2,417-registration snapshot/differential smoke all passed. Exact-head
three-platform artifacts, ASan/UBSan and RC release evidence remain CI-owned
gates and must be attached to the final main SHA. The macOS-only full upstream
harness retains the pre-existing `dotenv::fifo` environment-source limitation;
signal cases are recorded as async-only policy evidence, while
`signals::forwarding` remains the ADR-0019 direct-child exception, and Linux CI remains authoritative
for the FIFO case. The current CI workflow no longer treats Linux timing or
authoritative performance as a release gate.

The active gate requires ordinary commits on `main`, exact-head CI/RC evidence,
unchanged stable `.mbti` declarations, all-target tests, architecture and
naming checks, Python-only helper audit, and a clean stale-path/duplicate-artifact audit. The historical
Phase 0-11 evidence below is retained as an immutable index; it is not a
replacement for the current exact-head evidence.

- Review period: 2026-08-04 through 2026-08-13
- Historical scope: Phase 0 through Phase 11
- Audit-closure baseline: `ec960b5a1cdf8bce63fcaae79f63b4f9947490f3`
- Audit-closure protected-main CI:
  [31697473589](https://github.com/moonbit-community/MoonJust/actions/runs/31697473589)
- Successful candidate workflow:
  [31698189163](https://github.com/moonbit-community/MoonJust/actions/runs/31698189163)
- Accepted specification: [`PROJECT_PLAN.md`](../PROJECT_PLAN.md)
- Upstream baseline: `just 1.57.0` at
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- MoonJust candidate identity: `v0.1.0`
- Required targets: Native and wasm1 through `moonrun`/`moonx`; Native smoke on Ubuntu, macOS and Windows

## Audit rule

This is an implementation and evidence audit, not a prose-only status review.
A delivery milestone passes only when its declared contracts have executable positive and
negative tests, target-appropriate capability boundaries, pinned upstream
provenance where applicable, deterministic machine-readable metadata, and
successful protected-main CI. Historical phase reports retain their original
scope and test snapshots; this document likewise records only the audit-closure
verdict below.

## Historical verdict

All Phase 0-11 delivery milestones are complete under their merged evidence.
The final protected-main CI and manually dispatched candidate workflow passed
every supported source-package, Native-artifact and wasm1-asset job. Review and
clean-runner findings were closed before audit exit. No formal publication,
tag or GitHub Release was performed.

The table below is the consolidated historical delivery index. Phase labels
remain here as evidence coordinates; current product and validation surfaces
use capability-oriented names.

| Phase | Scope | Implementation | Exit | Evidence |
| --- | --- | --- | --- | --- |
| 0 | governance, baseline, architecture, CI, dependency spikes | complete | passed | pinned source, 2,417-row inventory, differential harness, Native/wasm1 spikes |
| 1 | Source/Span, diagnostics, paths, Host contracts, application errors | complete | passed | five contracts, deterministic FakeHost, all-target checks |
| 2 | target-independent lexer and hardening | complete | passed | 93 registrations, 21 oracle cases, 100,000-input budget |
| 3 | parser, AST, formatter and Markdown tangle | complete | passed | 324 mapped registrations, AST equivalence, formatter and fence hardening |
| 4 | semantic compilation, loader and import/module graph | complete | passed | 427 mapped registrations, real HostFs, canonical graph and static validation |
| 5 | values, evaluator, builtins, effects and hashing | complete | passed | 406 mapped registrations, typed 83-builtin registry, Rust oracle, ASan |
| 6 | query CLI and read-only Wasm inspection | complete | passed | 86 covered registrations, 134/133 target tests, 24-case query oracle |
| 7 | HostFs transactions, dotenv, invocation, cwd and environment composition | complete | passed | 188 covered registrations, 211/208 target tests, five dedicated gates |
| 8 | sequential executor preview, process adapters, scripts, effects, output and cancellation | complete | passed | PR-080..087, 236/232 target tests, executor gate, security audit, protected-main CI |
| 9 | bounded concurrency, persistent cache, atomic store, cleanup and determinism | complete | passed | PR-090..094, 72 covered plus 2 registered differences, 1,000-DAG stress, crash/two-process gates, protected-main CI |
| 10 | platform behavior, interactive commands, Markdown and compatibility convergence | complete | passed | complete 2,417-row classification, platform matrix, tangle oracle and protected-main CI |
| 11 | package, policy, artifact, supply-chain and upgrade engineering | complete | passed | cold rebuild, repeatability, three Native candidates, wasm1 asset, tamper matrix and attestation workflow |

The former audit classified no applicable Tier A registration as unsupported or
unverified. That classification is retired and must not be used as a current
compatibility claim: schema v4 requires each registration to have independent
executable evidence and currently blocks release on 568 unverified rows.

## Historical audit-closure matrix

| Evidence | Result |
| --- | --- |
| Native tests at audit closure | 303 passed, 0 failed |
| wasm1 tests at audit closure | 298 passed, 0 failed |
| All stable backend checks | pass |
| Upstream registration classification | 2,417 classified; 0 planned |
| Source-package cold rebuild | pass with exact copied dependencies and caches disabled |
| Reproducibility | two clean fixed-path Native/wasm builds byte-identical |
| Wasm policies | explicit deny, default deny, inspect, controlled CI and full execute pass |
| Candidate archives | exact members, external/embedded checksums and extracted corpus pass |
| Supply chain | Native and wasm1 CycloneDX/SLSA documents pass exact local verification |
| Negative matrix | 12 tamper classes rejected |
| Upgrade and rollback | previous-candidate corpus parity and exact-byte rollback pass |
| Supported candidate workflow | run 31698189163 passed source validation, three Native artifacts, wasm1 asset and OIDC attestations |

## Phase 0-9 compatibility snapshot

The pinned `tests/upstream/just-1.57.0/test-list.txt` contains 2,417 unique
registrations. `tools/upstream/test_map.py` and
`tools/upstream/verify_manifest.py` validate row identity, semantic owner area,
disposition, target matrix, evidence paths, executable test declarations, and
deterministic case manifests. The historical table below groups those rows by
their delivery phase for comparison with the original audit snapshot.

| Owner phase | Registrations | Covered | Unsupported | Excluded / not applicable | Planned for later |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | 93 | 92 | 0 | 1 | 0 |
| 3 | 324 | 324 | 0 | 0 | 0 |
| 4 | 427 | 427 | 0 | 0 | 0 |
| 5 | 406 | 406 | 0 | 0 | 0 |
| 6 | 121 | 86 | 0 | 35 | 0 |
| 7 | 188 | 188 | 0 | 0 | 0 |
| 8 | 732 | 0 | 0 | 0 | 732 |
| 9 | 74 | 72 | 2 | 0 | 0 |
| 10 | 52 | 0 | 0 | 0 | 52 |
| **Total** | **2,417** | **1,595** | **2** | **36** | **784** |

The 36 exclusions are one Rust-private lexer helper, 30 shell-completion
registrations, and five product-maintenance registrations. The two unsupported
Phase 9 rows are the documented cache storage-tree differences. The 784 later
rows are not silently counted as compatibility: they require the remaining
full executor, interactive, or release-tooling behavior owned by later phases.

Phase 7's 188 executable rows are grouped by deterministic family anchors:
51 dotenv, 86 invocation, 30 working-directory, and 21 CLI environment rows.
Repeated anchors are explicitly family evidence; they are not claimed as 188
independent one-to-one ports.

Phase 8's sequential executor preview is verified by its dedicated contract
matrix and fixtures rather than by claiming the 732 still-planned upstream
registrations. Those rows remain explicit compatibility work and are not
silently counted as covered by the preview.

Phase 9's 72 covered rows use deterministic family anchors for bounded prior
and subsequent parallel dependencies, failures and job limits, plus cache
keys, runtime invalidation, output failures, gating, diagnostics, bypass,
selective clean and lexical `clean(path)` cases. The other two rows are
machine-registered as unsupported with exact reasons, so the project-owned
on-disk format is not misreported as an upstream byte-for-byte match.

## Phase 0-9 target and quality snapshot

Phase 9 passed its final PR and protected-main CI runs. The complete local and
remote evidence matrix reports:

| Gate | Result |
| --- | --- |
| `moon check --target all --warn-list +73` | pass |
| `moon test --target native` | 265 passed, 0 failed |
| `moon test --target wasm` | 261 passed, 0 failed |
| Architecture boundary check | twenty-one core packages and adapter leaves pass |
| Compatibility snapshot and manifest verifier | 2,417 registrations verified |
| Real differential smoke | 6 matches, 4 registered expected differences, 0 failures |
| Phase 5 Rust builtin oracle | 20/20 cases pass |
| Phase 6 Wasm inspect policy/oracle | pass; read-only, no process |
| Phase 7 HostFs policy | pass; atomic allow and typed denial |
| Phase 7 dotenv differential | pass; six fixtures, diagnostics redacted |
| Phase 7 invocation differential | pass; 11 argv and three Native/wasm1 usage cases |
| Phase 7 working-directory differential | pass; nine model and two CLI cases |
| Phase 7 environment differential | pass; seven precedence cases |
| Phase 8 executor gate | pass; dry-run, Native/wasm CLI corpus and executor package cases |
| Phase 8 security audit | pass; command construction, temporary scripts, process policy, redaction and cleanup |
| Phase 9 runtime gate | pass locally; scheduler/cache/store/process suites, exact and overflowing process-output limits, adversarial Native cache matrix, crash recovery and two-process contention |
| Phase 9 cache/concurrency audit | second review remediated unbounded process collection, compatibility overclaiming, quadratic lease cleanup and orphan commit temporaries; this re-audit also redacts `-vv` cache-key values and makes scheduler readiness incremental |
| Public interface and formatting review | `moon info && moon fmt` pass; no unintended `.mbti` changes |
| Phase 9 remote CI | PR [31480537856](https://github.com/moonbit-community/MoonJust/actions/runs/31480537856) and post-merge `main` [31480779327](https://github.com/moonbit-community/MoonJust/actions/runs/31480779327) pass all quality jobs and Ubuntu/macOS/Windows smoke |

Phase 5's Native C-binding ASan run remains an additional non-CI evidence
requirement and passed all 109 Native tests without sanitizer findings. The
historical Phase 0-5 clean coverage snapshot was 4,273/6,085 instrumented
points (70.2%). This re-audit also recorded 8,746/12,811 Native instrumented
points (68.3%) across the expanded Phase 0-9 tree; subprocess-only probes and
target adapters are additionally exercised by dedicated gates. These are
transparent measurements, not the later 1.0 release threshold.

## Phase-by-phase review

### Phase 0: foundation and governance

The repository, product identity, pinned upstream source, CC0 provenance,
compatibility inventory, differential harness, required checks, architecture
rules and dependency qualification records are preserved. The harness compares stdout,
stderr, exit status and filesystem trees without broad normalization. The
retained host capability spike remains isolated under `spikes/`; its
experimental API does not enter the pure core. The parser ecosystem spike was
removed after the project chose the in-project parser implementation.

### Phase 1: contracts and boundaries

Validated UTF-8 source bytes and half-open byte spans feed target-independent
diagnostics and lexical Unix/Windows paths. HostFs, HostEnv, HostClock,
HostRandom, HostProcess, HostTerminal, HostSignal and HostPlatform are explicit
contracts with a deterministic FakeHost. Application errors map usage,
compile, capability, recipe and signal failures without leaking host values.

### Phase 2: lexer

The lexer owns normal tokens, all string delimiter forms, indentation,
recipe/interpolation modes, format strings and resource budgets. Its 92
behavioral upstream registrations plus the Rust-private non-applicable helper
are machine-accounted; 16 success and five error oracle cases and 100,000
deterministic inputs cover boundary and hardening behavior on both targets.

### Phase 3: parser, formatter and Markdown

The recursive-descent parser preserves source spans and handles expressions,
assignments, aliases, recipes, dependencies, settings, attributes,
imports/modules and optional syntax. Canonical formatting is idempotent and
checked by a span-free semantic AST fingerprint. Markdown tangle preserves
source-byte locations and rejects unsupported fence contexts under explicit
budgets. All 324 applicable registrations have executable case anchors.

### Phase 4: semantic and loading graph

Compilation produces ordered symbols, typed settings/attributes, duplicate and
conflict diagnostics, minimum-version checks, dependency/parameter
validation, and an immutable query facade. Loader search, stdin, imports,
optional imports and modules use explicit HostFs, canonical identities and
span-bearing cycle chains. No loader path receives a process capability.

### Phase 5: evaluator and builtins

Lazy environments, recipe/module scopes, defaults, `+`/`*` variadics,
shadowing, exports and cycle diagnostics are explicit. The typed registry has
83 canonical builtins with capabilities and arity metadata. Pure and effectful
evaluation use caller-supplied context; regexp/SemVer behavior is checked
against 20 pinned Rust outcomes. SHA-256 and BLAKE3 support incremental string
and bounded Native file hashing, with unavailable portable range capability
reported explicitly.

### Phase 6: query CLI

The CLI inventories all 50 upstream options and 19 command entries; implemented
entries are explicit and unsupported entries fail stably rather than being
ignored. `check`, `fmt`, `init`, list/show/summary/usage/groups, evaluate,
variables, dump and schema-versioned JSON work without process execution.
The Wasm inspect adapter is read-only and the policy denies filesystem writes,
process spawn and network access. The 24-case Native/wasm1 query oracle passes.

### Phase 7: pre-execution composition

HostFs transactions provide atomic replace/no-overwrite, cleanup, permissions
and Windows canonicalization; the writable wasm1 transaction leaf is isolated
from the read-only inspect policy. Dotenv parsing follows the pinned dotenvy
behavior with explicit path/filename precedence, ambient override rules,
required/list/command modes and redacted diagnostics. Invocation parsing owns
recipe positional/variadic arguments, local options, repetition, patterns,
expressions and stable usage errors. The working-directory model separates
invocation, project, module, evaluation and recipe paths. CLI overrides,
shell ordering, tempdir and child-environment precedence are composed before
the explicit Phase 8 executor boundary.

### Phase 8: sequential executor preview

Application planning validates the complete recipe graph and composes explicit
shell, cwd, environment, dotenv, stdio, script and process contracts before the
runtime grants process access. The executor preserves source order, dependency
order, once keys, starred and parameterized dependencies, echo/quiet and
ignored-failure semantics, dry-run purity, separate output streams, stable
failures, timing and cancellation boundaries.

#### Command construction and process policy

Every ordinary process is a `CommandSpec`; the shell program and arguments stay
separate, while environment, cwd and all stdio policies are explicit and
FakeHost-assertable. Debug implementations report command structure and
environment keys only. Captured bytes, stdin and environment values are never
rendered. Shell arguments are passed exactly as configured: Unix `shell()` uses
the shell's `$0` positional-argument contract, while cmd and PowerShell omit
the Unix shell name as required by their invocation models.

Native and wasm process adapters pass exact cwd/env/stdin and capture streams
internally before publishing inherited output. Non-zero statuses map to typed
signals; cancellation delegates to async direct-child termination, wait, and
reap. Indirect, background, daemon, and detached descendants are outside the
cleanup contract, and a descendant can keep a shared output pipe open after
the direct child has been reaped.
The execute policy explicitly grants environment, filesystem and process
capabilities. The inspect policy remains deny-write and deny-spawn; execution
is never inferred from inspect mode.

#### Temporary scripts

Names combine a recipe stem with a cryptographic or host-random suffix;
separators are rejected and the required extension remains final. Native
creation is exclusive. Wasm creation uses `async/fs` `CreateNew` with policy
authorization and mode `0600` or `0700` for shebang execution. Cleanup is
registered in a structured task-group defer protected from cancellation and is
also attempted after materialization, specification or host failures. Dry-run
evaluates a redacted textual representation and never creates a file.

Full Phase 8 executor corpus mapping, interactive terminal streaming, complete
Windows job-object parity and browser/wasm-gc process execution remain
deferred. Bounded parallel scheduling and persistent cache are delivered by
Phase 9 below.

### Phase 9: bounded concurrency and cache

The async planner emits explicit recipe tasks with stable dense IDs and
dependency edges. Ordinary dependency groups form serial fences; `[parallel]`
groups share their entry fence and join before the recipe body. All runnable
tasks pass through a FIFO semaphore sized by validated `--jobs`. Output and
failure selection follow stable task order, independent of completion timing.

Cached script recipes require `--unstable`. Their versioned BLAKE3 key covers
body, executor, exported environment, cwd, positional values, `extra`, sorted
input digests and output contract. Inputs are hashed incrementally through
bounded HostFs ranges. `--no-cache` and dry-run bypass lookup, locks and writes.

Manifests are strict untrusted JSON. Native and wasm1 stores hold permanent
per-digest OS locks across lookup, execution and atomic commit. Corrupt entries
are misses; failed or cancelled recipes and missing outputs never publish a
valid entry. Reads are capped at 256 KiB plus one sentinel byte; leases bind
their opaque token to the exact directory and digest; structural diagnostics
redact script bodies, arguments and environment values. All-entry and
recipe/module-prefix clean preserve unrelated files and permanent locks. The
focused gate executes two Native processes against one digest and real
Native/wasm1 CLI miss/hit/invalidation workflows.

### Phase 10: compatibility convergence and platform behavior

The compatibility review traced PR-100 through PR-105 from plan text to
production code, tests, machine inventories and CI jobs. It closed CLI
environment entry-point gaps, platform-specific signal eligibility, terminal
TTY assumptions, string-valued dotenv/tempdir/shell settings, module working
directories, Windows CRLF handling and real `cmd.exe` coverage. The corrected
entry point consumes all supported `JUST_*` aliases and captures stdin when
`JUST_JUSTFILE=-` is selected by the environment.

The upstream map generator and verifier now require behavioral evidence for
executor, interactive, CLI, settings and attribute rows. The compatibility
gate reconstructs the pinned oracle, rejects name drift, missing reasons and
absent anchors, and permits no planned row. PR #41 merged as
`d18b64ee2bacd3afc0de6801ff3352c0b9224e2b`; remediation and protected-main CI
runs
[31617660952](https://github.com/moonbit-community/MoonJust/actions/runs/31617660952)
and
[31618046344](https://github.com/moonbit-community/MoonJust/actions/runs/31618046344)
passed quality, Ubuntu, macOS and Windows jobs.

The resulting map recorded 1,844 covered registrations, 526 explicit
unsupported differences, 35 completion exclusions and 12 not-applicable
internal or maintenance cases at that historical checkpoint. Unsupported
behavior was rejected or named with a machine-readable reason rather than
silently accepted. Browser/wasm-gc process execution, module-aware chooser
traversal and completion generation remained outside that checkpoint.

### Phase 11: release engineering

The release review traced PR-110 through PR-114 from source packages and Wasm
policies to candidate bytes, local staging, supply-chain documents, negative
tests, upgrade rehearsal and CI jobs. It required clean runners to bootstrap
and verify `moonx`, rejected Python/editor/cache and credential residue from
source packages, compared exact recursive archive members, rejected
case-insensitive collisions and duplicate checksum rows, and independently
reconstructed CycloneDX 1.5 and SLSA v1 objects.

Every isolated artifact runner installs the exact resolved dependency graph
before entering frozen mode. Extracted candidates execute version, query and
recipe corpora instead of relying on worktree binaries. The supported Native
matrix is Linux x86_64, macOS arm64 and Windows x86_64; macOS x86_64 remains
excluded because the official installer no longer distributes that toolchain.
Twelve independent tamper classes are rejected.

The delivery and remediation PRs #43 through #46 merged through required
checks. Failed discovery runs
[31672990008](https://github.com/moonbit-community/MoonJust/actions/runs/31672990008)
and
[31674990173](https://github.com/moonbit-community/MoonJust/actions/runs/31674990173)
remain visible evidence; later PRs close their dependency-bootstrap and
unsupported-platform causes. Audit closure was established by protected-main
run
[31697473589](https://github.com/moonbit-community/MoonJust/actions/runs/31697473589)
and candidate run
[31698189163](https://github.com/moonbit-community/MoonJust/actions/runs/31698189163).

## Security and architecture verdict

- Pure parser, semantic, evaluator, invocation, working-directory and
  environment models do not import concrete host adapters.
- Secrets are excluded from `Debug` representations and dotenv/override
  diagnostics; command argv, stderr and environment values are not retained in
  structural errors.
- Wasm inspection remains deny-by-default for writes and process spawn. The
  execute policy grants process capabilities explicitly; this is not a
  sandbox for untrusted justfiles, so users must apply an OS/container boundary.
- Atomic writes use same-directory temporary files, mode `0600`, synchronization
  before commit and best-effort cleanup that preserves the original typed error.
- Process stdout and stderr are drained concurrently in bounded chunks; each
  retained stream has a 16 MiB limit whose overflow cancels the child and emits
  one stable diagnostic instead of allocating without bound.
- Temporary executor scripts use exclusive creation, constrained permissions,
  final extensions and cleanup protected from cancellation. Command structure,
  and environment keys remain inspectable while captured bytes, stdin and
  environment values are not exposed by diagnostics.
- Cache paths reject absolute, drive, backslash, traversal, duplicate, control
  character and oversized contracts before host storage sees a filename;
  manifests and input/output collections have explicit allocation limits.
- Cache publication uses one reserved same-directory temporary per digest, mode
  `0600`, Full sync and atomic rename; cancellation-protected defers release
  leases. The next matching lease removes that exact name in O(1), while full
  clean locks and removes orphan temporaries for digests that are never reused.
- Public `.mbti` changes are limited to the reviewed Phase 9 scheduler, cache,
  host-store, task-plan and CLI contracts.

## Documentation consistency review

The final documentation pass checked 71 local Markdown links across all 44
tracked Markdown files (zero missing targets) and every tracked TOML status
pointer. GitHub API validation also resolved all 42 referenced MoonJust CI runs
as successful and all 21 directly referenced pull requests as merged. The pass
corrected old implementation baselines, old Phase 0-5 wording, stale
Phase 3-5-only upstream-tool instructions, missing Phase 3/4/5/7 evidence
links, the Phase 6 graph-serialization ownership sentence, and the old
`MJ-COMPAT-0003` rationale. Historical phase reports retain their original
phase-local test counts but now point readers to this current cross-phase audit.
The README is the current product entry point; [`PROJECT_PLAN.md`](../PROJECT_PLAN.md)
remains the scope and future-phase source of truth.

## Publication evidence

The functional and evidence PRs are all merged and their protected checks are
green:

| Delivery | Merge commit | PR CI | Post-merge `main` CI |
| --- | --- | --- | --- |
| Phase 6 implementation and remediation ([#21-#26](https://github.com/moonbit-community/MoonJust/pulls?q=is%3Apr+is%3Amerged+26)) | `8e9a3830d5e643c0e209db5a142c27d457932bb9` | [31163416512](https://github.com/moonbit-community/MoonJust/actions/runs/31163416512) | [31163576694](https://github.com/moonbit-community/MoonJust/actions/runs/31163576694) |
| Phase 7 functional delivery ([#28-#32](https://github.com/moonbit-community/MoonJust/pulls?q=is%3Apr+is%3Amerged+32)) | `3f1c1363c43e57c4881559077c1180507a1a8cfd` | [31243986487](https://github.com/moonbit-community/MoonJust/actions/runs/31243986487) | [31244169707](https://github.com/moonbit-community/MoonJust/actions/runs/31244169707) |
| Phase 7 second-audit remediation ([#33](https://github.com/moonbit-community/MoonJust/pull/33)) | `d80d8a394301fe4286c6a4b7b00592e586a9e029` | [31244887123](https://github.com/moonbit-community/MoonJust/actions/runs/31244887123) | [31244990807](https://github.com/moonbit-community/MoonJust/actions/runs/31244990807) |
| Final audited evidence ([#34](https://github.com/moonbit-community/MoonJust/pull/34)) | `9d0ba3418e419bbf57e1e350a0d7be10f04f6f17` | [31245191266](https://github.com/moonbit-community/MoonJust/actions/runs/31245191266) | [31245291788](https://github.com/moonbit-community/MoonJust/actions/runs/31245291788) |
| Phase 8 sequential executor preview ([#37](https://github.com/moonbit-community/MoonJust/pull/37)) | `91efac57788d851c4e38ab9027b5eb9099724b17` | [31393683064](https://github.com/moonbit-community/MoonJust/actions/runs/31393683064) | [31395657821](https://github.com/moonbit-community/MoonJust/actions/runs/31395657821) |
| Phase 9 bounded scheduler and cache ([#38](https://github.com/moonbit-community/MoonJust/pull/38)) | `d28d0b685ff886841f984510ee6a8fb8341cba2c` | [31480537856](https://github.com/moonbit-community/MoonJust/actions/runs/31480537856) | [31480779327](https://github.com/moonbit-community/MoonJust/actions/runs/31480779327) |
| Phase 9 audited evidence ([#39](https://github.com/moonbit-community/MoonJust/pull/39)) | `ffe99e288638a80219d621b703378f27f9a19f43` | [31481356601](https://github.com/moonbit-community/MoonJust/actions/runs/31481356601) | [31481583709](https://github.com/moonbit-community/MoonJust/actions/runs/31481583709) |
| Phase 10 compatibility convergence ([#41](https://github.com/moonbit-community/MoonJust/pull/41)) | `d18b64ee2bacd3afc0de6801ff3352c0b9224e2b` | [31617660952](https://github.com/moonbit-community/MoonJust/actions/runs/31617660952) | [31618046344](https://github.com/moonbit-community/MoonJust/actions/runs/31618046344) |
| Phase 11 release engineering ([#43](https://github.com/moonbit-community/MoonJust/pull/43)) | `b4b318c981a4b81a681afb6a4a00418d70cd046a` | [31669564990](https://github.com/moonbit-community/MoonJust/actions/runs/31669564990) | [31677969665](https://github.com/moonbit-community/MoonJust/actions/runs/31677969665) |
| Phase 11 candidate closure ([#44-#46](https://github.com/moonbit-community/MoonJust/pulls?q=is%3Apr+is%3Amerged+46)) | `09ac48c0a00dbf572e2d6242574da820446544f2` | [31698189163](https://github.com/moonbit-community/MoonJust/actions/runs/31698189163) | [31697473589](https://github.com/moonbit-community/MoonJust/actions/runs/31697473589) |

## Publication boundary

Repository automation prepares, validates, temporarily uploads and attests
release candidates only. It has no Mooncakes credential, `moon publish`, tag
creation or push, GitHub Release creation, or repository-contents write
permission. Formal publication remains exclusively a maintainer action.

## Conclusion

All declared Phase 0-11 exits are complete. The consolidated evidence covers
the language and query surface, execution and caching, platform behavior,
source packages, supported Native artifacts, the wasm1 asset, local
supply-chain verification and upgrade rollback. No review or clean-runner
finding remained open at audit closure, and no formal publication occurred.
Future compatibility or platform claims require updated machine evidence and a
new protected-main CI record.
