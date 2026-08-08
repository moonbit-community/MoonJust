# Phase 4 completion report

- Status: Implemented; Phase 4 exit passed
- Strict review: 2026-08-06 ([Phase 0-7 audit](PHASE_0_7_AUDIT.md))
- Historical phase snapshot; the current cross-phase verdict is in the audit above.
- Upstream baseline: `just 1.57.0`
- Required implementation targets: Native and wasm1
- Scope: semantic compilation, typed settings/attributes, capability-backed loading, and import/module graph validation

The strict remediation is complete. The semantic and loader contracts now
have executable Native/wasm1 evidence, including a real `moonbitlang/x/fs`
adapter, native `realpath` identity, case-insensitive justfile discovery,
source-unified stdin/Markdown loading, cycle chains with import spans, and
static dependency/variable/version validation.

## Delivered contracts

| Unit | Implementation | Evidence |
| --- | --- | --- |
| PR-040 | `src/semantic` ordered symbols and duplicate rules | duplicate variable/recipe behavior, stable query order |
| PR-041 | typed `CompiledSettings` and conflict validation | dotenv/no-cd conflict pairs and boolean flags |
| PR-042 | `RecipeAttributes` metadata and platform selectors | private/doc/group/shell/script/platform conflict tests |
| PR-043 | `src/loader` search and explicit loading | memory host ceiling, explicit missing, capability errors |
| PR-044 | deterministic import/module graph | optional omission and cycle diagnostics |
| PR-045 | static recipe, alias, dependency and variable validation | no process capability is consulted by compile |
| PR-046 | immutable `Compilation` query facade | source-aware symbols, names, recipes, variables and settings |

## Frozen decisions

- Semantic packages depend only on `syntax`, `source`, and diagnostics; they do not import host contracts.
- Loader APIs use generic `HostFs`/`HostEnv` bounds and map every host failure to `LoaderError`.
- Search is deterministic across `justfile`, `.justfile`, and case variants;
  the caller supplies the start directory, optional ceiling, and optional
  global fallback; global process state is never read.
- Explicit, stdin, Markdown, filesystem, import, and module sources share the
  same source/parser boundary.
- Import and module identities use HostFs canonicalization, and optional
  declarations are skipped only when the file is absent.
- Static dependency and alias cycles are rejected before any evaluator or process layer is involved.

## Verification evidence at the Phase 4 exit

- `moon check --target all --warn-list +73` passes without warnings.
- `moon test --target native`: 109 passed, 0 failed.
- `moon test --target wasm`: 108 passed, 0 failed.
- The Phase 4 upstream case manifest links all 427 registrations to
  loader/semantic suites with Native/wasm1 targets. Each row carries an
  executable `suite`/`test_name` anchor checked by the manifest verifier;
  repeated anchors explicitly denote family-level coverage.
- `src/host_native/native_test.mbt` verifies real file reads, directory
  enumeration, metadata and canonical identity; the FFI stub is covered by the
  native build.
- `tools/check_architecture.sh` verifies fourteen core packages plus the host
  adapter leaf and keeps `semantic` host-free.
- Generated `pkg.generated.mbti` files are reviewed for the new public semantic and loader surfaces.

Phase 5 may consume `Compilation`, `Expression`, `SettingValue`, and host traits without reaching into parser or loader internals.
