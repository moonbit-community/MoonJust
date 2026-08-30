# Changelog

MoonJust is a binary-only MoonBit implementation compatible with just 1.57.0.
The root package builds the executable; implementation details remain under
`internal/` and are not a supported library surface.

## Unreleased

- Reorganized the implementation around explicit CLI, application, project,
  query, planner, runtime, and host phases.
- Moved platform-independent file algorithms into `internal/host_fs` and split
  parser, loader, evaluator, planner, runtime, and process modules by
  responsibility.
- Rebuilt functional and differential runners in MoonBit under `tests`.
- Preserved Native/Wasm behavior, process cleanup, cache behavior, and the
  just 1.57 compatibility corpus.
