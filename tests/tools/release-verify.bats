#!/usr/bin/env bats
#
# Tests for tools/release-verify.sh.
#
# Scoped to the checks a throwaway repository can settle: a tag that is
# not there, a tag that is lightweight rather than annotated, and a
# release commit that nothing signed. No test here talks to GitHub.
#
# The lightweight case is the one worth holding. Cog can only make a
# lightweight tag, `push --follow-tags` pushes annotated tags alone, and
# release.yml deletes and re-creates the tag signed to compensate. A
# verifier that has only ever seen a good tag has not been tested against
# the failure it exists for.
#
# The unsigned-commit case is the second one, and it is the failure that
# actually shipped: every release CI cut, v0.3.0 through v0.5.0, carried
# a verified tag over a commit the runner wrote and nothing signed, while
# this task read the tag alone and called the release good.
#
# Neither signed path takes a fixture, and for the same reason from
# opposite directions. Fabricating a tag GitHub would call verified means
# holding the release signing key, and fabricating a signed release
# commit means holding GitHub's. Running the task against a real release
# tag is what exercises those halves.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../tools/release-verify.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"

  # Cut the operator's configuration out. tag.gpgSign or
  # tag.forceSignAnnotated would otherwise turn the lightweight tag below
  # into the annotated one these tests exist to tell apart.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME='Test' GIT_AUTHOR_EMAIL='test@example.com'
  export GIT_COMMITTER_NAME='Test' GIT_COMMITTER_EMAIL='test@example.com'

  mkdir -p "$REPO"
  cd "$REPO"
  git init --quiet --initial-branch=main .
  git commit --quiet --allow-empty -m "a release commit"
}

# Give the repository an origin that answers without a network. The
# commit checks sit past `git ls-remote origin`, which aborts the script
# under `set -e` where no remote answers at all, so a bare repository
# next door is what lets a test reach them. The gh calls beyond it report
# and carry on rather than aborting, which is what those checks are
# written for, so nothing here needs a stub.
publish() {
  git init --quiet --bare "${BATS_TEST_TMPDIR}/origin.git"
  git remote add origin "${BATS_TEST_TMPDIR}/origin.git"
  git push --quiet origin main "refs/tags/$1"
  git fetch --quiet origin
}

@test "rejects a lightweight tag rather than reading it as present" {
  git tag v1.2.3

  run "$SCRIPT" v1.2.3
  [ "$status" -eq 1 ]
  [[ $output == *"OK    tag v1.2.3 exists locally"* ]]
  [[ $output == *"FAIL  tag v1.2.3 is annotated"* ]]
  [[ $output == *"lightweight tag pointing at a commit"* ]]
  [[ $output == *"BAD RELEASE v1.2.3"* ]]
}

@test "stops at the lightweight tag rather than reporting later checks" {
  git tag v1.2.3

  run "$SCRIPT" v1.2.3
  # Nothing downstream can hold once the tag is not a tag object, and
  # reporting those checks would bury the one finding that matters.
  [[ $output != *"SSH signature"* ]]
  [[ $output != *"reachable from main"* ]]
}

@test "reports a tag that is not present rather than passing" {
  run "$SCRIPT" v9.9.9
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  tag v9.9.9 exists locally"* ]]
  [[ $output == *"git fetch --tags"* ]]
}

@test "takes a version with or without the leading v" {
  git tag v1.2.3

  run "$SCRIPT" 1.2.3
  [ "$status" -eq 1 ]
  [[ $output == *"tag v1.2.3 is annotated"* ]]
}

@test "verifies the latest tag when given no argument" {
  git tag v1.2.3

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"tag v1.2.3 is annotated"* ]]
}

@test "reports a release commit that nothing signed" {
  git tag -a v1.2.3 -m v1.2.3
  publish v1.2.3

  run "$SCRIPT" v1.2.3
  [ "$status" -eq 1 ]
  # The tag half passing is the point: this is the exact shape every
  # CI-cut release shipped in, and reading the tag alone called it good.
  [[ $output == *"OK    tag v1.2.3 is annotated"* ]]
  [[ $output == *"FAIL  the release commit carries a signature"* ]]
  [[ $output == *"written on the runner rather than by createCommitOnBranch"* ]]
}

@test "reports a release commit authored outside the release app" {
  git tag -a v1.2.3 -m v1.2.3
  publish v1.2.3

  run "$SCRIPT" v1.2.3
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  the release commit is authored by tbhb-releases[bot]"* ]]
  [[ $output == *"it names Test <test@example.com>"* ]]
}

@test "refuses where no tag exists and none was named" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"no tag given and none reachable from HEAD"* ]]
}
