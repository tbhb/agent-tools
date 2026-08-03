#!/usr/bin/env bats
#
# Tests for tools/release-dispatch.sh.
#
# The contract worth asserting is the command line it builds and the
# preflight it refuses on, so these drive the script as a subprocess with
# a stub `gh` on PATH recording what it was called with. Nothing here
# dispatches a workflow, and testing against the real one would mean
# cutting a release to find out.
#
# The readiness script resolves relative to the repository root, so a
# throwaway repository carrying a stub at that path is what lets these
# exercise both the pass and the refuse arm.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../tools/release-dispatch.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  BIN="${BATS_TEST_TMPDIR}/bin"
  GH_LOG="${BATS_TEST_TMPDIR}/gh.log"

  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME='Test' GIT_AUTHOR_EMAIL='test@example.com'
  export GIT_COMMITTER_NAME='Test' GIT_COMMITTER_EMAIL='test@example.com'

  mkdir -p "$REPO/tools" "$BIN"
  cd "$REPO"
  git init --quiet --initial-branch=main .
  git commit --quiet --allow-empty -m "a commit"

  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$GH_LOG" > "$BIN/gh"
  chmod +x "$BIN/gh"
  export PATH="$BIN:$PATH"
}

pass_readiness() {
  printf '#!/bin/sh\necho READY\nexit 0\n' > "$REPO/tools/release-readiness.sh"
}

fail_readiness() {
  printf '#!/bin/sh\necho "NOT READY: 1 check(s) failed"\nexit 1\n' > "$REPO/tools/release-readiness.sh"
}

@test "passes an explicit version through to the workflow" {
  pass_readiness

  run "$SCRIPT" 0.5.0
  [ "$status" -eq 0 ]
  [ "$(cat "$GH_LOG")" = "workflow run release.yml -f version=0.5.0" ]
}

@test "dispatches with no input where no version is given" {
  pass_readiness

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$GH_LOG")" = "workflow run release.yml" ]
  [[ $output == *"cog bump --auto"* ]]
}

@test "refuses to dispatch where readiness fails" {
  fail_readiness

  run "$SCRIPT" 0.5.0
  [ "$status" -eq 1 ]
  [[ $output == *"refusing to dispatch, readiness failed"* ]]
  # The refusal has to happen before the call, not after it.
  [ ! -f "$GH_LOG" ]
}

@test "refuses a version carrying a leading v before running anything" {
  pass_readiness

  run "$SCRIPT" v0.5.0
  [ "$status" -eq 1 ]
  [[ $output == *"without a leading v"* ]]
  [ ! -f "$GH_LOG" ]
}

@test "refuses a version that is not X.Y.Z" {
  pass_readiness

  run "$SCRIPT" 0.5
  [ "$status" -eq 1 ]
  [[ $output == *"is not an X.Y.Z version"* ]]
  [ ! -f "$GH_LOG" ]
}
