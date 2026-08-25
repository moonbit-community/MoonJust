#!/usr/bin/env bash
set -euo pipefail

attempts="${MOON_UPDATE_ATTEMPTS:-5}"
base_delay="${MOON_UPDATE_RETRY_DELAY:-10}"

for ((attempt = 1; attempt <= attempts; attempt++)); do
  if moon update; then
    exit 0
  fi
  if ((attempt < attempts)); then
    sleep "$((base_delay * attempt))"
  fi
done

echo "moon update failed after ${attempts} attempts" >&2
exit 1
