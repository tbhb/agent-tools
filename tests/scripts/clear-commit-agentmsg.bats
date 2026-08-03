#!/usr/bin/env bats
#
# Tests for scripts/clear-commit-agentmsg.sh — the post-commit hook that
# removes the agent commit-message draft after a commit lands.
#
# The pinned bats image carries no git, so these drive the script through
# a git stub on PATH. That is enough: the script's whole contract is
# "ask git for the worktree root, then delete the draft under it".

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/clear-commit-agentmsg.sh"
  STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "$STUB_DIR" "$ROOT"
}

# stub_git installs a git that reports $1 as the worktree root. Called
# with no argument, it installs one that fails the way git does outside
# a repository.
stub_git() {
  if [ "$#" -eq 0 ]; then
    printf '#!/usr/bin/env bash\nexit 128\n' >"${STUB_DIR}/git"
  else
    {
      printf '#!/usr/bin/env bash\n'
      printf 'printf "%%s\\n" "%s"\n' "$1"
    } >"${STUB_DIR}/git"
  fi
  chmod +x "${STUB_DIR}/git"
}

@test "deletes the draft rather than truncating it" {
  stub_git "$ROOT"
  printf 'docs: explain the thing\n' >"${ROOT}/COMMIT_AGENTMSG"
  PATH="${STUB_DIR}:${PATH}" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "${ROOT}/COMMIT_AGENTMSG" ]
}

@test "succeeds when no draft is present" {
  stub_git "$ROOT"
  PATH="${STUB_DIR}:${PATH}" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "${ROOT}/COMMIT_AGENTMSG" ]
}

@test "clears only the draft under the reported root" {
  local other="${BATS_TEST_TMPDIR}/other"
  mkdir -p "$other"
  stub_git "$ROOT"
  printf 'this worktree\n' >"${ROOT}/COMMIT_AGENTMSG"
  printf 'another worktree\n' >"${other}/COMMIT_AGENTMSG"
  PATH="${STUB_DIR}:${PATH}" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "${ROOT}/COMMIT_AGENTMSG" ]
  [ -e "${other}/COMMIT_AGENTMSG" ]
}

@test "exits cleanly when git cannot resolve a worktree" {
  stub_git
  PATH="${STUB_DIR}:${PATH}" run "$SCRIPT"
  [ "$status" -eq 0 ]
}
