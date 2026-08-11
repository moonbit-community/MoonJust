# Phase 0-9 strict exit audit

- Review date: 2026-08-11
- Reviewed implementation baseline: Phase 9 delivery branch; final merge commit pending
- Final post-merge CI: pending protected-main run
- Accepted specification: [`docs/PROJECT_PLAN.md`](PROJECT_PLAN.md) v1.0
- Upstream baseline: `just 1.57.0` at
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- MoonJust application identity: `0.6.0-alpha`
- Required targets: Native and wasm1 through `moonrun`/`moonx`; Native smoke on Ubuntu, macOS and Windows

## Audit rule

This is an implementation and evidence audit, not a prose-only status review.
A phase passes only when its declared contracts have executable positive and
negative tests, target-appropriate capability boundaries, pinned upstream
provenance where applicable, deterministic machine-readable metadata, and
successful protected-main CI. Historical phase reports retain their original
scope and test snapshots; this document is the current cross-phase verdict.

## Final verdict

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
| 9 | bounded concurrency, persistent cache, atomic store, cleanup and determinism | complete | pending remote CI | PR-090..094, 72 covered plus 2 registered differences, 1,000-DAG stress, crash/two-process gates |

No applicable completed Phase 0-9 contract row remains `blocked-platform` or
`unverified`; Phase 6's explicitly inventoried unsupported options are stable
diagnostics rather than silent omissions. The compatibility inventory still
tracks 732 Phase 8 upstream registrations as `planned`: the sequential executor
preview is audited at its declared contract boundary, while full upstream
compatibility mapping remains a later compatibility task. Phase 9's cache,
clean and parallel inventory has 72 executable Native/wasm1 family
registrations and two explicit storage-tree differences with Phase 10
tracking. Phase 10 interactive/product tooling remains intentionally outside
this exit.

## Machine-verified compatibility accounting

The pinned `tests/upstream/just-1.57.0/test-list.txt` contains 2,417 unique
registrations. `tools/upstream/test_map.py` and
`tools/upstream/verify_manifest.py` validate row identity, owner phase,
disposition, target matrix, evidence paths, executable test declarations, and
deterministic case manifests.

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

## Target and quality matrix

The Phase 9 delivery awaits its final protected-main CI run. The prior Phase 8
baseline completed all required jobs; Phase 9 local gates currently report:

| Gate | Result |
| --- | --- |
| `moon check --target all --warn-list +73` | pass |
| `moon test --target native` | 263 passed, 0 failed |
| `moon test --target wasm` | 259 passed, 0 failed |
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
| Phase 9 cache/concurrency audit | second review remediated unbounded process collection and stale commit temporaries; final protected-main rerun pending |
| Public interface and formatting review | `moon info && moon fmt` pass; no unintended `.mbti` changes |
| Native platform smoke | Ubuntu, macOS and Windows pass; post-merge CI [31395657821](https://github.com/moonbit-community/MoonJust/actions/runs/31395657821) |

Phase 5's Native C-binding ASan run remains an additional non-CI evidence
requirement and passed all 109 Native tests without sanitizer findings. The
clean coverage snapshot is 4,273/6,085 instrumented points (70.2%); this is
transparent evidence, not the later 1.0 release threshold.

## Phase-by-phase review

### Phase 0: foundation and governance

The repository, product identity, pinned upstream source, CC0 provenance,
compatibility inventory, differential harness, required checks, architecture
rules and dependency spikes are all present. The harness compares stdout,
stderr, exit status and filesystem trees without broad normalization. The
async and parser ecosystem spikes remain isolated under `spikes/` and their
experimental APIs do not enter the pure core.

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
signals; cancellation delegates to async/process-group termination and reap.
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
- Cache publication uses same-directory exclusive temporaries, mode `0600`,
  Full sync and atomic rename; cancellation-protected defers release leases,
  and the next locked lease removes only strictly recognized stale temporaries.
- Public `.mbti` changes are limited to the reviewed Phase 9 scheduler, cache,
  host-store, task-plan and CLI contracts.

## Documentation consistency review

The final documentation pass checked every tracked Markdown/TOML status pointer
and corrected old implementation baselines, old Phase 0-5 wording, stale
Phase 3-5-only upstream-tool instructions, missing Phase 3/4/5/7 evidence
links, the Phase 6 graph-serialization ownership sentence, and the old
`MJ-COMPAT-0003` rationale. Historical phase reports retain their original
phase-local test counts but now point readers to this current cross-phase audit.
The README is the current product entry point; [`docs/PROJECT_PLAN.md`](PROJECT_PLAN.md)
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
| Phase 9 bounded scheduler and cache | pending merge | pending PR CI | pending post-merge CI |

## Conclusion

Phase 0-9 implementation is complete and locally re-certified; the Phase 9
exit becomes final only after the pending PR and protected-main CI are green.
MoonJust now provides deterministic bounded scheduling and a persistent,
cross-process-safe Native/wasm1 cache. Interactive tooling, complete Windows
job-object parity and browser/wasm-gc process execution remain owned by later
phases. Any future claim beyond this boundary requires a new phase audit,
updated compatibility evidence and a protected-main CI record.
