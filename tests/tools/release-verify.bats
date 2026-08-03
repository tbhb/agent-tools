#!/usr/bin/env bats
#
# Tests for tools/release-verify.sh.
#
# Scoped to the checks that settle before the script reaches the network:
# a tag that is not there, and a tag that is lightweight rather than
# annotated. Both report and stop, so a throwaway repository is enough to
# drive them and no test here talks to GitHub.
#
# The lightweight case is the one worth holding. Cog can only make a
# lightweight tag, `push --follow-tags` pushes annotated tags alone, and
# release.yml deletes and re-creates the tag signed to compensate. A
# verifier that has only ever seen a good tag has not been tested against
# the failure it exists for.
#
# The signed path has no fixture here, because fabricating a tag GitHub
# would call verified means holding the release signing key. Running the
# task against a real release tag is what exercises that half.

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

@test "refuses where no tag exists and none was named" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"no tag given and none reachable from HEAD"* ]]
}
