#!/usr/bin/env bash
# release-readiness — say whether this repository is ready to release,
# and report the version the automatic path would derive.
#
# Run it before dispatching. Every check here reads and none writes: it
# does not clean the tree, move a pin, or rewrite a literal. A primitive
# that mutates on the way to reporting cannot be run to ask a question,
# and cannot be composed by anything that has not already decided to act.
#
# That rule is why `mise run check-all` is absent. Composing it looks
# obvious, and it would have made this script a writer: check-all reaches
# `tidy`, which is `go mod tidy`, so a passing run could leave go.mod and
# go.sum rewritten. The comprehensive gate arrives instead through the
# checks-green probe below, which asks GitHub what those same gates
# concluded about this exact commit. That answer is the better one
# anyway, since it came from a clean runner on every platform in the
# matrix rather than from whatever this machine happens to hold. Run
# `mise run check-all` by hand where a local sweep is what you want.
#
# The derived version is the part worth reading even on a green run.
# Cog computes a bump from Conventional Commit types, so a run of fixes
# and chores yields a patch where a minor was intended. #25 exists
# because that difference went unnoticed until after the tag. Printing
# it here is the cheapest place to catch it, and it stays informational:
# nothing in this repository knows which version the operator wants.
#
# Checks run cheapest first, so a verdict a dirty tree already settled
# costs no network call to reach.
#
# Findings print one per line and the exit code carries the verdict, so
# a wrapper can branch on it and CI can run it unattended.
#
# Usage: release-readiness.sh
set -euo pipefail

export LC_ALL=C
export GH_PAGER=cat
export GH_PROMPT_DISABLED=1
unset CDPATH GH_REPO GH_HOST GREP_OPTIONS
IFS=$' \t\n'

root=$(command git rev-parse --show-toplevel)
cd "$root"

# release.yml pushes to main and nothing else, so a release cut from
# any other branch would push a tag onto commits main has never seen.
readonly RELEASE_BRANCH=main

failures=0
ok() { printf 'OK    %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  [ $# -lt 2 ] || printf '      %s\n' "$2"
  failures=$((failures + 1))
}

# --- On the release branch ---

branch=$(command git rev-parse --abbrev-ref HEAD)
if [ "$branch" = "$RELEASE_BRANCH" ]; then
  ok "on $RELEASE_BRANCH"
else
  fail "on $RELEASE_BRANCH" "HEAD is on $branch; release.yml bumps and pushes $RELEASE_BRANCH"
fi

# --- Clean working tree ---

dirty=$(command git status --porcelain)
if [ -z "$dirty" ]; then
  ok "working tree clean"
else
  fail "working tree clean" "$(printf '%s' "$dirty" | tr '\n' ' ')"
fi

# --- Current with the remote ---
#
# ls-remote rather than a fetch. Reading the remote answers the question
# without writing a remote-tracking ref, which keeps this task read-only
# in the sense that matters: run it twice and the repository is the same
# either way.

local_head=$(command git rev-parse HEAD)
remote_head=$(command git ls-remote origin "refs/heads/$RELEASE_BRANCH" | cut -f1)
if [ -z "$remote_head" ]; then
  fail "current with origin/$RELEASE_BRANCH" "origin has no $RELEASE_BRANCH"
elif [ "$local_head" = "$remote_head" ]; then
  ok "current with origin/$RELEASE_BRANCH"
else
  fail "current with origin/$RELEASE_BRANCH" "HEAD is $local_head, origin has $remote_head"
fi

# --- Version literals ---

if literals=$(bash tools/check-versions.sh 2>&1); then
  ok "version literals name the latest tag"
else
  fail "version literals name the latest tag" "$(printf '%s' "$literals" | tr '\n' ' ')"
fi

# --- Checks green on HEAD ---
#
# A commit with no check runs is a failure rather than a pass. The bump
# commit itself is deliberately skipped by CI, so "nothing reported" is
# a state this repository really produces, and reading it as green would
# release whatever the last skipped commit left behind.

# Separating the failed call from the empty answer matters more than it
# looks. gh prints an error response body on stdout rather than stderr,
# so collapsing the two arms puts a raw JSON blob where the finding text
# belongs, and the commonest cause of that call failing is the ordinary
# one of asking about a commit nobody has pushed.
if ! runs=$(gh api "repos/{owner}/{repo}/commits/$local_head/check-runs" \
  --jq '.check_runs[] | "\(.conclusion // "pending") \(.name)"' 2>/dev/null); then
  fail "checks green on HEAD" "the check-runs API had no answer for $local_head; a commit nobody has pushed is the usual cause"
elif [ -z "$runs" ]; then
  fail "checks green on HEAD" "no check runs reported for $local_head"
else
  bad=$(printf '%s\n' "$runs" | grep -vE '^(success|skipped|neutral) ' || true)
  if [ -z "$bad" ]; then
    ok "checks green on HEAD"
  else
    fail "checks green on HEAD" "$(printf '%s' "$bad" | tr '\n' '; ')"
  fi
fi

# --- The changelog previews ---

if preview=$(mise run preview-changelog 2>&1) && [ -n "$preview" ]; then
  ok "the changelog previews"
else
  fail "the changelog previews" "mise run preview-changelog produced nothing usable"
fi

# --- The version the automatic path would derive ---
#
# Informational rather than a gate. Cog reads the commit types since the
# last tag, and the operator may well want a different number; passing
# one to release-repotools is how they say so.

# Cog refuses a dirty tree, so this reports its own reason rather than a
# bare nothing. The clean-tree check above already covers the usual
# cause, and repeating it here beats leaving the operator to guess which
# of the two lines explains the other.
if derived=$(cog bump --auto --dry-run 2>&1) && [ -n "$derived" ]; then
  printf 'INFO  cog bump --auto would derive %s\n' "$derived"
else
  printf 'INFO  cog bump --auto derived nothing: %s\n' "$(printf '%s' "$derived" | tr '\n' ' ')"
fi

if [ "$failures" -gt 0 ]; then
  printf 'NOT READY: %s check(s) failed\n' "$failures"
  exit 1
fi

printf 'READY\n'
