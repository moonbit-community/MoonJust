# ADR-0015: Phase 7 working-directory model

- Status: Accepted
- Date: 2026-08-08

## Context

Upstream `just` distinguishes the directory where the process was invoked,
the project directory selected by justfile discovery or `-d`, and the directory
owned by each module. Imports locate their source relative to the importing
file but retain the containing module's execution directory. Modules establish
a new directory at their own source file.

The path used to display a justfile must also remain separate from its
canonical filesystem identity. Canonicalizing the project directory would
make a justfile reached through a symlink run relative to the target instead of
the user-visible symlink parent.

## Decision

- `src/workdir` is a pure package that stores invocation, project, and module
  directories as lexical `PathValue` values. It never consults a filesystem or
  changes global process state.
- Relative `--justfile` and `--working-directory` values are resolved against
  the explicit invocation directory. Stdin uses the invocation directory unless
  `-d` supplies an override.
- A module-level `working-directory` setting is relative to that module's base
  and controls expression evaluation as well as the default recipe cwd.
- Recipe `[no-cd]` and `set no-cd` select the invocation directory only for
  recipe execution. They do not redirect variable, backtick, or shell-function
  evaluation. A recipe `[working-directory(...)]` takes precedence over either
  no-cd source and is relative to the module evaluation directory.
- Loader graph nodes record whether they are roots, imports, or modules and
  expose their module directory. Imports inherit the parent module directory;
  modules use their source file's display parent. Canonical paths remain the
  identity used for graph deduplication and cycle detection.

## Consequences

Phase 8 can assign every process request an explicit cwd without rereading
ambient process state. Evaluation and execution can share the same model while
preserving their intentional no-cd difference.

The loader interface gains source relation and module-directory accessors.
There is no persistent format, dependency, license, or host-capability change.
Nine model cases and two Native/Wasm CLI cases compare cwd selection with
pinned `just 1.57.0`. Cross-target package tests cover path flavors, imports,
modules, symlink display paths, settings, attributes, and errors.
