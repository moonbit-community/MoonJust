# Final Release Review

This report records the release-candidate review for the
`codex/strict-beta-hardening` feature branch. It complements the historical
phase reports; it does not change the pinned upstream contract or the public
MoonBit API.

## Fixed baseline

- Upstream: `just 1.57.0`
- Upstream commit: `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Public interface hash (`api/pkg.generated.mbti`):
  `0c221c1df903e3b4bf43df7750d8bd9753204bf713e1266de9c293a0124cb14c9`
- Review implementation head: `aa1c1040ffdbd011ec8dceed07757005968c54aa`

## Functional and compatibility review

The final local review ran Native and wasm1 full tests, all-target checking
with `--deny-warn`, formatting, architecture boundaries, tool tests and the
official upstream harness. The harness result is:

| Target | Exact/diagnostic | Failed | Completion | Signals |
| --- | ---: | ---: | ---: | ---: |
| Native | 1,792 | 0 | 30 excluded | 14 passed |
| shared wasm1 | 1,792 | 0 | 30 excluded | 14 passed |

The supported matrix is Linux x86_64, macOS arm64 and Windows x86_64 Native,
plus one Ubuntu-built shared wasm1 artifact consumed by each platform gate.
The two Linux MoonX invalid UTF-8 cwd cases remain explicitly
`not-applicable`; they are host-environment limitations, not MoonJust
normalization or functional failures. Completion remains excluded.

The review fixed one real compatibility issue: the shared wasm launcher passed
Apple's `arm64` spelling through `arch()`, while Rust just reports `aarch64`.
The portable host now normalizes `arm64`/`amd64` aliases and has a regression
test. The release benchmark also now passes the real host OS/architecture into
portable Wasm and writes fixtures as platform-neutral UTF-8 bytes, closing the
Windows path and CRLF measurement failures without workload-specific branches.
No special workload or platform result is hard-coded.

## Performance and size

Performance authority is hosted cloud trend evidence, not a developer laptop.
The release workflow exercises Linux, macOS and Windows with three cold/warm
rounds and records raw samples, toolchain identity and exact head SHA. It is
used to detect regressions and compare candidates under the same workflow; it
does not claim a universal absolute latency independent of host hardware.

The final RC measured Native growth of 6.04%–10.81% by platform, shared wasm1
growth of 7.13%, and archive growth of 6.25%–10.71% against the frozen
baseline. The strict size job remains a separately visible release gate
exception. No size threshold was relaxed and no functional or compatibility
result is hidden by this exception.

## Verification system changes

- `tools/runner.py` is the public runner for `fast`, `verify`, `compat` and
  `release` modes.
- Build registry keys bind commit/tree/target/host/profile/toolchain,
  dependency graph and source input digests before artifact reuse.
- Evidence records carry the exact head SHA, registry references, artifact
  hashes, command/environment digests, measurements and classifications.
- Native, platform, signal, process and interactive evidence is never reused
  across hosts; only the checked shared wasm artifact crosses platform jobs.

## Exact-head evidence

- PR CI run `32637581499` passed at exact head
  `aa1c1040ffdbd011ec8dceed07757005968c54aa`.
- Release Candidate run `32639532630` passed correctness, contract, coverage,
  repeatability and all three cloud-trend performance jobs at that exact head.
- The same RC reports the independent artifact-size exception described above;
  its aggregate release job is expected to remain red until a separate size
  optimization phase is authorized.
- The final documentation commit must receive its own exact-head PR CI before
  the Draft PR is merged. The PR remains Draft and no size threshold is being
  relaxed.
