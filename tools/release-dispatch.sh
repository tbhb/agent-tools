#!/usr/bin/env bash
# release-dispatch — dispatch the release workflow.
#
# This dispatches. It does not release. release.yml SSH-signs the tag
# with a repository secret, under the tagger identity GitHub verifies
# that key against, so no local command can reproduce what it produces.
# Anything here that bumped and tagged locally would mint an unsigned or
# wrongly attributed tag and diverge from the path every consumer pins
# against. There is no bump-version task for the same reason: cocogitto
# owns bumping, it runs inside CI, and a second local bumper would be a
# second source for one number.
#
# Deliberately thin, and deliberately kept that way. The target for
# release management here is a continuously updated release pull request
# whose merge tags and publishes, and under that model releasing is
# merging rather than dispatching, so this is the piece that gets
# superseded. Readiness and verification survive it. No retry, no
# polling, no state.
#
# Usage: release-dispatch.sh [X.Y.Z]
#   With no argument the workflow runs `cog bump --auto`, which derives
#   the version from the Conventional Commit types since the last tag.
#   Readiness prints that derived version, so read it before choosing.
set -euo pipefail

export LC_ALL=C
export GH_PAGER=cat
export GH_PROMPT_DISABLED=1
unset CDPATH GH_REPO GH_HOST GREP_OPTIONS
IFS=$' \t\n'

root=$(command git rev-parse --show-toplevel)
cd "$root"

# Named rather than left to the default, and readiness reads the same
# name. A bare `gh workflow run` resolves to the repository's default
# branch, which is right today by coincidence of configuration rather
# than by statement, and `on: workflow_dispatch` constrains nothing:
# it takes no branch filter, so any ref carrying the workflow file can
# run it. release.yml's checkout takes the dispatched ref while its push
# step names main outright, so a dispatch against anything else would
# bump that ref's tree and push the result onto main. Saying the branch
# here costs one flag and makes the target the same statement readiness
# verified.
readonly RELEASE_BRANCH=main

version=${1:-}
if [ -n "$version" ]; then
  # release.yml passes this straight to `cog bump --version`, which
  # takes a bare X.Y.Z. A leading v reaches the tag twice.
  case $version in
  v*)
    printf 'release-dispatch: pass the version without a leading v (got %s)\n' "$version" >&2
    exit 1
    ;;
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    printf 'release-dispatch: %s is not an X.Y.Z version\n' "$version" >&2
    exit 1
    ;;
  esac
fi

if ! bash tools/release-readiness.sh; then
  printf '\nrelease-dispatch: refusing to dispatch, readiness failed\n' >&2
  exit 1
fi

if [ -n "$version" ]; then
  printf '\ndispatching: gh workflow run release.yml --ref %s -f version=%s\n' "$RELEASE_BRANCH" "$version"
  gh workflow run release.yml --ref "$RELEASE_BRANCH" -f version="$version"
else
  printf '\ndispatching: gh workflow run release.yml --ref %s (cog bump --auto)\n' "$RELEASE_BRANCH"
  gh workflow run release.yml --ref "$RELEASE_BRANCH"
fi

printf 'dispatched. Follow it with: gh run list --workflow=release.yml\n'
printf 'Then, once the run finishes: mise run verify-repotools-release\n'
