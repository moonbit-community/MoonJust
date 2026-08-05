# Phase 4 implementation report

- Status: Implementation baseline merged; original Phase 4 exit pending
- Strict review: 2026-08-05 ([Phase 0-5 audit](PHASE_0_5_AUDIT.md))
- Upstream baseline: `just 1.57.0`
- Required implementation targets: Native and wasm1
- Scope: semantic compilation, typed settings/attributes, capability-backed loading, and import/module graph validation

This report records the implementation that was merged for Phase 4. It is not
evidence that every original `PROJECT_PLAN.md` exit condition has passed. The
strict review found that the complete settings and attributes inventories are
still marked planned, loader coverage is memory-host-only, and the full static
validation and cross-file diagnostic matrix is not yet present.

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
- Search is lexical and deterministic: the caller supplies the start directory and optional ceiling; global process state is never read.
- Import and module identities are normalized `PathValue` values, and optional declarations are skipped only when the file is absent.
- Static dependency and alias cycles are rejected before any evaluator or process layer is involved.

## Current verification evidence

- `moon check --target all --warn-list +73` passes without warnings.
- `moon test --target native`: 71 passed, 0 failed.
- `moon test --target wasm`: 71 passed, 0 failed.
- `tools/check_architecture.sh` now covers eleven Phase 1-4 packages and keeps `semantic` host-free.
- Generated `pkg.generated.mbti` files are reviewed for the new public semantic and loader surfaces.

Phase 5 may consume `Compilation`, `Expression`, `SettingValue`, and host traits without reaching into parser or loader internals.
