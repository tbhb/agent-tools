#!/usr/bin/env bash
# clear-commit-agentmsg — remove the agent commit-message draft once a
# commit lands. Runs on the post-commit stage, which git fires only
# after the commit succeeds, so a rejected commit keeps its draft and
# the author keeps their work.
#
# The file is deleted rather than truncated, and that distinction is the
# whole point. An agent harness tracks which files it has read; a file
# that still exists with different contents fails the next write with
# "you must read the file first", so the agent burns a turn re-reading a
# scratchpad it is about to overwrite anyway. An absent path carries no
# stale read state, and writing the next draft just works.
#
# Takes no arguments. The other hooks in this repository run on the
# commit-msg stage and receive the buffer path; this one runs after the
# fact and resolves the worktree root itself, because a post-commit hook
# is not handed one.
set -euo pipefail

# --- environment hardening -------------------------------------------
# An operator's locale reshapes what git prints, and this script acts on
# the path git reports. Pinning it keeps the resolution the same on every
# machine that installs the hook.
export LC_ALL=C

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
rm -f "${root}/COMMIT_AGENTMSG"
