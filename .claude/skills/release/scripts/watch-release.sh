#!/usr/bin/env bash
# watch-release — emit one line per release step as it settles, then
# exit.
#
# `gh workflow run` returns the moment GitHub accepts the request, long
# before anything is tagged, so a dispatch on its own leaves the release
# in an unknown state. This closes that gap.
#
# Written as an event stream for the Monitor tool, on the same contract
# watch-checks.sh follows:
#
#   * one line per event, flushed as it happens
#   * every terminal state emits, not only the passing one, because a
#     watcher that prints nothing on failure is indistinguishable from a
#     watcher that is still waiting
#   * the command exits once the run stops moving, so the watch ends by
#     itself rather than sitting armed until the timeout
#
# It also works as a plain blocking call, where the exit code carries
# the outcome: 0 the run succeeded, 1 it did not, 2 the wait ran out or
# the run never appeared.
#
# The baseline argument is what makes the run unambiguous. Between the
# dispatch and the run registering, the newest release run is still the
# previous release's, and reading that one would report a success that
# belongs to a tag cut weeks ago. Take the newest run id before
# dispatching, pass it here, and this waits for a different one:
#
#   gh run list --workflow=release.yml --limit 1 --json databaseId \
#     --jq '.[0].databaseId'
#
# Pass `none` where the repository has never run the workflow.
#
# Read-only. It dispatches nothing and never retries a dispatch: a run
# it cannot identify is reported and left alone, because a second
# release is far worse than a stalled one.
#
# Usage: watch-release.sh <baseline-run-id|none>
# Written to bash 3.2.
set -uo pipefail

# --- environment hardening -------------------------------------------
# The agent reads this output, so the operator's preferences must not
# change its shape. LC_ALL pins collation, because sort and the [a-z]
# ranges below mean different things under a UTF-8 locale. The unsets
# cover variables that silently retarget a command: GH_REPO sends gh at
# another repository, CDPATH makes a relative cd print somewhere else.
export LC_ALL=C
export GH_PAGER=cat
export GH_PROMPT_DISABLED=1
export PYTHONUTF8=1
unset CDPATH GH_REPO GH_HOST GREP_OPTIONS
IFS=$' \t\n'

readonly WORKFLOW=release.yml
readonly INTERVAL=${RELEASE_RUN_INTERVAL:-15}
readonly TIMEOUT=${RELEASE_RUN_TIMEOUT:-1800}
readonly APPEAR_TIMEOUT=${RELEASE_RUN_APPEAR_TIMEOUT:-180}

root=$(git rev-parse --show-toplevel)
cd "$root" || exit 2

fail() {
  printf 'ERROR %s\n' "$1"
  exit 2
}

command -v gh >/dev/null 2>&1 || fail "gh is not installed"
command -v jq >/dev/null 2>&1 || fail "jq is not installed"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated"

baseline=${1:-}
[ -n "$baseline" ] || fail "no baseline run id; pass the newest run id from before the dispatch, or 'none'"
[ "$baseline" = "none" ] && baseline=""

newest() {
  gh run list --workflow="$WORKFLOW" --limit 1 \
    --json databaseId,url --jq '.[0] | "\(.databaseId)\t\(.url)"' 2>/dev/null || true
}

# --- Wait for the dispatched run to register -------------------------
#
# GitHub accepts the dispatch before it creates the run, so the first
# few looks legitimately find nothing new.

run_id=""
run_url=""
waited=0
while :; do
  IFS="$(printf '\t')" read -r id url <<EOF
$(newest)
EOF
  if [ -n "${id:-}" ] && [ "$id" != "$baseline" ]; then
    run_id=$id
    run_url=$url
    break
  fi
  if [ "$waited" -ge "$APPEAR_TIMEOUT" ]; then
    printf 'NO RUN registered within %ss of the dispatch\n' "$APPEAR_TIMEOUT"
    printf 'Check by hand before dispatching again: gh run list --workflow=%s\n' "$WORKFLOW"
    exit 2
  fi
  sleep 5
  waited=$((waited + 5))
done

printf 'RELEASE RUN %s  %s\n' "$run_id" "$run_url"

# --- Follow it to a conclusion ---------------------------------------
#
# Per step rather than per job, because release.yml is one job and a job
# granularity would emit a single event at the very end. The steps are
# the interesting boundary anyway: the bump and the signing are separate
# steps, and the signing one is where the workaround this whole release
# convention rests on either holds or does not.

settled_steps() {
  gh run view "$run_id" --json jobs \
    --jq '.jobs[].steps[] | select(.conclusion != null and .conclusion != "") | "\(.conclusion)\t\(.name)"' \
    2>/dev/null || true
}

run_state() {
  gh run view "$run_id" --json status,conclusion \
    --jq '"\(.status)\t\(.conclusion // "")"' 2>/dev/null || true
}

# A seen-set rather than comm, for the reason watch-checks.sh gives:
# comm compares under the collation its locale defines, and a step name
# carrying punctuation can sort one way and compare another, which drops
# a failure line instead of reporting it.
seen=""
elapsed=0
status=""
conclusion=""

while :; do
  while IFS="$(printf '\t')" read -r step_conclusion step_name; do
    [ -n "$step_name" ] || continue
    case "$seen" in
    *"|${step_name}|"*) continue ;;
    esac
    seen="${seen}|${step_name}|"
    case $step_conclusion in
    success) printf 'PASS  %s\n' "$step_name" ;;
    skipped) printf 'SKIP  %s\n' "$step_name" ;;
    *) printf 'FAIL  %s (%s)\n' "$step_name" "$step_conclusion" ;;
    esac
  done <<EOF
$(settled_steps)
EOF

  IFS="$(printf '\t')" read -r status conclusion <<EOF
$(run_state)
EOF

  [ "${status:-}" = "completed" ] && break

  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    printf 'TIMEOUT run %s after %ss, still %s\n' "$run_id" "$TIMEOUT" "${status:-unknown}"
    printf 'The release may still land. Check the run before dispatching again: %s\n' "$run_url"
    exit 2
  fi
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done

if [ "${conclusion:-}" = "success" ]; then
  printf 'RELEASE RUN SUCCEEDED %s\n' "$run_url"
  printf 'Next: git fetch origin --tags, then mise run verify-repotools-release\n'
  exit 0
fi

printf 'RELEASE RUN %s %s\n' "$(printf '%s' "${conclusion:-unknown}" | tr '[:lower:]' '[:upper:]')" "$run_url"
printf 'Nothing was released. Read the run before dispatching again; a second release is worse than a stalled one.\n'
exit 1
