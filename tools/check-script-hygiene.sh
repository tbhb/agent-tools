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
IFS=$' \t\n'

root=$(git rev-parse --show-toplevel)
cd "$root"

findings=0
report() {
  printf '%s:%s [error] %s  %s\n' "$1" "$2" "$3" "$4"
  findings=$((findings + 1))
}

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  # Whatever git can see, matching how lint-shell scopes itself. A new
  # script is the one this check exists for, and reading the index
  # alone would reach it only once somebody staged it. Gitignored
  # scratch scripts stay out through --exclude-standard.
  while IFS= read -r f; do
    files+=("$f")
  done < <(command git -c core.quotePath=false ls-files \
    --cached --others --exclude-standard \
    '.apm/skills/*/scripts/*.sh' 'hooks/*.sh' 'scripts/*.sh' 'tools/*.sh')

  # Then the skills that live under .claude/ alone. A repo-local skill
  # has no .apm/ source, so the glob above cannot reach its scripts,
  # while the .claude/ copy of a published skill is a mirror of one it
  # already scanned and would report every finding twice. Asking whether
  # .apm/ holds a skill of the same name separates the two, and keeps
  # the next local skill covered without an edit here.
  while IFS= read -r f; do
    skill=${f#.claude/skills/}
    skill=${skill%%/*}
    [ -d ".apm/skills/$skill" ] && continue
    files+=("$f")
  done < <(command git -c core.quotePath=false ls-files \
    --cached --others --exclude-standard '.claude/skills/*/scripts/*.sh')
fi

# The files the structural pass below scans: everything that exists and
# has not opted out. Collected here so `hygiene-exempt` means the same
# thing to both passes, and so a script that calls neither git nor gh
# still reaches the rules that have nothing to do with either.
scan_files=()

for f in "${files[@]}"; do
  [ -f "$f" ] || continue

  if grep -q '^# hygiene-exempt:' "$f"; then
    continue
  fi

  scan_files+=("$f")

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

done

# Rules 3 to 5 match shell structure rather than text, so ast-grep owns
# them and .ast-grep/rules holds one file each. They run over the whole
# file list in a single pass, after the per-file loop above, because
# ast-grep starts faster once than once per script.
#
# The JSON stream is reformatted into report()'s shape rather than shown
# raw. ast-grep's own output is a rustc-style block with source previews,
# and the agent reading this expects one self-contained line per finding,
# the same shape the vale template emits. Line numbers arrive 0-indexed.
if [ ${#scan_files[@]} -gt 0 ]; then
  ast_err=$(mktemp)
  trap 'rm -f "$ast_err"' EXIT

  # ast-grep exits 1 when it finds diagnostics, which is the ordinary
  # case here and not a failure of the run. Any other status means the
  # tool itself broke: a missing binary, an unreadable sgconfig.yml, a
  # rule that no longer parses. Those must not read as a clean gate, so
  # the status is separated from the finding count rather than discarded.
  set +e
  ast_json=$(ast-grep scan --json=stream "${scan_files[@]}" 2>"$ast_err")
  ast_status=$?
  set -e
  if [ "$ast_status" -gt 1 ]; then
    printf 'check-script-hygiene: ast-grep failed with status %s\n' "$ast_status" >&2
    cat "$ast_err" >&2
    exit 1
  fi

  # join rather than @tsv: @tsv escapes a backslash as two, and every
  # one of these messages quotes a shell escape. Sorted by file then
  # line, because ast-grep streams grouped by rule and the reader wants
  # a script's findings together and in source order.
  while IFS=$'\t' read -r file line rule message; do
    [ -n "$file" ] || continue
    report "$file" "$line" "$rule" "$message"
  done < <(printf '%s' "$ast_json" |
    jq -r 'select(.file) | [.file, (.range.start.line + 1 | tostring), .ruleId, .message] | join("\t")' |
    sort -t"$(printf '\t')" -k1,1 -k2,2n)
fi

if [ "$findings" -gt 0 ]; then
  printf 'TOTAL: %s finding(s)\n' "$findings"
  exit 1
fi
