# Contributing to MoonJust

MoonJust follows the staged compatibility process in
[`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md). A change is ready for integration
only when its upstream behavior, compatibility tier, supported targets, and
acceptance tests are explicit.

## Local setup

1. Install the toolchain versions listed in `README.mbt.md`.
2. Enable the repository hook with `git config core.hooksPath .githooks`.
3. Run `./tools/check.sh` before opening a pull request.

## Pull requests

- Keep production changes below roughly 800 lines and fixtures below roughly
  1,500 lines unless the PR explains why generated data cannot be split.
- Reference the corresponding `MJ-*` issue or compatibility ID.
- Cite `just 1.57.0` behavior and add a differential or focused regression
  test.
- Report Native, wasm1, and all-target check results.
- Call out public `.mbti`, dependency, security, persistence, and performance
  changes.
- Do not broaden a differential normalizer or update golden output without
  explaining the observed behavior.

The full Definition of Ready, independent-maintainer self-review policy, and
Definition of Done are in the project plan.
