# just 1.57.0 to 1.59.0

The three-target upstream inventory grew from **2,427 to 2,461 IDs** across 1.58.0 and 1.59.0. There are 37 additions, 3 removals and 71 retained IDs whose Rust function or test macro invocation changed. The complete Git comparison covers 32 commits and 94 paths, with 2,153 inserted and 1,052 deleted lines. The historical 1.57.0 list contains the 2,417 IDs discovered on macOS. [Official comparison](https://github.com/casey/just/compare/1.57.0...1.59.0)

| Release | Date | Peeled commit | Commits since previous row |
| --- | --- | --- | ---: |
| [1.57.0](https://github.com/casey/just/releases/tag/1.57.0) | 2026-07-18 | `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f` | — |
| [1.58.0](https://github.com/casey/just/releases/tag/1.58.0) | 2026-08-03 | `7f4ef81bd6a93faa2b28430912c8e9ab0e3dd29a` | 7 |
| [1.59.0](https://github.com/casey/just/releases/tag/1.59.0) | 2026-10-14 | `2638e9c0941edb1f409da7426fa7842887656973` | 25 |

## Release changes

1.58.0 adds per-recipe timestamps with an optional format expression, accepts comma-separated justfile names and inserts spaces around formatted interpolation expressions. The release also documents the working-directory scope of `no-cd` and adds a GitHub link. The two timestamp commits are separate entries in the ledger. [1.58.0 notes](https://github.com/casey/just/blob/2638e9c0941edb1f409da7426fa7842887656973/CHANGELOG.md#L41-L54)

1.59.0 requires Unicode paths. A non-Unicode invocation directory now fails, while an unrelated non-Unicode sibling file can coexist with a valid justfile. It adds `--working-directory` without `--justfile`, module-wide `--usage` and cache-key environment expressions. It changes usage spacing, traversal order, function diagnostics and the default chooser's justfile environment. It also handles stdout broken pipes and limits the PowerShell shebang BOM to Windows. [1.59.0 notes](https://github.com/casey/just/blob/2638e9c0941edb1f409da7426fa7842887656973/CHANGELOG.md#L4-L39)

The complete ledger also covers shell completion, the installer and minified JSON, CI/workflow locking, dependency and error-handling changes, lint configuration, man-page escaping, developer scripts, and documentation including Chinese typography and language metadata. Each of the 30 release-note items and both release commits has a full commit SHA and a line in the 1.59 changelog. The hunk table records every changed range for each commit and the endpoint comparison, including changes superseded before 1.59.0. [Commit ledger](release-commits.tsv) · [Source hunks](source-hunks.tsv)

### Test evidence and target scope

| Rust test registration | just 1.57.0 | just 1.59.0 | Ignored in each release |
| --- | ---: | ---: | ---: |
| macOS, aarch64-apple-darwin | 2,417 | 2,451 | 19 |
| Linux, x86_64-unknown-linux-gnu | 2,418 | 2,452 | 18 |
| Windows, x86_64-pc-windows-gnu | 2,393 | 2,426 | 6 |
| Unique IDs across these three targets | 2,427 | 2,461 | — |

IDs are the Rust test harness's fully qualified names from the `just` library and the `integration` target. The Rust compiler gives each ID's source file and one-based line, including the `name:` argument for macro-generated tests. The macOS counts come from compiled, locked native Cargo test harnesses. Linux and Windows counts come from the corresponding target's Rust test descriptors after locked Cargo type-checking and compiler expansion on macOS (Rust/Cargo 1.97.1, `blake3/pure` for cross-checking). Those two populations describe compiled registrations. Native execution, a passing assertion and MoonJust differential parity each require their own evidence.

The platform tables list every registration with a restricted target set or an ignore flag. Every other registration is present and enabled on all three targets. The target names in these tables describe the three targets above. Upstream also gates SIGINFO on several BSD systems and iOS. A registered test may return early at runtime, as the Unix PowerShell BOM test does on Windows. [1.57 platform exceptions](platforms-1.57.0.tsv) · [1.59 platform exceptions](platforms-1.59.0.tsv) · [SIGINFO gate](../upstream/just-1.59.0/source/tests/signals.rs#L303) · [PowerShell test](../upstream/just-1.59.0/source/tests/shebang.rs#L55)

The ten 1.59 IDs outside the macOS list comprise two Linux non-Unicode tests, seven Windows shell/shebang tests, and a Windows drive-root unit test. The same eight Windows IDs existed in 1.57.0. Linux replaces two old warning IDs with `non_unicode_invocation_directory_is_an_error` and `non_unicode_sibling_files_are_ignored`. Their host-probe results belong to the active runner's evidence. [Module gates](../upstream/just-1.59.0/source/tests/lib.rs#L152) · [Linux tests](../upstream/just-1.59.0/source/tests/non_unicode.rs#L4) · [Drive-root test](../upstream/just-1.59.0/source/src/clean.rs#L146)

| Artifact | Meaning |
| --- | --- |
| [1.59 test list](../upstream/just-1.59.0/test-list.txt) | One ID per member of the three-target union, in bytewise lexical order. |
| [1.59 spec index](../upstream/just-1.59.0/spec-index.txt) | Each ID has an official Rust anchor. Local evidence has a separate location and name. A row pointing directly to vendored Rust records source provenance only. The active runner determines execution status from the fixture, named test, document oracle, host contract or exclusion. |
| [Supplemental 1.57 anchors](supplemental-anchors-1.57.0.tsv) | The 201 macOS registrations whose declarations were absent from the historical 1.57 spec index. Used only to reconstruct the historical comparison. |
| [Registration changes](registration-delta.tsv) | Every added or removed upstream ID with its declaration anchor. Mac-only discovery would show 35 additions and one removal. |
| [Changed tests](changed-tests.tsv) | Every common ID with different Rust function or macro-invocation text, including whitespace and changes to expected diagnostics. Ranges are one-based and inclusive at each release. Helpers, attributes outside an item and shared macro definitions remain visible in the Git hunks. |
| [Source hunks](source-hunks.tsv) | Exactly 749 per-commit and 675 endpoint hunks. Both sides use Git's zero-context `start,count` convention. A zero count marks an insertion/deletion boundary. Full SHA and parent resolve intermediate paths via `git show REV:path`. |
| [Release archive digests](oracle-archives.tsv) | GitHub's SHA-256 for all ten binary archives in each release. The hashes cover downloaded archives. |

## Reproduce

Run from the MoonJust repository root. The checks read the tracked files and use a temporary directory for the live CLI probes. The standalone MoonBit compiler may populate its ignored build cache.

```sh
U=tests/compatibility/upgrade
moon run "$U/verify.mbtx"
moon run "$U/local-anchors.mbtx"
git clone --no-checkout https://github.com/casey/just.git "$RUNNER_TEMP/just-tags"
moon run "$U/git-delta.mbtx" -- "$RUNNER_TEMP/just-tags"
```

Use a scratch directory for `RUNNER_TEMP` locally. The Git check verifies all three peeled tags, regenerates both Git tables and checks the byte-exact blobs and complete vendored file set against the 1.59.0 commit. Use LF checkouts for this byte check. Pass the TSV name as the final argument to print a regenerated Git table. `local-anchors.mbtx -- --print-index` prints a refreshed index from `moon test --target wasm --outline` for review. It preserves the other columns and source-only entries.

### Official executables

Select the archive suffix for the CI host from the digest table. On macOS arm64 the following commands download, verify and extract both oracle executables into separate directories. On Linux use the corresponding Linux archive and `sha256sum -c`. For Windows use the listed MSVC zip, verify with `Get-FileHash -Algorithm SHA256` and extract `just.exe`.

```sh
set -eu
U=tests/compatibility/upgrade
for v in 1.57.0 1.59.0; do
  dest="$RUNNER_TEMP/just-$v"
  mkdir -p "$dest"
  archive="just-$v-aarch64-apple-darwin.tar.gz"
  gh release download "$v" --repo casey/just --pattern "$archive" --dir "$dest"
  digest=$(awk -F '\t' -v name="$archive" '$2 == name {sub(/^sha256:/, "", $3); print $3}' "$U/oracle-archives.tsv")
  (cd "$dest" && printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 -c -)
  tar -xzf "$dest/$archive" -C "$dest" just
done
moon run "$U/verify.mbtx" -- oracles "$RUNNER_TEMP/just-1.57.0/just" "$RUNNER_TEMP/just-1.59.0/just"
```

The probes check both exact version banners and the entire emitted changelog against the official Git blob. They also compare distinct formatter output and root-module usage behavior for each executable, including status, stdout and stderr. These are release-identity and behavior checks on the official binaries. MoonJust compatibility uses the differential runner.

### Native registration and changed-body checks

On each CI host, set `HOST` to `linux`, `windows` or `macos`. Use a separate official source checkout for each release. The tracked MoonJust source subset omits Cargo build metadata. These commands discover tests without running test bodies.

```sh
U=tests/compatibility/upgrade
v=1.59.0
git -C "$RUNNER_TEMP/just-tags" worktree add --detach "$RUNNER_TEMP/src-$v" "$v"
cargo test --locked --manifest-path "$RUNNER_TEMP/src-$v/Cargo.toml" -- --list > "$RUNNER_TEMP/list-$v.txt"
moon run "$U/verify.mbtx" -- cargo-list "$v" "$HOST" "$RUNNER_TEMP/list-$v.txt"
cargo test --locked --manifest-path "$RUNNER_TEMP/src-$v/Cargo.toml" -- --ignored --list > "$RUNNER_TEMP/ignored-$v.txt"
moon run "$U/verify.mbtx" -- cargo-ignored "$v" "$HOST" "$RUNNER_TEMP/ignored-$v.txt"
```

Repeat with `v=1.57.0`. To compare every compiler-reported source path, line and ignore flag, the pinned discovery toolchain also supports unstable libtest JSON. The ordinary and ignored list checks above use stable Cargo output.

```sh
RUSTC_BOOTSTRAP=1 cargo +1.97.1 test --locked --manifest-path "$RUNNER_TEMP/src-$v/Cargo.toml" -- --list -Z unstable-options --format=json > "$RUNNER_TEMP/descriptors-$v.jsonl"
moon run "$U/verify.mbtx" -- cargo-json "$v" "$HOST" "$RUNNER_TEMP/descriptors-$v.jsonl"
```

The optional body comparison uses ast-grep 0.39.6. It parses both vendored Rust trees, resolves each registration to its smallest enclosing function or macro invocation, compares text for all common IDs and checks the complete table of changed ranges. This check requires the ast-grep CLI binary path.

```sh
npm install --prefix "$RUNNER_TEMP/ast-tools" --no-save @ast-grep/cli@0.39.6
moon run "$U/verify.mbtx" -- changed-tests "$RUNNER_TEMP/ast-tools/node_modules/.bin/ast-grep"
```
