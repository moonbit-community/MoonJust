#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-phase10-platform.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

fail() {
  echo "Phase 10 platform gate failed: $1" >&2
  exit 1
}

moon test --target native src/host
moon test --target native src/host_native
moon test --target native src/host_process
moon test --target native src/environment
moon test --target native src/executor
moon test --target native src/application
moon build cmd/just --target native >/dev/null
cli="$repo_root/_build/native/debug/build/cmd/just/just.exe"
[ -x "$cli" ] || [ -f "$cli" ] || fail "Native CLI artifact is missing"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    expected_os=windows
    cat >"$work/justfile" <<'EOF'
set windows-powershell
[confirm('Run phase 10?')]
confirm:
  Write-Output phase10-confirm

alpha:
  Write-Output phase10-choice

[shell('cmd.exe', '/C')]
cmd-probe:
  echo phase10-cmd

# `phase10` platform probe
platform:
  Write-Output {{os()}}
  Write-Output {{arch()}}

fail:
  exit 7

[script]
script:
  Write-Output phase10-script
EOF
    ;;
  Darwin)
    expected_os=macos
    cat >"$work/justfile" <<'EOF'
[confirm('Run phase 10?')]
confirm:
  echo phase10-confirm

alpha:
  echo phase10-choice

# `phase10` platform probe
platform:
  echo {{os()}}
  echo {{arch()}}

[script]
script:
  #!/bin/sh
  echo phase10-script
EOF
    ;;
  Linux)
    expected_os=linux
    cat >"$work/justfile" <<'EOF'
[confirm('Run phase 10?')]
confirm:
  echo phase10-confirm

alpha:
  echo phase10-choice

# `phase10` platform probe
platform:
  echo {{os()}}
  echo {{arch()}}

[script]
script:
  #!/bin/sh
  echo phase10-script
EOF
    ;;
  *) fail "unsupported runner operating system: $(uname -s)" ;;
esac

set +e
(cd "$work" && "$cli" platform >platform.stdout 2>platform.stderr)
platform_status=$?
set -e
if [ "$platform_status" -ne 0 ]; then
  echo "Phase 10 platform stdout:" >&2
  cat "$work/platform.stdout" >&2
  echo "Phase 10 platform stderr:" >&2
  cat "$work/platform.stderr" >&2
  fail "platform recipe exited with status $platform_status"
fi
actual_os=$(sed -n '1p' "$work/platform.stdout" | tr -d '\r')
[ "$actual_os" = "$expected_os" ] || fail "reported OS '$actual_os', expected '$expected_os'"
actual_arch=$(sed -n '2p' "$work/platform.stdout" | tr -d '\r')
[ -n "$actual_arch" ] && [ "$actual_arch" != unknown ] || fail "reported architecture is empty or unknown"

(cd "$work" && printf 'yes\n' | "$cli" confirm >confirm.stdout 2>confirm.stderr)
tr -d '\r' <"$work/confirm.stdout" | grep -qx 'phase10-confirm' || fail "affirmative confirmation did not execute"
grep -q 'Run phase 10?' "$work/confirm.stderr" || fail "confirmation prompt was not written to stderr"

if (cd "$work" && printf 'no\n' | "$cli" confirm >deny.stdout 2>deny.stderr); then
  fail "negative confirmation executed"
fi
[ ! -s "$work/deny.stdout" ] || fail "negative confirmation produced recipe output"
grep -q 'was not confirmed' "$work/deny.stderr" || fail "negative confirmation lacks a typed error"

if (cd "$work" && "$cli" confirm </dev/null >eof.stdout 2>eof.stderr); then
  fail "confirmation EOF was accepted"
fi
grep -q 'was not confirmed' "$work/eof.stderr" || fail "confirmation EOF did not terminate predictably"

(cd "$work" && "$cli" --yes confirm >yes.stdout 2>yes.stderr)
tr -d '\r' <"$work/yes.stdout" | grep -qx 'phase10-confirm' || fail "--yes did not bypass the prompt"
! grep -q 'Run phase 10?' "$work/yes.stderr" || fail "--yes still emitted a prompt"

(cd "$work" && "$cli" script >script.stdout 2>script.stderr)
tr -d '\r' <"$work/script.stdout" | grep -qx 'phase10-script' || fail "platform script did not execute"

(cd "$work" && NO_COLOR=1 TERM=xterm-256color "$cli" --list --color auto >auto.stdout)
if LC_ALL=C grep -q $'\033' "$work/auto.stdout"; then
  fail "NO_COLOR/non-TTY list output contains ANSI escapes"
fi
(cd "$work" && "$cli" --list --color always >always.stdout)
LC_ALL=C grep -q $'\033' "$work/always.stdout" || fail "forced-color list output lacks ANSI escapes"

if [ "$expected_os" = windows ]; then
  (cd "$work" && "$cli" cmd-probe >cmd.stdout 2>cmd.stderr)
  tr -d '\r' <"$work/cmd.stdout" | grep -qx 'phase10-cmd' || fail "cmd.exe recipe did not execute"
  set +e
  (cd "$work" && "$cli" fail >fail.stdout 2>fail.stderr)
  status=$?
  set -e
  [ "$status" -eq 7 ] || fail "PowerShell exit status was $status instead of 7"
else
  (cd "$work" && VISUAL=true "$cli" --edit)
  (cd "$work" && "$cli" --choose --chooser "sed -n '1p'" >choose.stdout 2>choose.stderr)
  grep -qx 'phase10-choice' "$work/choose.stdout" || fail "chooser selection was not executed independently"
fi

echo "Phase 10 platform gate passed ($expected_os/$actual_arch, Native CLI, non-TTY, interactive)"
