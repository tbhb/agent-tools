#!/usr/bin/env bash
# context — gather what judging a release version needs, in one call.
#
# The reviewer opens holding its material rather than going to look for
# it. That shape came out of measuring the earlier reviewers here: the
# one left to run its own commands spent most of its calls repeating a
# fetch it had already made.
#
# Everything is read out of the release clone rather than out of the
# checkout that invoked the release. The version under discussion is the
# one that would be cut from the release branch, so a commit range taken
# from a local branch would be a range nobody is releasing.
#
# The consumer surface is the part worth explaining. Cog derives a bump
# from Conventional Commit types alone, which is exactly right for a
# change whose type describes its blast radius and exactly wrong for one
# whose type describes its author's intent. A `build:` commit that
# rewrites the vendored task payload reaches every consumer on the next
# sync. Listing which changed paths are published gives the reviewer the
# evidence for that call, since nothing in the commit type carries it.
#
# Read-only, and it prints rather than deciding. The judgement belongs to
# the reviewer reading this.
#
# Usage: context.sh [clone-path]
#   Without an argument it asks release-clone.sh where the clone is.
set -euo pipefail

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

readonly DIFF_LIMIT=${RELEASE_VERSION_DIFF_LIMIT:-200}
readonly BODY_LIMIT=${RELEASE_VERSION_BODY_LIMIT:-10}

die() {
  printf 'context: %s\n' "$1" >&2
  exit 1
}

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
clone=${1:-}
if [ -z "$clone" ]; then
  clone=$(bash "$here/../../release/scripts/release-clone.sh" path) ||
    die "no release clone; run release-clone.sh prepare first"
fi
[ -d "$clone/.git" ] || die "$clone is not a git repository"

cd "$clone"

tag=$(command git describe --tags --abbrev=0 2>/dev/null) ||
  die "no tag reachable from the release branch"
head=$(command git rev-parse --short HEAD)

printf '== the range ==\n'
printf 'release branch at: %s\n' "$head"
printf 'last tag:          %s\n' "$tag"
printf 'commits since:     %s\n' "$(command git rev-list --count "$tag..HEAD")"
printf '\n'

# --- What cog would derive --------------------------------------------
#
# The number under review. Printed first so the reviewer forms its own
# answer against a stated one rather than reconstructing it afterwards.

printf '== what cog derives ==\n'
if derived=$(cog bump --auto --dry-run 2>&1) && [ -n "$derived" ]; then
  printf '%s\n' "$derived"
else
  printf 'cog derived nothing: %s\n' "$(printf '%s' "$derived" | tr '\n' ' ')"
fi
printf '\n'

# --- The commits, in full ---------------------------------------------
#
# Whole messages rather than subjects. A breaking change announces
# itself in a footer or a bang, and a subject list hides both.

# Subjects carry the type, which is what cog read, and the opening of
# each body carries why the change exists, which is what cog could not.
# Beyond that a body argues its own design, and this repository writes
# long ones, so a whole range printed in full buries the two lines that
# decide a version under several thousand that do not.
#
# The bound never hides a declared break. A bang lives in the subject,
# and the footers are pulled out by name from anywhere in the body, so
# the two forms that settle a major on their own always print whatever
# the limit is set to.
printf '== the commits ==\n'
printf '(bodies cut to %s lines; declared breaking footers always shown)\n\n' "$BODY_LIMIT"
while IFS= read -r sha; do
  printf -- '--- %s %s\n' \
    "$(command git log -1 --format=%h "$sha")" \
    "$(command git log -1 --format=%s "$sha")"

  body=$(command git log -1 --format=%b "$sha")
  [ -z "$body" ] || printf '%s\n' "$body" | head -n "$BODY_LIMIT"

  total=$(printf '%s\n' "$body" | wc -l | tr -d ' ')
  [ "$total" -gt "$BODY_LIMIT" ] &&
    printf '    [body cut at %s of %s lines]\n' "$BODY_LIMIT" "$total"

  breaking=$(printf '%s\n' "$body" | grep -E '^(BREAKING[ -]CHANGE|BREAKING)' || true)
  [ -z "$breaking" ] || printf '    DECLARED: %s\n' "$breaking"

  printf '\n'
done < <(command git rev-list --reverse "$tag..HEAD")

# --- The published surface --------------------------------------------
#
# Every path here reaches a consumer directly rather than through this
# repository's own gates, so a change under one of them is visible
# outside no matter which type its commit carried. The list mirrors what
# AGENTS.md describes as published: the APM package, the vendored task
# payload, the commit-msg hooks, the reusable workflows and actions, the
# Renovate presets, and the Go tools consumers install by module path.
printf '== changed paths on the published surface ==\n'
published=$(
  command git diff --name-only "$tag..HEAD" -- \
    '.apm' '.repotools' '.pre-commit-hooks.yaml' \
    '.github/workflows' '.github/actions' \
    'renovate.json' 'renovate' 'cmd' 'internal' 'packages' |
    sort -u
)
if [ -n "$published" ]; then
  printf '%s\n' "$published"
else
  printf '(none: every change is internal to this repository)\n'
fi
printf '\n'

printf '== every changed path ==\n'
command git diff --stat "$tag..HEAD" | tail -40
printf '\n'

# --- The diff, bounded ------------------------------------------------
#
# Only the published surface, and only to a bound. The reviewer's
# question is what a consumer would notice, so a full tree diff would
# spend its context on the parts that answer nothing. The bound is
# announced rather than silent, because a range large enough to hit it
# is exactly the one where a missed breaking change hides.

printf '== diff on the published surface ==\n'
if [ -n "$published" ]; then
  diff_out=$(command git diff "$tag..HEAD" -- \
    '.apm' '.repotools' '.pre-commit-hooks.yaml' \
    '.github/workflows' '.github/actions' \
    'renovate.json' 'renovate' 'cmd' 'internal' 'packages')
  lines=$(printf '%s\n' "$diff_out" | wc -l | tr -d ' ')
  if [ "$lines" -gt "$DIFF_LIMIT" ]; then
    printf '%s\n' "$diff_out" | head -n "$DIFF_LIMIT"
    printf '\n[truncated at %s of %s lines. Read the rest with:\n' "$DIFF_LIMIT" "$lines"
    printf '  git -C %s diff %s..HEAD -- <path>]\n' "$clone" "$tag"
  else
    printf '%s\n' "$diff_out"
  fi
else
  printf '(nothing published changed)\n'
fi
