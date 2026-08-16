#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
oracle="$repo_root/_build/upstream/just-1.57.0/target/release/just"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-workdir.XXXXXX")
repo_relative="_build/workdir-cli.$$"
repo_fixture="$repo_root/$repo_relative"
trap 'rm -rf -- "$scratch" "$repo_fixture"' EXIT HUP INT TERM
scratch=$(CDPATH='' cd -- "$scratch" && pwd -P)
fixture="$scratch/fixture"
artifacts="$scratch/artifacts"

fail() {
  echo "Working-directory differential failed: $1" >&2
  exit 1
}

"$repo_root/tools/upstream/build_oracle.sh" >/dev/null
moon build --quiet --target native tools/workdir_probe
probe="$repo_root/_build/native/debug/build/tools/workdir_probe/workdir_probe.exe"
moon build --quiet --target native cmd/just
moon build --quiet --target wasm cmd/just
native="$repo_root/_build/native/debug/build/cmd/just/just.exe"
wasm="$repo_root/_build/wasm/debug/build/cmd/just/just.wasm"
policy="$repo_root/policies/inspect.toml"
[ -x "$oracle" ] || fail "upstream oracle is missing"
[ -x "$probe" ] || fail "candidate probe is missing"
[ -x "$native" ] || fail "Native CLI is missing"
[ -f "$wasm" ] || fail "Wasm CLI is missing"
mkdir -p "$fixture/inv" "$artifacts"
mkdir -p "$repo_fixture/config" "$repo_fixture/run"

compare() {
  name=$1
  shift
  (
    cd "$fixture/inv"
    "$oracle" "$@"
  ) >"$artifacts/$name.oracle" 2>"$artifacts/$name.stderr"
  "$probe" "$fixture" "$name" >"$artifacts/$name.candidate"
  cmp -s "$artifacts/$name.oracle" "$artifacts/$name.candidate" || {
    diff -u "$artifacts/$name.oracle" "$artifacts/$name.candidate" || true
    fail "$name cwd differs"
  }
  [ ! -s "$artifacts/$name.stderr" ] || {
    sed -n '1,20p' "$artifacts/$name.stderr" >&2
    fail "$name emitted stderr"
  }
}

printf 'default:\n  @pwd -P\n' >"$fixture/justfile"
compare project

printf '[no-cd]\ndefault:\n  @pwd -P\n' >"$fixture/justfile"
compare no-cd

mkdir -p "$fixture/build"
printf "set working-directory := 'build'\n\ndefault:\n  @pwd -P\n" >"$fixture/justfile"
compare setting

mkdir -p "$fixture/build/release"
printf "set working-directory := 'build'\n\n[working-directory('release')]\ndefault:\n  @pwd -P\n" >"$fixture/justfile"
compare setting-attribute

mkdir -p "$fixture/release"
printf "set no-cd := true\n\n[working-directory('release')]\ndefault:\n  @pwd -P\n" >"$fixture/justfile"
compare attribute-over-no-cd

mkdir -p "$fixture/includes"
printf "import 'includes/tasks.just'\n" >"$fixture/justfile"
printf 'task:\n  @pwd -P\n' >"$fixture/includes/tasks.just"
compare import task

mkdir -p "$fixture/modules/release"
printf "mod release 'modules/release/mod.just'\n" >"$fixture/justfile"
printf 'task:\n  @pwd -P\n' >"$fixture/modules/release/mod.just"
compare module release task

mkdir -p "$fixture/link/sub"
printf 'default:\n  @pwd -P\n' >"$fixture/source.just"
ln -s ../source.just "$fixture/link/justfile"
(
  cd "$fixture/link/sub"
  "$oracle"
) >"$artifacts/symlink.oracle" 2>"$artifacts/symlink.stderr"
"$probe" "$fixture" symlink >"$artifacts/symlink.candidate"
cmp -s "$artifacts/symlink.oracle" "$artifacts/symlink.candidate" || {
  diff -u "$artifacts/symlink.oracle" "$artifacts/symlink.candidate" || true
  fail "symlink cwd differs"
}
[ ! -s "$artifacts/symlink.stderr" ] || {
  sed -n '1,20p' "$artifacts/symlink.stderr" >&2
  fail "symlink emitted stderr"
}

mkdir -p "$fixture/config" "$fixture/run"
printf 'default:\n  @pwd -P\n' >"$fixture/config/justfile"
compare cli-override --justfile "$fixture/config/justfile" --working-directory "$fixture/run"
printf 'default:\n  @pwd -P\n' >"$repo_fixture/config/justfile"

for target in oracle native wasm; do
  case "$target" in
    oracle) command="$oracle" ;;
    native) command="$native" ;;
    wasm) command="moonrun" ;;
  esac
  if [ "$target" = wasm ]; then
    (
      cd "$repo_root"
      "$command" --policy "$policy" "$wasm" \
        --summary \
        --justfile "$repo_relative/config/justfile" \
        --working-directory "$repo_relative/run"
    ) >"$artifacts/cli-$target.stdout" 2>"$artifacts/cli-$target.stderr"
  else
    (
      cd "$repo_root"
      "$command" \
        --summary \
        --justfile "$repo_relative/config/justfile" \
        --working-directory "$repo_relative/run"
    ) >"$artifacts/cli-$target.stdout" 2>"$artifacts/cli-$target.stderr"
  fi
done
for target in native wasm; do
  cmp -s "$artifacts/cli-oracle.stdout" "$artifacts/cli-$target.stdout" || {
    diff -u "$artifacts/cli-oracle.stdout" "$artifacts/cli-$target.stdout" || true
    fail "$target relative -f/-d stdout differs"
  }
  cmp -s "$artifacts/cli-oracle.stderr" "$artifacts/cli-$target.stderr" || {
    diff -u "$artifacts/cli-oracle.stderr" "$artifacts/cli-$target.stderr" || true
    fail "$target relative -f/-d stderr differs"
  }
done

echo "Working-directory differential passed (9 model and 2 Native/Wasm CLI cases against just 1.57.0)"
