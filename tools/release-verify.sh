#!/usr/bin/env bash
# release-verify — check that a release tag is what the release
# convention promises, after the workflow has landed it.
#
# The sharp assertion is that the tag is annotated and signed rather
# than merely present. Cog drives libgit2 and can only make a
# lightweight tag, which `push --follow-tags` silently leaves behind
# because that flag pushes annotated tags alone. release.yml deletes
# cog's tag and re-creates it signed to work around that, so a check
# asking only whether the tag exists would pass in exactly the case the
# workaround exists for.
#
# The commit under that tag gets the same treatment, and for a reason
# this task learned the hard way: it read the tag alone, and every
# release CI cut from v0.3.0 through v0.5.0 shipped a verified tag over
# an unsigned commit. A good tag implies nothing about the object beneath
# it. The two are signed by different parties here, so they are two
# assertions rather than one.
#
# It matters more than it looks, because the bump runs under --skip-ci
# and CI never validates the release commit. That is deliberate, and it
# leaves this task as the only thing standing between a bad release
# commit and every consumer pinning the tag.
#
# The tag is the whole release. This repository publishes no GitHub
# Release object, no release assets, and no built artifacts: consumers
# resolve the ref directly, through apm, the Go module proxy, a
# pre-commit rev, or a workflow pin. So nothing here looks for a
# release object, and finding none is correct rather than a gap.
#
# Read-only. It reads the local tag, the remote's refs, and the API, and
# writes nothing.
#
# Usage: release-verify.sh [vX.Y.Z]
#   With no argument it verifies the latest tag.
set -euo pipefail

export LC_ALL=C
export GH_PAGER=cat
export GH_PROMPT_DISABLED=1
unset CDPATH GH_REPO GH_HOST GREP_OPTIONS
IFS=$' \t\n'

root=$(command git rev-parse --show-toplevel)
cd "$root"

# The identity release.yml tags under, and the identity GitHub verifies
# the signing key against. Changing it in one place alone produces a tag
# that signs correctly and still shows as unverified.
readonly TAGGER='Tony Burns <tony@tonyburns.net>'

# The identity createCommitOnBranch commits under, which is the release
# App's bot user rather than anything the runner chooses. The local part
# is that user's numeric id, so recreating the App changes this address
# and the release identity along with it.
readonly RELEASE_AUTHOR='tbhb-releases[bot] <278792582+tbhb-releases[bot]@users.noreply.github.com>'
readonly RELEASE_BRANCH=main

failures=0
ok() { printf 'OK    %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  [ $# -lt 2 ] || printf '      %s\n' "$2"
  failures=$((failures + 1))
}
finish() {
  if [ "$failures" -gt 0 ]; then
    printf 'BAD RELEASE %s: %s check(s) failed\n' "$tag" "$failures"
    exit 1
  fi
  printf 'RELEASE %s VERIFIED\n' "$tag"
  exit 0
}

latest=$(command git describe --tags --abbrev=0 2>/dev/null || true)
tag=${1:-$latest}
case $tag in
'')
  printf 'release-verify: no tag given and none reachable from HEAD\n' >&2
  exit 1
  ;;
v*) ;;
*) tag=v$tag ;;
esac

# --- The tag exists locally ---

if ! command git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  fail "tag $tag exists locally" "run \`git fetch --tags\` and try again"
  finish
fi
ok "tag $tag exists locally"

# --- Annotated rather than lightweight ---
#
# This is the workaround's failure mode. A lightweight tag is a ref
# pointing straight at the commit, so cat-file reports commit rather
# than tag, and nothing below it can hold.

kind=$(command git cat-file -t "refs/tags/$tag")
if [ "$kind" != "tag" ]; then
  fail "tag $tag is annotated" "it is a lightweight tag pointing at a $kind; cog's tag survived instead of the signed replacement"
  finish
fi
ok "tag $tag is annotated"

body=$(command git cat-file tag "refs/tags/$tag")

# --- Signed ---

if printf '%s\n' "$body" | grep -q -- '-----BEGIN SSH SIGNATURE-----'; then
  ok "tag $tag carries an SSH signature"
else
  fail "tag $tag carries an SSH signature" "the tag object has no signature block"
fi

# --- Tagged under the release identity ---

tagger=$(printf '%s\n' "$body" | sed -n 's/^tagger \(.*\) [0-9][0-9]* [-+][0-9]*$/\1/p')
if [ "$tagger" = "$TAGGER" ]; then
  ok "tagger is $TAGGER"
else
  fail "tagger is $TAGGER" "the tag names $tagger, which is not the identity the signing key verifies against"
fi

# --- The release commit is signed, under the release App ---
#
# Signed by GitHub rather than by the runner, and that is the whole
# design rather than a detail. release.yml has GitHub create this commit
# through createCommitOnBranch, because a signature comes from a key the
# signer holds and a GitHub App has none to hold. So an unsigned commit
# here means it came off the runner, where nothing could have signed it
# as the App in the first place.
#
# Read out of the commit object, the way the tagger check above reads
# the tag object. A `git log --format` read would need the gitr wrapper
# to keep log.showSignature out of its output, and there is no wrapper
# in this script to reach for.

tag_commit=$(command git rev-parse "refs/tags/$tag^{commit}")
commit_object=$(command git cat-file commit "$tag_commit")

if printf '%s\n' "$commit_object" | grep -q '^gpgsig'; then
  ok "the release commit carries a signature"
else
  fail "the release commit carries a signature" "$tag_commit has none, so it was written on the runner rather than by createCommitOnBranch"
fi

commit_author=$(printf '%s\n' "$commit_object" | sed -n 's/^author \(.*\) [0-9][0-9]* [-+][0-9]*$/\1/p')
if [ "$commit_author" = "$RELEASE_AUTHOR" ]; then
  ok "the release commit is authored by $RELEASE_AUTHOR"
else
  fail "the release commit is authored by $RELEASE_AUTHOR" "it names $commit_author, which is not the identity createCommitOnBranch commits under"
fi

# --- The remote carries the same tag object ---

remote_tag=$(command git ls-remote origin "refs/tags/$tag" | cut -f1)
local_tag=$(command git rev-parse "refs/tags/$tag")
if [ -z "$remote_tag" ]; then
  fail "origin carries $tag" "origin has no such tag; --follow-tags may have left it behind"
elif [ "$remote_tag" = "$local_tag" ]; then
  ok "origin carries $tag"
else
  fail "origin carries $tag" "origin has $remote_tag, this checkout has $local_tag"
fi

# --- GitHub verifies the signature ---
#
# The local check above proves a signature is present. This one proves
# GitHub accepts it under the tagger's account, which is the property
# release.yml holds the signing key to produce. Only meaningful once the
# remote carries the object, so it rides on the check above.

if [ "$remote_tag" = "$local_tag" ] && [ -n "$remote_tag" ]; then
  verified=$(gh api "repos/{owner}/{repo}/git/tags/$local_tag" \
    --jq '"\(.verification.verified) \(.verification.reason)"' 2>/dev/null || true)
  case $verified in
  'true '*) ok "GitHub reports $tag verified" ;;
  '') fail "GitHub reports $tag verified" "the API returned nothing for the tag object" ;;
  *) fail "GitHub reports $tag verified" "GitHub says $verified" ;;
  esac
fi

# --- GitHub verifies the release commit ---
#
# The other half of the same question, asked about the object under the
# tag. It reads a verdict on a signature GitHub itself produced, so
# anything but valid means the commit on the remote is not the one this
# checkout just read.

commit_verified=$(gh api "repos/{owner}/{repo}/commits/$tag_commit" \
  --jq '"\(.commit.verification.verified) \(.commit.verification.reason)"' 2>/dev/null || true)
case $commit_verified in
'true '*) ok "GitHub reports the release commit verified" ;;
'') fail "GitHub reports the release commit verified" "the API returned nothing for $tag_commit" ;;
*) fail "GitHub reports the release commit verified" "GitHub says $commit_verified" ;;
esac

# --- Reachable from the release branch ---
#
# Against the remote-tracking ref rather than the local branch. These
# repositories run several agent worktrees at once and only one of them
# can hold `main` checked out, so a local branch is stale in every other
# worktree through no fault of the release. Comparing the tracking ref
# to what the remote actually reports keeps a stale fetch caught while
# leaving the answer the same wherever it runs.

tracking=$(command git rev-parse -q --verify "refs/remotes/origin/$RELEASE_BRANCH" || true)
remote_branch=$(command git ls-remote origin "refs/heads/$RELEASE_BRANCH" | cut -f1)
if [ -z "$tracking" ] || [ "$tracking" != "$remote_branch" ]; then
  fail "$tag is reachable from $RELEASE_BRANCH" "origin/$RELEASE_BRANCH is not current with origin; run \`git fetch origin\` before verifying"
elif command git merge-base --is-ancestor "$tag_commit" "$tracking"; then
  ok "$tag is reachable from $RELEASE_BRANCH"
else
  fail "$tag is reachable from $RELEASE_BRANCH" "the tagged commit $tag_commit is not an ancestor of $RELEASE_BRANCH"
fi

# --- The published version literals name this tag ---
#
# check-versions reads the working tree, which names the latest released
# version between releases. That makes the assertion meaningful for the
# newest tag and meaningless for an older one, so an older tag gets the
# reason rather than a verdict it cannot support.

if [ "$tag" = "$latest" ]; then
  if literals=$(bash tools/check-versions.sh "$tag" 2>&1); then
    ok "version literals name $tag"
  else
    fail "version literals name $tag" "$(printf '%s' "$literals" | tr '\n' ' ')"
  fi
else
  printf 'INFO  skipping the literal check: the working tree names %s, not %s\n' "$latest" "$tag"
fi

finish
