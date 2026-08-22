#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-platform.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

fail() {
  echo "Platform gate failed: $1" >&2
  exit 1
}

moon test --target native internal/host
moon test --target native internal/host_native
moon test --target native internal/host_process
moon test --target native internal/environment
moon test --target native internal/executor
moon test --target native internal/application
if [ -z "${MOONJUST_NATIVE_CANDIDATE:-}" ]; then moon build cmd/just --target native >/dev/null; fi
cli="${MOONJUST_NATIVE_CANDIDATE:-$repo_root/_build/native/debug/build/cmd/just/just.exe}"
[ -x "$cli" ] || [ -f "$cli" ] || fail "Native CLI artifact is missing"

runner_os=$(uname -s)
windows_runner=0
case "$runner_os" in
  MINGW*|MSYS*|CYGWIN*) windows_runner=1 ;;
esac

run_cli() {
  local label=$1
  shift
  if [ "$windows_runner" -eq 1 ]; then
    python3 "$repo_root/tools/verification/probe.py" \
      --cwd "$PWD" --label "$label" --timeout 60 -- "$cli" "$@"
  else
    echo "platform probe: $label" >&2
    "$cli" "$@"
  fi
}

case "$runner_os" in
  MINGW*|MSYS*|CYGWIN*)
    expected_os=windows
    cat >"$work/justfile" <<'EOF'
set windows-shell := ['cmd.exe', '/D', '/C']

[confirm('Run platform?')]
confirm:
  echo platform-confirm

alpha:
  echo platform-choice

cmd-probe:
  echo platform-cmd

# `platform` platform probe
platform:
  echo {{os()}}
  echo {{arch()}}

fail:
  exit /B 7

script:
  echo platform-script
EOF
    ;;
  Darwin)
    expected_os=macos
    cat >"$work/justfile" <<'EOF'
[confirm('Run platform?')]
confirm:
  echo platform-confirm

alpha:
  echo platform-choice

# `platform` platform probe
platform:
  echo {{os()}}
  echo {{arch()}}

[script]
script:
  #!/bin/sh
  echo platform-script
EOF
    ;;
  Linux)
    expected_os=linux
    cat >"$work/justfile" <<'EOF'
[confirm('Run platform?')]
confirm:
  echo platform-confirm

alpha:
  echo platform-choice

# `platform` platform probe
platform:
  echo {{os()}}
  echo {{arch()}}

[script]
script:
  #!/bin/sh
  echo platform-script
EOF
    ;;
  *) fail "unsupported runner operating system: $(uname -s)" ;;
esac

set +e
(cd "$work" && run_cli platform platform >platform.stdout 2>platform.stderr)
platform_status=$?
set -e
if [ "$platform_status" -ne 0 ]; then
  echo "Platform stdout:" >&2
  cat "$work/platform.stdout" >&2
  echo "Platform stderr:" >&2
  cat "$work/platform.stderr" >&2
  echo "Platform configuration:" >&2
  (cd "$work" && run_cli dump --dump) >&2 || true
  echo "Platform dry-run:" >&2
  (cd "$work" && run_cli dry-run --verbose --dry-run platform) >&2 || true
  if [ "$expected_os" = windows ]; then
    echo "Windows cmd recipe execution:" >&2
    (cd "$work" && run_cli cmd-probe --verbose cmd-probe) >&2 || true
    echo "Platform verbose execution:" >&2
    (cd "$work" && run_cli verbose-platform --verbose platform) >&2 || true
    echo "Static script execution:" >&2
    (cd "$work" && run_cli verbose-script --verbose script) >&2 || true
    cat >"$work/justfile-absolute" <<'EOF'
set script-interpreter := ['C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe', '-NoLogo', '-NoProfile', '-File']

[script]
platform:
  Write-Output platform-absolute
EOF
    echo "Absolute PowerShell recipe execution:" >&2
    (cd "$work" && run_cli absolute-platform --verbose --justfile justfile-absolute platform) >&2 || true
    cat >"$work/direct.ps1" <<'EOF'
Write-Output platform-direct-file
EOF
    echo "Direct PowerShell execution:" >&2
    powershell.exe -NoLogo -NoProfile -Command \
      'Write-Output platform-direct-command' >&2 || true
    powershell.exe -NoLogo -NoProfile -File "$work/direct.ps1" >&2 || true
    echo "Windows executable resolution:" >&2
    for executable in cmd.exe powershell.exe sh.exe bash.exe; do
      where.exe "$executable" >&2 || true
    done
  fi
  fail "platform recipe exited with status $platform_status"
fi
actual_os=$(sed -n '1p' "$work/platform.stdout" | tr -d '\r')
[ "$actual_os" = "$expected_os" ] || fail "reported OS '$actual_os', expected '$expected_os'"
actual_arch=$(sed -n '2p' "$work/platform.stdout" | tr -d '\r')
[ -n "$actual_arch" ] && [ "$actual_arch" != unknown ] || fail "reported architecture is empty or unknown"

(cd "$work" && printf 'yes\n' | run_cli confirm-yes confirm >confirm.stdout 2>confirm.stderr)
tr -d '\r' <"$work/confirm.stdout" | grep -qx 'platform-confirm' || fail "affirmative confirmation did not execute"
grep -q 'Run platform?' "$work/confirm.stderr" || fail "confirmation prompt was not written to stderr"

if (cd "$work" && printf 'no\n' | run_cli confirm-no confirm >deny.stdout 2>deny.stderr); then
  fail "negative confirmation executed"
fi
[ ! -s "$work/deny.stdout" ] || fail "negative confirmation produced recipe output"
grep -q 'was not confirmed' "$work/deny.stderr" || fail "negative confirmation lacks a typed error"

if (cd "$work" && run_cli confirm-eof confirm </dev/null >eof.stdout 2>eof.stderr); then
  fail "confirmation EOF was accepted"
fi
grep -q 'was not confirmed' "$work/eof.stderr" || fail "confirmation EOF did not terminate predictably"

(cd "$work" && run_cli yes --yes confirm >yes.stdout 2>yes.stderr)
tr -d '\r' <"$work/yes.stdout" | grep -qx 'platform-confirm' || fail "--yes did not bypass the prompt"
! grep -q 'Run platform?' "$work/yes.stderr" || fail "--yes still emitted a prompt"

(cd "$work" && JUST_YES=1 run_cli env-yes confirm </dev/null >env-yes.stdout 2>env-yes.stderr)
tr -d '\r' <"$work/env-yes.stdout" | grep -qx 'platform-confirm' || fail "JUST_YES did not bypass the prompt"
! grep -q 'Run platform?' "$work/env-yes.stderr" || fail "JUST_YES still emitted a prompt"

printf 'stdin-env:\n  echo platform-stdin-env\n' | (cd "$work" && JUST_JUSTFILE=- run_cli stdin-env stdin-env >env-stdin.stdout 2>env-stdin.stderr)
tr -d '\r' <"$work/env-stdin.stdout" | grep -qx 'platform-stdin-env' || fail "JUST_JUSTFILE=- did not read stdin"

(cd "$work" && JUST_JUSTFILE=- run_cli env-override --justfile justfile alpha </dev/null >env-override.stdout 2>env-override.stderr)
tr -d '\r' <"$work/env-override.stdout" | grep -qx 'platform-choice' || fail "argv justfile did not override JUST_JUSTFILE"
(cd "$work" && JUST_ALLOW_MISSING=1 JUST_DRY_RUN=1 JUST_QUIET=1 run_cli env-version --version </dev/null >env-version.stdout 2>env-version.stderr)
grep -q '^moonjust 0.7.0-alpha.1' "$work/env-version.stdout" || fail "--version did not override unsupported environment diagnostics"

(cd "$work" && run_cli script script >script.stdout 2>script.stderr)
tr -d '\r' <"$work/script.stdout" | grep -qx 'platform-script' || fail "platform script did not execute"

(cd "$work" && NO_COLOR=1 TERM=xterm-256color run_cli list-auto --list --color auto >auto.stdout)
if LC_ALL=C grep -q $'\033' "$work/auto.stdout"; then
  fail "NO_COLOR/non-TTY list output contains ANSI escapes"
fi
(cd "$work" && run_cli list-always --list --color always >always.stdout)
LC_ALL=C grep -q $'\033' "$work/always.stdout" || fail "forced-color list output lacks ANSI escapes"

if [ "$expected_os" = windows ]; then
  (cd "$work" && run_cli cmd-probe-final cmd-probe >cmd.stdout 2>cmd.stderr)
  tr -d '\r' <"$work/cmd.stdout" | grep -qx 'platform-cmd' || fail "cmd.exe recipe did not execute"
  set +e
  (cd "$work" && run_cli fail fail >fail.stdout 2>fail.stderr)
  status=$?
  set -e
  [ "$status" -eq 7 ] || fail "PowerShell exit status was $status instead of 7"
else
  (cd "$work" && VISUAL=true run_cli edit --edit)
  (cd "$work" && run_cli choose --choose --chooser "sed -n '1p'" >choose.stdout 2>choose.stderr)
  grep -qx 'platform-choice' "$work/choose.stdout" || fail "chooser selection was not executed independently"
fi

echo "Platform gate passed ($expected_os/$actual_arch, Native CLI, non-TTY, interactive)"
