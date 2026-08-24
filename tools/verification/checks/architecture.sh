#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
core_packages="source diagnostic path host cli lexer syntax parser formatter semantic loader value builtin evaluator environment invocation workdir scheduler cache executor application"
async_packages="loader evaluator executor application"
# Loader and application keep a stable async API while selecting the already
# verified synchronous Native implementation. Target selection is allowed only
# in these capability-boundary packages; native imports and extern declarations
# remain forbidden here.
target_specialized_packages="loader application"

fail() {
  echo "architecture boundary error: $1" >&2
  exit 1
}

for file in "$repo_root/tools"/*; do
  [ -f "$file" ] || continue
  case "$(basename "$file")" in
    README.md|runner.py) ;;
    *) fail "unexpected file at tools root: $(basename "$file")" ;;
  esac
done

for directory in differential oracles probes quality release spikes upstream verification; do
  [ -d "$repo_root/tools/$directory" ] || fail "missing tools/$directory directory"
done
[ -d "$repo_root/tools/verification/checks" ] || fail "missing tools/verification/checks directory"
[ -d "$repo_root/tools/verification/benchmarks" ] || fail "missing tools/verification/benchmarks directory"

for file in "$repo_root"/*.mbt "$repo_root"/*.mbti "$repo_root/moon.pkg"; do
  [ -e "$file" ] || continue
  fail "MoonBit package file must live below the repository root: $(basename "$file")"
done

[ -f "$repo_root/api/moon.pkg" ] || fail "missing api/moon.pkg"
[ -f "$repo_root/api/pkg.generated.mbti" ] || \
  fail "missing api/pkg.generated.mbti"
if grep -n 'ZSeanYves/MoonJust/src/' \
  "$repo_root/api/pkg.generated.mbti"; then
  fail "stable API interface leaks an src package type"
fi

for package in $core_packages; do
  package_dir="$repo_root/src/$package"
  [ -f "$package_dir/moon.pkg" ] || fail "missing src/$package/moon.pkg"
  [ -f "$package_dir/pkg.generated.mbti" ] || \
    fail "missing src/$package/pkg.generated.mbti"

  for file in "$package_dir"/*.mbt "$package_dir/moon.pkg"; do
    [ -f "$file" ] || continue
    if [ "$(basename "$file")" = "moon.pkg" ]; then
      production_imports=$(awk '
        /^import \{/ { in_import=1; block=$0 "\\n"; next }
        in_import {
          block=block $0 "\\n"
          if ($0 ~ /^}/) {
            if ($0 !~ /for "test"/ && block ~ /native-stub/) print block
            in_import=0
          }
          next
        }
      ' "$file")
      if [ -n "$production_imports" ]; then
        printf '%s\n' "$production_imports"
        fail "target-specific implementation found in src/$package"
      fi
      async_imports=$(awk '
        /^import \{/ { in_import=1; block=$0 "\\n"; next }
        in_import {
          block=block $0 "\\n"
          if ($0 ~ /^}/) {
            if ($0 !~ /for "test"/ && block ~ /moonbitlang\/async/) print block
            in_import=0
          }
          next
        }
      ' "$file")
      case " $async_packages " in
        *" $package "*) ;;
        *)
          if [ -n "$async_imports" ]; then
            printf '%s\n' "$async_imports"
            fail "async runtime dependency found in src/$package"
          fi
          ;;
      esac
    elif grep -nE \
      '#cfg|#external|extern[[:space:]]+"|native-stub' \
      "$file"; then
      case " $target_specialized_packages " in
        *" $package "*)
          if grep -nE '#external|extern[[:space:]]+"|native-stub' "$file"; then
            fail "native target implementation found in src/$package"
          fi
          ;;
        *) fail "target-specific implementation found in src/$package" ;;
      esac
    fi
    if [ "$package" != host ] && [ "$package" != loader ] && \
      [ "$package" != evaluator ] && \
      [ "$package" != executor ] && [ "$package" != application ] && \
      grep -nE 'async[[:space:]]+fn' "$file"; then
      fail "async implementation found in src/$package"
    fi
  done
done

for package in loader evaluator executor application; do
  if grep -nE 'moonbitlang/async|#external|extern[[:space:]]+"' \
    "$repo_root/src/$package"/*.mbt; then
    fail "src/$package async capability API imports a runtime or target implementation"
  fi
done

pure_packages="source diagnostic path cli lexer syntax parser formatter semantic value builtin invocation workdir scheduler cache"
for package in $pure_packages; do
  if grep -nE 'src/host(_native|_wasm)?' "$repo_root/src/$package/moon.pkg"; then
    fail "src/$package imports a host package"
  fi
done

if grep -nE 'src/host_(native|wasm)' "$repo_root/src/host/moon.pkg"; then
  fail "host contracts import a concrete host adapter"
fi

abort_hits=$(find "$repo_root/src" "$repo_root/api" "$repo_root/cmd" \
  -type f -name '*.mbt' ! -name '*_test.mbt' ! -name '*_wbtest.mbt' \
  -exec grep -nHF 'abort(' {} + || true)
if [ -n "$abort_hits" ]; then
  printf '%s\n' "$abort_hits"
  fail "production MoonBit code contains an abort path"
fi

orphan_process_hits=$(find "$repo_root/src" "$repo_root/api" "$repo_root/cmd" \
  -type f -name '*.mbt' ! -name '*_test.mbt' ! -name '*_wbtest.mbt' \
  -exec grep -nHE '@process\.(spawn_orphan|wait_pid)' {} + || true)
if [ -n "$orphan_process_hits" ]; then
  printf '%s\n' "$orphan_process_hits"
  fail "production process adapters must use async structured concurrency"
fi

[ -f "$repo_root/src/host_native/moon.pkg" ] || fail "missing native host adapter package"
[ -f "$repo_root/src/host_native/pkg.generated.mbti" ] || fail "missing native host adapter interface"
if grep -nE 'src/(semantic|evaluator|builtin|parser|formatter)' "$repo_root/src/host_native/moon.pkg"; then
  fail "native host adapter imports core implementation packages"
fi

[ -f "$repo_root/src/host_wasm/moon.pkg" ] || fail "missing Wasm host adapter package"
[ -f "$repo_root/src/host_wasm/pkg.generated.mbti" ] || fail "missing Wasm host adapter interface"
if grep -nE 'Host(Process|Env|Clock|Random|Terminal|Signal|AsyncScriptTemp)|write_bytes_to_file' \
  "$repo_root/src/host_wasm/read_only.mbt"; then
  fail "Wasm inspect adapter exposes a forbidden capability"
fi
grep -Eq '^write = \[\]$' "$repo_root/policies/inspect.toml" || \
  fail "Wasm inspect policy grants filesystem writes"
grep -Eq '^spawn = false$' "$repo_root/policies/inspect.toml" || \
  fail "Wasm inspect policy grants process spawn"

transaction_dir="$repo_root/src/host_wasm/transaction"
[ -f "$transaction_dir/moon.pkg" ] || fail "missing Wasm transaction adapter package"
grep -Eq '^supported_targets = "-all\+wasm"$' "$transaction_dir/moon.pkg" || \
  fail "Wasm transaction adapter is not wasm1-only"
if grep -nE 'Host(Process|Env|Clock|Terminal|Signal)|wasi_snapshot_preview1' \
  "$transaction_dir"/*.mbt "$transaction_dir/moon.pkg"; then
  fail "Wasm transaction adapter crosses its capability boundary"
fi

set -- $core_packages
echo "architecture boundaries verified for $# core packages and host adapter leaves"
