# Phase 10 Completion Report

- Scope: PR-100 through PR-105 from `docs/PROJECT_PLAN.md`
- Compatibility baseline: `just 1.57.0` at `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Release identity: `0.7.0-alpha`
- Local review date: 2026-08-12
- Delivery: pending pull request and remote CI

## Delivered contracts

| PR | Contract | Local exit evidence |
| --- | --- | --- |
| PR-100 | Native OS/architecture/TTY facts, Windows path flavor, cmd/PowerShell and signal-aware statuses | platform probe, Windows model tests, three-runner CI gate |
| PR-101 | Unix shebang permissions, signal mapping and graceful process cancellation | Native adapter tests and Linux/macOS gate |
| PR-102 | evaluated confirm prompts, `--yes`, chooser and editor capabilities | deterministic FakeHost tests and real non-hanging CLI workflows |
| PR-103 | list/command color, NO_COLOR, Unicode display width and stable long-signature layout | ANSI, terminal-mode and width golden tests |
| PR-104 | final source-aware Markdown implementation and automatic `.md` loading | five upstream tangle tests plus Native/wasm1 boundary suites and ADR-0017 |
| PR-105 | complete flags/settings/attributes/builtins/tests inventory | manifest verifier rejects `planned`, missing reasons, missing anchors and name drift |

## Platform and interaction

`host_native` now probes the compiled operating system and architecture through
a leaf C adapter and observes stdin/stdout/stderr TTY state without leaking
platform conditionals into semantic or planner packages. Windows selects
Windows lexical paths and supports cmd/PowerShell script extensions and UTF-8
PowerShell BOMs. Unix shebang scripts are created executable. Process results
retain structured termination signals and use `128 + signal` exit codes;
cancellation delegates to a bounded graceful process-group handler.

Confirmation requests are fully evaluated while planning and preserve direct
versus dependency context. The CLI prompts on stderr, accepts only `y`/`yes`,
treats EOF or a negative answer as a stable failure, and starts no recipe
process before all requests are accepted. `--yes` bypasses prompts.

The chooser receives sorted public zero-required-argument root recipes through
stdin. CLI `--chooser` overrides `JUST_CHOOSER`, which overrides the documented
fzf command. Each selected line becomes an independent invocation; status 130
is cancellation, other exits and signals propagate. Editor selection is
`VISUAL`, then `EDITOR`, then `vim`, with inherited stdio and the justfile
directory as cwd. Editing remains available for malformed source.

## Terminal and Markdown

Color modes are `auto`, `always`, and `never`. Auto requires the relevant TTY,
terminal color support and absence of `NO_COLOR`; forced color is deterministic
under redirected output. Command echo defaults to bold, supports the upstream
named palette, and list docs color comment markers and backtick spans.
Unicode width handles combining marks, variation selectors, emoji modifiers,
ZWJ sequences and regional-indicator flags without changing alignment.

ADR-0017 selects the dedicated source-aware Markdown extractor. Loader paths
recognize `.md` case-insensitively, including `--justfile-name`. Only top-level
fenced `just` blocks are selected; quote/list/comment/indented/outer-fence
content stays prose. Formatting Markdown emits canonical extracted just source
without mutating the original document. The pinned upstream's five tangle unit
tests pass unchanged.

## Compatibility accounting

Every one of the pinned 2,417 upstream registrations is explicitly classified:
1,844 are `covered-by` executable family tests, 526 are `unsupported` with a
reason, 35 completion rows are excluded, and 12 rows are not applicable. No
row remains `planned`.

Phase 10 owns 52 registrations: 40 covered, four chooser/module differences,
five excluded completion cases and three non-applicable maintenance/internal
cases. The previously deferred Phase 8 inventory is also resolved
conservatively: 209 covered, 520 unsupported and three not applicable. A family
anchor is evidence for a behavior family, not a claim that MoonJust copied each
Rust test one-for-one.

The CLI inventory contains 50 options and 19 commands. Settings (29),
attributes (29), and builtins (83) are exact-name checked. Recognition or JSON
serialization alone no longer counts as implementation; partial behaviors are
marked unsupported with a concrete reason. The audit also fixed string-valued
dotenv filename/path, tempdir, shell and static module working-directory
settings that were previously parsed but not consumed. Effectful global
backticks and shell functions still use their original evaluation cwd, so that
part of `working-directory` remains explicitly unsupported.

## Gates

Local evidence currently passes 297 Native and 292 wasm1 tests, strict
all-backend checking, formatting, public compatibility verification, the
macOS aarch64 real platform gate, and all five pinned upstream tangle tests.
`tools/check_phase10_platform.sh` is also installed in the Ubuntu, macOS and
Windows Native matrix. Remote PR and protected-main evidence will be recorded
only after those runs complete.
