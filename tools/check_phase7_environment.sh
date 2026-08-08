#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
oracle="$repo_root/_build/upstream/just-1.57.0/target/release/just"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-environment.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT HUP INT TERM
scratch=$(CDPATH='' cd -- "$scratch" && pwd -P)
artifacts="$scratch/artifacts"
project="$scratch/project"
mkdir -p "$artifacts" "$project/custom-temp"

fail() {
  echo "Phase 7 environment differential failed: $1" >&2
  exit 1
}

"$repo_root/tools/upstream/build_oracle.sh" >/dev/null
moon build --quiet --target native tools/phase7_environment_probe
probe="$repo_root/_build/native/debug/build/tools/phase7_environment_probe/phase7_environment_probe.exe"
[ -x "$oracle" ] || fail "upstream oracle is missing"
[ -x "$probe" ] || fail "candidate probe is missing"

printf "value := 'default'\ndefault:\n  @echo {{value}}\n" >"$project/justfile"
(
  cd "$project"
  "$oracle" --set value first --set value overridden
) >"$artifacts/set.oracle" 2>"$artifacts/set.stderr"
"$probe" set >"$artifacts/set.candidate"
cmp -s "$artifacts/set.oracle" "$artifacts/set.candidate" || {
  diff -u "$artifacts/set.oracle" "$artifacts/set.candidate" || true
  fail "--set last-wins behavior differs"
}
[ ! -s "$artifacts/set.stderr" ] || fail "--set emitted stderr"

shell_probe="$scratch/shell-probe"
cat >"$shell_probe" <<'EOF'
#!/bin/sh
while [ "$#" -gt 1 ]; do
  printf '%s\n' "$1"
  shift
done
EOF
chmod +x "$shell_probe"
printf 'default:\n  @:\n' >"$project/justfile"

compare_shell() {
  name=$1
  shift
  (
    cd "$project"
    "$oracle" --shell "$shell_probe" "$@"
  ) >"$artifacts/$name.oracle" 2>"$artifacts/$name.stderr"
  "$probe" "$name" >"$artifacts/$name.candidate"
  cmp -s "$artifacts/$name.oracle" "$artifacts/$name.candidate" || {
    diff -u "$artifacts/$name.oracle" "$artifacts/$name.candidate" || true
    fail "$name shell argument order differs"
  }
  [ ! -s "$artifacts/$name.stderr" ] || fail "$name emitted stderr"
}

compare_shell shell-two --shell-arg one --shell-arg two
compare_shell shell-clear --shell-arg ignored --clear-shell-args
compare_shell shell-reset --clear-shell-args --shell-arg last

cat >"$project/justfile" <<'EOF'
default:
  #!/bin/sh
  dirname "$(dirname "$0")"
EOF
(
  cd "$project"
  "$oracle" --tempdir custom-temp
) >"$artifacts/tempdir.oracle" 2>"$artifacts/tempdir.stderr"
"$probe" tempdir "$project" >"$artifacts/tempdir.candidate"
cmp -s "$artifacts/tempdir.oracle" "$artifacts/tempdir.candidate" || {
  diff -u "$artifacts/tempdir.oracle" "$artifacts/tempdir.candidate" || true
  fail "temporary directory precedence differs"
}
[ ! -s "$artifacts/tempdir.stderr" ] || fail "tempdir emitted stderr"

cat >"$project/.env" <<'EOF'
DOTENV=dotenv
ORDER=dotenv
EOF
cat >"$project/justfile" <<'EOF'
set dotenv-load
unexport REMOVED
export EXPORTED := 'exported'
export ORDER := 'exported'

[env('RECIPE', 'recipe'), env('ORDER', 'recipe')]
default $PARAM:
  @printf '%s\n' "$AMBIENT|$DOTENV|$EXPORTED|$PARAM|$RECIPE|$ORDER|${REMOVED-unset}"
EOF
(
  cd "$project"
  AMBIENT=ambient ORDER=ambient REMOVED=ambient "$oracle" default argument
) >"$artifacts/precedence.oracle" 2>"$artifacts/precedence.stderr"
"$probe" precedence >"$artifacts/precedence.candidate"
cmp -s "$artifacts/precedence.oracle" "$artifacts/precedence.candidate" || {
  diff -u "$artifacts/precedence.oracle" "$artifacts/precedence.candidate" || true
  fail "process environment precedence differs"
}
[ ! -s "$artifacts/precedence.stderr" ] || {
  sed -n '1,20p' "$artifacts/precedence.stderr" >&2
  fail "environment precedence emitted stderr"
}

echo "Phase 7 environment differential passed (7 cases against just 1.57.0)"
