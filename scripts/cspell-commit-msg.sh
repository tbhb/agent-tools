#!/usr/bin/env bash
# Spell-check the commit-message buffer with cspell, reading it on
# stdin under a worktree-relative virtual path so cspell resolves its
# config from the worktree root.
#
# The commit-msg hook lints the buffer at the path git hands it, which
# for a linked worktree is the real file under the common git
# directory (for example .git/worktrees/<name>/COMMIT_EDITMSG). That
# path sits beside the main worktree's tree, not this worktree's, so
# cspell's parent-directory config search loads the main worktree's
# .cspell-words.txt and merges it ahead of the explicit --config. A
# word that a branch adds to its own dictionary then reads as unknown
# and the commit fails, even though "just lint-commit-msg" passed
# (that recipe lints COMMIT_AGENTMSG at the worktree root, where the
# search finds the right dictionary).
#
# Piping the buffer on stdin and labelling it "stdin://./<basename>"
# anchors both the config search and the error-message path to the
# current directory, which prek sets to the worktree root. The
# explicit --config still loads the project settings; the virtual
# path just keeps the discovered dictionary from being the wrong one.
# This mirrors tools/vale-commit-msg.sh, which sidesteps the same
# worktree path problem for vale.
#
# The hook receives the message-buffer path as $1
# (.git/worktrees/<name>/COMMIT_EDITMSG from git, or COMMIT_AGENTMSG
# from the lint-commit-msg recipe).
set -euo pipefail

msg_file=$1

# Read the buffer up front so the cspell invocation does not name the
# message file in both a redirect and its virtual path (shellcheck
# SC2094). The $(<file) form avoids a cat subprocess as well.
message=$(<"${msg_file}")

printf '%s\n' "${message}" | cspell \
  --config .cspell.jsonc \
  --no-summary \
  --no-progress \
  --language-id commit-msg \
  "stdin://./$(basename "${msg_file}")"
