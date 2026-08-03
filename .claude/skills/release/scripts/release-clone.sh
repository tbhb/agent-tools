#!/usr/bin/env bash
# release-clone — run the release tasks against a throwaway clone of
# the release branch, from whatever checkout invoked them.
#
# The release is a statement about origin/main and nothing else. The
# workflow checks that branch out fresh on the runner, so the tree a
# local checkout happens to hold has never been the thing being
# released. Reading the version literals, the changelog preview, and
# the derived version out of a clone of origin/main therefore answers
# the question more accurately than reading them out of a working
# checkout, which may sit on another branch or trail the remote.
#
# It also frees the release from the checkout it runs in. Several agent
# worktrees run here at once and the local main checkout stays pristine,
# so requiring the operator to move a checkout onto the release commit
# was a demand this repository's own layout could not meet.
#
# The clone costs almost nothing. `--reference` points it at the local
# object store, so it makes hard links to what is already on disk and
# fetches only what the remote has that the local repository does not.
#
# What the clone gives up, and what replaces it. Inside a fresh clone
# "the working tree is clean" and "HEAD is the release commit" are true
# by construction, so readiness stops reporting them as findings. Those
# two checks existed to catch one thing: an operator releasing while
# believing uncommitted or unmerged work was in it. `prepare` prints
# that as an advisory read from the invoking checkout instead. It says
# what the release leaves behind rather than refusing, because a branch
# in flight is the normal state here and never a reason a release of
# main cannot proceed.
#
# Nothing outside the clone changes. It borrows objects from the local
# repository and writes none back, reads the invoking checkout for the
# advisory and writes nothing there beyond a pointer file inside its git
# directory, and grants mise its trust through the environment rather
# than through the operator's global trust store.
#
# The clone is never a place to make a release. Nothing here tags,
# bumps, or commits, in the clone or anywhere else. The tag is
# SSH-signed inside release.yml under a key this machine does not hold.
#
# Usage: release-clone.sh prepare
#        release-clone.sh refresh
#        release-clone.sh path
#        release-clone.sh run <mise-task> [args...]
#        release-clone.sh done
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

readonly RELEASE_BRANCH=main

die() {
  printf 'release-clone: %s\n' "$1" >&2
  exit 1
}

# The invoking checkout, which this script reads and never writes.
invoking_root=$(command git rev-parse --show-toplevel 2>/dev/null) ||
  die "not inside a git repository"

absolute() {
  case $1 in
  /*) printf '%s\n' "$1" ;;
  *) printf '%s\n' "$invoking_root/$1" ;;
  esac
}

# Two git directories, and the difference matters. --git-common-dir is
# the main repository's, shared by every linked worktree, and it holds
# the object store the clone borrows from. --git-dir is this worktree's
# alone.
#
# The pointer goes in the per-worktree one. Several worktrees run here
# at once, so a pointer in the shared directory would have two sessions
# overwriting each other's clone path, and a `done` in one would delete
# a clone the other was mid-release against. Scoping it per worktree
# means a release running beside this one is invisible to it.
common_dir=$(absolute "$(cd "$invoking_root" && command git rev-parse --git-common-dir)")
git_dir=$(absolute "$(cd "$invoking_root" && command git rev-parse --git-dir)")
readonly POINTER=$git_dir/release-clone-path

read_pointer() {
  [ -f "$POINTER" ] || return 1
  local recorded
  recorded=$(cat "$POINTER")
  [ -n "$recorded" ] || return 1
  [ -d "$recorded/.git" ] || return 1
  printf '%s\n' "$recorded"
}

cmd_prepare() {
  local clone
  if clone=$(read_pointer); then
    printf 'reusing the release clone at %s\n' "$clone"
  else
    local url
    url=$(cd "$invoking_root" && command git remote get-url origin) ||
      die "the invoking repository has no origin remote"

    # mktemp -d rather than a fixed path, so two releases running at
    # once never share a tree, and so nothing here can collide with a
    # directory the operator meant to keep.
    clone=$(mktemp -d "${TMPDIR:-/tmp}/repotools-release.XXXXXX")

    # --reference makes hard links against the local object store,
    # which is what makes this take under a second. --dissociate is deliberately
    # absent: the clone is thrown away, so borrowing objects from a
    # repository that outlives it costs nothing and copying them back
    # out would be the only expensive part of this.
    command git clone --quiet \
      --reference "$common_dir" \
      --branch "$RELEASE_BRANCH" \
      "$url" "$clone" ||
      die "could not clone $url"

    # The clone resolves its own toolchain rather than borrowing
    # whatever the invoking shell happens to have activated. The release
    # branch pins its own versions, and a worktree sitting on a branch
    # that moved one would otherwise judge the release with the wrong
    # cog. Installing costs nothing where the pins already match, which
    # is the ordinary case, and downloads where they do not, which is
    # the case worth catching.
    #
    # `install-toolchain` rather than `bootstrap`, which composes it with
    # two more steps this never needs. `install-tools` syncs vale styles
    # and builds a Python virtual environment, and no release gate runs
    # prose lint or touches `packages/`. `repotools:prek-install` writes
    # git hooks, and nothing commits in here. Both would spend real time
    # per release on work the release cannot use.
    MISE_TRUSTED_CONFIG_PATHS=$clone mise -C "$clone" run install-toolchain >/dev/null 2>&1 ||
      die "could not install the pinned toolchain in $clone"

    printf '%s\n' "$clone" > "$POINTER"
    printf 'prepared a release clone of %s at %s\n' "$RELEASE_BRANCH" "$clone"
  fi

  local head
  head=$(cd "$clone" && command git rev-parse --short HEAD)
  printf 'releasing %s at %s\n' "$RELEASE_BRANCH" "$head"

  advisory "$clone"
}

# What this release leaves behind, read from the checkout that invoked
# it. Advisory rather than a gate, and the distinction is the whole
# point: a release of main is legitimate while a branch is in flight,
# and the only thing worth saying is which work is not in it.
advisory() {
  local clone=$1 released local_head ahead branch
  released=$(cd "$clone" && command git rev-parse HEAD)
  local_head=$(cd "$invoking_root" && command git rev-parse HEAD)

  [ "$local_head" = "$released" ] && return 0

  branch=$(cd "$invoking_root" && command git rev-parse --abbrev-ref HEAD)

  # Counted against the released commit rather than against a
  # remote-tracking ref, which in a worktree may be any age.
  ahead=$(cd "$invoking_root" &&
    command git rev-list --count "$released..$local_head" 2>/dev/null || printf '0\n')

  if [ "$ahead" = "0" ]; then
    printf 'NOTE  this checkout (%s) is not on the released commit, and carries nothing the release lacks\n' "$branch"
    return 0
  fi

  printf 'NOTE  this checkout (%s) carries work the release does not include:\n' "$branch"
  (cd "$invoking_root" &&
    command git log --format='      %h %s' "$released..$local_head") || true
  printf '      Land it and prepare again to release it, or go on to release %s without it.\n' "$RELEASE_BRANCH"
}

cmd_run() {
  [ $# -ge 1 ] || die "run needs a task name"
  local clone
  clone=$(read_pointer) || die "no release clone; run 'release-clone.sh prepare' first"

  # The working directory is the whole point of this subcommand. Every
  # release task resolves its own repository root from the current
  # directory, so running one from the invoking checkout would read that
  # tree no matter which clone was prepared. `-C` sets it for the task
  # body rather than for this shell, which keeps the caller's directory
  # its own.
  #
  # MISE_TRUSTED_CONFIG_PATHS rather than `mise trust`. mise refuses a
  # config at a path it has not seen, and the clone is always such a
  # path, but trusting it would write an entry to the operator's global
  # trust store for a directory removed minutes later. The variable
  # grants the same trust for the length of one command and leaves
  # nothing behind.
  MISE_TRUSTED_CONFIG_PATHS=$clone mise -C "$clone" run "$@"
}

cmd_done() {
  local clone
  if clone=$(read_pointer); then
    rm -rf "$clone"
    printf 'removed the release clone at %s\n' "$clone"
  fi
  rm -f "$POINTER"
}

case ${1:-} in
prepare)
  cmd_prepare
  ;;
refresh)
  # The release lands a commit and a tag on main, which leaves the clone
  # describing the state before its own release. Verification then reads
  # a tag the clone has never seen and version literals naming the
  # previous one. Throwing it away and cloning again costs about half a
  # second and leaves no question about what the second clone holds,
  # which fetching into the first one would.
  cmd_done >/dev/null
  cmd_prepare
  ;;
path)
  read_pointer || die "no release clone; run 'release-clone.sh prepare' first"
  ;;
run)
  shift
  cmd_run "$@"
  ;;
done)
  cmd_done
  ;;
*)
  die "usage: release-clone.sh prepare|refresh|path|run <task> [args...]|done"
  ;;
esac
