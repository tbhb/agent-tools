#!/usr/bin/env bash
# Run native Go fuzz targets under the path in $1 (default the whole
# module). go test -fuzz takes one target regexp per invocation, so this
# lists every Fuzz* function under each package below the path and runs
# them one at a time for the FUZZ_TIME budget (default 30s). Seed-corpus
# failures fail the script, and new crashers land under each package's
# testdata/fuzz/.
#
# The `just fuzz` recipe and the fuzz-nightly workflow both call this
# script; the workflow raises FUZZ_TIME for a longer scheduled sweep,
# mirroring the gremlins / mutate-all shape where one entry point powers
# both the inner loop and the scheduled run.
set -euo pipefail

path="${1:-./...}"
fuzz_time="${FUZZ_TIME:-30s}"

found=0
for pkg in $(go list "$path"); do
  targets=$(go test -list '^Fuzz' "$pkg" 2>/dev/null | grep -E '^Fuzz' || true)
  [[ -z "$targets" ]] && continue
  while IFS= read -r target; do
    echo "==> $pkg $target"
    go test -run='^$' -fuzz="^${target}$" -fuzztime="$fuzz_time" "$pkg"
    found=$((found + 1))
  done <<<"$targets"
done

if ((found == 0)); then
  echo "no fuzz targets discovered under $path" >&2
  exit 1
fi
