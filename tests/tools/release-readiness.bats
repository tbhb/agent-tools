#!/usr/bin/env bats
#
# Tests for tools/release-readiness.sh, covering the one check that says
# whether the tree in front of the operator is the tree being released.
#
# That check compares HEAD against the commit origin's release branch
# points at, and the cases worth holding are the ones a branch-name test
# got wrong: an agent worktree, which can never hold main checked out,
# and a detached HEAD. Both are correct releases and both used to be
# refused. The failing arms matter too, because dropping the name test
# is only safe if the commit test still refuses everything it should.
#
# Each test builds a throwaway repository with a bare origin beside it,
# since the script reads the remote with ls-remote. The three programs it
# shells out to are stubbed on PATH: gh, because the check-runs API has
# no answer for a commit nobody pushed anywhere real; mise and cog,
# because neither has anything to say about a synthetic history. What
# they report is held constant so the commit comparison is the only
# thing any assertion here turns on.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../tools/release-readiness.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  ORIGIN="${BATS_TEST_TMPDIR}/origin.git"
  BIN="${BATS_TEST_TMPDIR}/bin"

  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME='Test' GIT_AUTHOR_EMAIL='test@example.com'
  export GIT_COMMITTER_NAME='Test' GIT_COMMITTER_EMAIL='test@example.com'

  mkdir -p "$REPO/tools" "$BIN"
  git init --quiet --bare --initial-branch=main "$ORIGIN"

  cd "$REPO"
  git init --quiet --initial-branch=main .
  git remote add origin "$ORIGIN"

  # Committed rather than merely written, because readiness checks the
  # tree is clean and an untracked stub would fail that check in every
  # test here, including the ones asserting a pass.
  printf '#!/bin/sh\nexit 0\n' > "$REPO/tools/check-versions.sh"
  git add tools/check-versions.sh
  git commit --quiet -m "a commit"
  git push --quiet origin main

  printf '#!/bin/sh\nprintf "success build\\n"\n' > "$BIN/gh"
  printf '#!/bin/sh\nprintf "a changelog\\n"\n' > "$BIN/mise"
  printf '#!/bin/sh\nprintf "v1.2.4\\n"\n' > "$BIN/cog"
  chmod +x "$BIN/gh" "$BIN/mise" "$BIN/cog"
  export PATH="$BIN:$PATH"
}

@test "passes from a branch that is not main but sits on origin's commit" {
  git checkout --quiet -b worktree-some-task

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ $output == *"OK    HEAD is origin/main"* ]]
  [[ $output == *"READY"* ]]
  # The branch name reaches no finding at all, which is the point.
  [[ $output != *"FAIL"* ]]
}

@test "passes from a detached HEAD at origin's commit" {
  git checkout --quiet --detach

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ $output != *"FAIL"* ]]
}

@test "refuses a HEAD that has moved past origin, naming both commits" {
  git checkout --quiet -b worktree-some-task
  git commit --quiet --allow-empty -m "a commit origin has never seen"
  local ahead
  ahead=$(git rev-parse HEAD)
  local pushed
  pushed=$(git rev-parse HEAD~1)

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  HEAD is origin/main"* ]]
  [[ $output == *"HEAD is $ahead, origin/main is $pushed"* ]]
}

@test "refuses a local branch named main that origin has not caught up with" {
  git commit --quiet --allow-empty -m "a commit origin has never seen"

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  HEAD is origin/main"* ]]
}

@test "refuses where origin carries no release branch" {
  # Straight at the ref. A push deleting it is refused, main being the
  # bare repository's own HEAD.
  git -C "$ORIGIN" update-ref -d refs/heads/main

  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ $output == *"origin has no main"* ]]
}
