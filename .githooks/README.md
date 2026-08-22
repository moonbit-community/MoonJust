# Git hooks

## Pre-commit hook

The pre-commit hook runs the same deterministic checks as the primary local
quality script.

### Usage Instructions

To use this pre-commit hook:

1. Configure Git to use the hooks in the `.githooks` directory:

   ```bash
   git config core.hooksPath .githooks
   ```

2. Commit normally. The hook invokes `python3 tools/runner.py run --mode fast` and stops the commit on
   formatting, type-checking, test, or CLI smoke failures.
