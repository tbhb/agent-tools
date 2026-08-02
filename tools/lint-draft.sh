#!/usr/bin/env bash
# lint-draft — run every prose gate over one drafted document, in a
# single call, and report all of it at once.
#
# The recipes this replaces each run one checker. `just lint-prose x.md`
# runs vale and says nothing about spelling or structure, so a document
# that clears it can still fail cspell and rumdl afterwards. Answering
# them one at a time is how a twenty-line file turns into four rounds:
# the measured session behind this script ran a linter on half of its
# 250 Bash calls, and 69 percent of the failing runs surfaced one or two
# findings apiece. Every gate reports here, whatever the ones before it
# found.
#
# The probe is the other half. Vale matches a path against the sections
# in .vale.ini, the match is exact, and a path no section names loads no
# styles at all. Vale then reads the file, applies nothing, prints
# nothing, and exits 0, which is byte for byte what a clean document
# produces. Measured in this repository: one paragraph of deliberately
# bad prose draws 13 findings as probe.md, and zero as probe.txt, zero
# under another name, and zero one directory down.
#
# So this sends known-bad text through vale under the target's own path,
# using --path to associate that path with stdin, and never touching the
# file. Findings mean the path carries rules. Silence from text this bad
# means the path carries none, and the clean run above proved nothing.
#
# Findings print in the shape the vale template uses, and the exit code
# carries the result.
#
# Usage: lint-draft.sh <file>
set -uo pipefail

# --- environment hardening -------------------------------------------
# The agent reads this output, so the operator's preferences must not
# change its shape. LC_ALL pins collation, and CDPATH is unset because
# it makes a relative path resolve somewhere else entirely.
export LC_ALL=C
export PYTHONUTF8=1
unset CDPATH GREP_OPTIONS
IFS=$(printf ' \t\n')

root=$(git rev-parse --show-toplevel)
cd "$root" || exit 1

file=${1:-}
[ -n "$file" ] || {
  printf 'usage: lint-draft.sh <file>\n' >&2
  exit 2
}
[ -f "$file" ] || {
  printf '%s:1 [error] missing-file  no such file\n' "$file"
  exit 1
}

# Source files answer to the tree-wide recipes. The probe below sends
# bare prose, which a Go file would reject as code rather than comment,
# so it would report every source file as unscoped.
case $file in
*.go | *.py | *.sh)
  printf '%s:1 [error] wrong-recipe  source file; use just lint-prose\n' "$file"
  exit 2
  ;;
esac

rc=0

# --- the probe -------------------------------------------------------
# Bad on several axes at once, so any section with rules attached
# reports something. The contraction rules, the weasel list, and the
# AI-adjective pairs all fire independently, which is why this draws 11
# findings under every scoped path measured here.
#
# Every word is spelled correctly on purpose. Seeding it with typos
# would make the probe stronger and would also trip cspell on this
# file, and silencing that would mean adding the kind of ignore comment
# the fix-prose skill exists to refuse.
readonly CONTROL='This is a very robust and comprehensive design that does not use contractions and it is significantly better.'

probe=$(printf '%s\n' "$CONTROL" |
  vale --path="$file" --output=project-agent.tmpl 2>/dev/null |
  grep -c '^[0-9]' || true)

if [ "${probe:-0}" -eq 0 ]; then
  printf '%s:1 [error] unscoped-path  no .vale.ini section matches this path, so vale loads no styles and a silent run proves nothing; move the draft to a path the config names\n' "$file"
  rc=1
fi

# --- the gates -------------------------------------------------------
# Each runs whatever the ones before it reported. Collecting output and
# printing it together is the entire point of this script.
vale --output=project-agent.tmpl "$file" || rc=1

cspell --config .cspell.jsonc --no-summary --no-progress "$file" || rc=1

case $file in
*.md) rumdl check "$file" || rc=1 ;;
esac

exit "$rc"
