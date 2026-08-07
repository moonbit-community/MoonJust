# MoonJust architecture

## Design rule

MoonJust implements observable `just` behavior rather than translating Rust
files one by one. The architecture keeps parsing, analysis, evaluation, and
planning deterministic and independent from host I/O. Filesystem, environment,
process, terminal, time, random, and signal operations enter through
project-owned capabilities.

```text
cmd/just
  -> cli
  -> loader -> source -> lexer -> syntax -> parser
            -> semantic -> evaluator -> invocation -> planner
            -> runtime -> host
                       -> host_native
                       -> host_wasm
```

Dependencies flow from the command composition root toward leaf packages.
`source`, `syntax`, `semantic value types`, and `diagnostic IR` do not import a
host adapter. Target-specific `#cfg` and FFI are restricted to host adapters.

## Package ownership

| Package | Responsibility | Must not own |
| --- | --- | --- |
| root facade | stable user-facing API and build metadata | parser internals or target FFI |
| `source` | UTF-8 bytes, source IDs, byte spans, line index | terminal rendering |
| `diagnostic` | structured diagnostic values and render contracts | process exits |
| `path` | host-independent Unix/Windows lexical path values | filesystem canonicalization |
| `lexer` | tokens and lexical state machines | semantic name resolution |
| `syntax` | AST/CST types used by parser and formatter | filesystem loading |
| `parser` | recursive-descent grammar | imports or command execution |
| `formatter` | canonical source rendering and check diffs | source discovery |
| `semantic` | settings, attributes, symbols, static validation | host side effects |
| `loader` | source discovery and import/module graph | direct target FFI |
| `evaluator` | pure and explicitly effectful expression evaluation | arbitrary global environment reads; implicit host access |
| `invocation` | recipe argument and option parsing | global CLI parsing |
| `planner` | ordered dependency DAG and execution plan | process spawning |
| `runtime` | scheduler, cache state machine, execution orchestration | backend-specific calls |
| `host` | project-owned capability contracts and errors | third-party concrete types |
| `host_native` | Native capability implementation | language semantics |
| `host_wasm` | moonrun/moonx wasm1 capability implementation | browser compatibility claims |
| `host_wasm/transaction` | policy-aware wasm1 atomic file transactions | synchronous core loading or direct WASI calls |
| `cli` | argv validation and application request | parser internals |

Packages are introduced only when their phase starts. Empty directories and
placeholder public APIs are not committed merely to mirror this table.

## Dependency policy

1. MoonBit core packages are preferred.
2. Official ecosystem packages are isolated behind MoonJust contracts.
3. Community packages require target, license, maintenance, and differential
   contract evidence.
4. Compatibility-critical behavior is implemented in-project when no package
   passes the contract.
5. A package version is exact, and an update is a reviewed compatibility
   change.

## Public API policy

The root package owns public concrete types users are expected to inspect or
construct. Internal implementation packages do not leak concrete types through
the facade. Every public change is reviewed through generated
`pkg.generated.mbti` files and black-box tests.

## Target policy

- `native`: production CLI target for supported Linux, macOS, and Windows
  runners.
- `wasm`: production CLI target under `moonx`/`moonrun` when the host grants
  required capabilities.
- `wasm-gc` and `js`: pure-core check targets until a later ADR expands scope.
- Browser and arbitrary WASI recipe execution are not initial release promises.

## Architecture tests

CI enforces all-target type checking, Native/wasm tests, generated interface
stability, and `tools/check_architecture.sh`. The architecture check rejects
target-specific FFI, conditional compilation, async implementation, and host
adapter imports in completed pure-core packages. The `host` package may declare
an async capability, but runtime imports and implementations remain confined to
leaf adapters. Its package inventory expands when a new pure-core phase begins.
Compatibility manifests are verified alongside the pinned upstream inventory.
