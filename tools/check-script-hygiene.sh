#!/usr/bin/env bash
# check-script-hygiene — refuse a script whose output an operator's
# configuration could reshape.
#
# The agent reads what these scripts print. A user's ~/.gitconfig,
# ~/.config/gh/config.yml, and locale can all change that output without
# changing the script, and the failures are silent: log.showSignature
# turns a --oneline listing into two lines per commit, so a head -n cap
# shows half a branch as though it were all of it. A collation mismatch
# drops a line from a set comparison. GH_REPO points gh at a different
# repository entirely.
#
# The scripts carry a hardening block for this. That block is a
# convention, and a convention holds only while somebody remembers it,
# so this turns it into a gate. A new script that parses git output and
# skips the wrapper fails the lint run rather than shipping.
#
# Findings print one per line, in the shape the vale template uses.
# Silence means a clean run.
#
# A script with a genuine reason to opt out says so on its own line:
#
#   # hygiene-exempt: <reason>
#
# hygiene-exempt: the rules below quote the command names they look for,
# so this script matches its own patterns. It never invokes gh, and its
# one git call is pinned inline.
#
# Usage: check-script-hygiene.sh [file ...]
set -euo pipefail

export LC_ALL=C
unset CDPATH GREP_OPTIONS
IFS=$(printf ' \t\n')

root=$(git rev-parse --show-toplevel)
cd "$root"

findings=0
report() {
  printf '%s:%s [error] %s  %s\n' "$1" "$2" "$3" "$4"
  findings=$((findings + 1))
}

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  # Tracked files only, matching how lint-shell scopes itself.
  while IFS= read -r f; do
    files+=("$f")
  done < <(command git -c core.quotePath=false ls-files \
    '.apm/skills/*/scripts/*.sh' 'hooks/*.sh' 'tools/*.sh')
fi

for f in "${files[@]}"; do
  [ -f "$f" ] || continue

  if grep -q '^# hygiene-exempt:' "$f"; then
    continue
  fi

  # Comments discuss these commands constantly, and a guard script
  # quotes them in its refusal text. Only code lines count.
  code=$(grep -vE '^[[:space:]]*#' "$f" || true)

  calls_git=$(printf '%s\n' "$code" | grep -cE '(^|[^-[:alnum:]_])git ' || true)
  calls_gh=$(printf '%s\n' "$code" | grep -cE '(^|[^-[:alnum:]_])gh ' || true)

  if [ "$calls_git" = "0" ] && [ "$calls_gh" = "0" ]; then
    continue
  fi

  # Rule 1: anything invoking git or gh pins the locale, because sort
  # ordering and the [a-z] ranges these scripts use both move with it.
  if ! grep -q '^export LC_ALL=' "$f"; then
    report "$f" 1 missing-locale-pin \
      "invokes git or gh without 'export LC_ALL=C'; sort order and [a-z] ranges shift with the locale"
  fi

  # Rule 2: gh reads GH_REPO and GH_HOST from the environment, and
  # either one silently retargets every call at another repository.
  if [ "$calls_gh" != "0" ] && ! grep -q '^unset .*GH_REPO' "$f"; then
    report "$f" 1 missing-gh-unset \
      "invokes gh without unsetting GH_REPO and GH_HOST; an exported one retargets the repository"
  fi

  # Rule 3: output this script parses goes through the wrapper.
  while IFS=: read -r lineno text; do
    [ -n "$lineno" ] || continue
    case $text in
    *'# hygiene-ok'*) continue ;;
    esac
    report "$f" "$lineno" "bare-git-output" \
      "parses git output without gitr; log.showSignature and the diff prefix settings reshape this"
  done < <(grep -nE '(^|[^-[:alnum:]_r])git (log|show|diff)\b' "$f" |
    grep -vE '^[0-9]+:[[:space:]]*#' || true)

  # Rule 4: an external difftool replaces the patch wholesale, so every
  # diff says so explicitly.
  while IFS=: read -r lineno _; do
    [ -n "$lineno" ] || continue
    report "$f" "$lineno" "diff-without-no-ext-diff" \
      "gitr diff without --no-ext-diff; diff.external would replace the patch entirely"
  done < <(grep -nE 'gitr diff' "$f" | grep -v -- '--no-ext-diff' |
    grep -vE '^[0-9]+:[[:space:]]*#' || true)
done

if [ "$findings" -gt 0 ]; then
  printf 'TOTAL: %s finding(s)\n' "$findings"
  exit 1
fi
