#!/usr/bin/env bash
# commitlint — a Conventional-Commits linter for the commit-msg hook,
# written in bash to replace the Go commitlint binary. It enforces the
# rules the retired .commitlint.yaml carried (a known type, header length
# bounds, body and footer line-length caps, and a required Signed-off-by
# trailer) plus the structural Conventional-Commits checks cog leaves
# out: a "<type>(<scope>)?(!)?: <description>" subject with a recognized
# type and a non-empty description, and a blank line between the subject
# and the body.
#
# Reads the commit message from the file named by $1, or from stdin when
# no argument is given. The commit-msg hook passes the buffer path as $1.
# git's helper comments (lines beginning with #) and any verbose-diff
# scissors block are stripped first so the diff and the "# Please
# enter..." preamble never count as body lines. The stripping is pure
# awk (no `git stripspace`) so the hook needs no git, which keeps it
# runnable in a minimal container; it assumes the default # comment char.
set -euo pipefail

# Rule parameters. The header and footer bounds match the retired
# .commitlint.yaml; the body cap follows the 72-column wrap
# convention so an over-length body line fails mechanically instead of
# slipping past review. Each is overridable so a consumer repo can
# retune without editing the script.
readonly HEADER_MIN_LENGTH=${COMMITLINT_HEADER_MIN_LENGTH:-10}
readonly HEADER_MAX_LENGTH=${COMMITLINT_HEADER_MAX_LENGTH:-80}
readonly BODY_MAX_LINE_LENGTH=${COMMITLINT_BODY_MAX_LINE_LENGTH:-72}
readonly FOOTER_MAX_LINE_LENGTH=${COMMITLINT_FOOTER_MAX_LINE_LENGTH:-100}
readonly REQUIRE_SIGNED_OFF_BY=${COMMITLINT_REQUIRE_SIGNED_OFF_BY:-1}
readonly TYPES_DEFAULT="feat fix docs style refactor perf test build ci chore revert"

# Regexes live in variables because [[ =~ ]] mis-parses a literal pattern
# that contains parentheses; referencing the variable unquoted feeds the
# whole string to the regex engine intact.
readonly HEADER_RE='^([a-z]+)(\([^)]+\))?(!)?: (.+)$'
readonly TRAILER_RE='^([A-Za-z0-9][A-Za-z0-9-]*|BREAKING[ -]CHANGE): .+$'
readonly CONTINUATION_RE='^[[:space:]]+[^[:space:]]'
readonly SIGNOFF_RE='^Signed-off-by: .+$'

errors=()
err() { errors+=("$1"); }

# is_trailer reports whether a line is a git trailer (Token: value, or
# BREAKING CHANGE: value) or a folded continuation of one.
is_trailer() {
  [[ $1 =~ $TRAILER_RE ]] || [[ $1 =~ $CONTINUATION_RE ]]
}

# strip_message normalizes the raw buffer on stdin the way git's own
# cleanup would: it cuts the verbose-diff scissors block, drops comment
# lines, trims trailing whitespace, collapses blank runs, and removes
# leading and trailing blank lines. Pure awk so the hook carries no git
# dependency.
strip_message() {
  awk '
    /^[#;] *-+ *>8 *-+ *$/ { exit }
    /^#/ { next }
    { sub(/[[:space:]]+$/, "") }
    /^$/ { if (started) pending = 1; next }
    { if (pending) { print ""; pending = 0 }; started = 1; print }
  '
}

# check_header validates the subject line against the length bounds and
# the Conventional-Commits shape.
check_header() {
  local header=$1
  local -i len=${#header}
  if [ "$len" -lt "$HEADER_MIN_LENGTH" ]; then
    err "subject is too short (${len} < ${HEADER_MIN_LENGTH}): \"${header}\""
  fi
  if [ "$len" -gt "$HEADER_MAX_LENGTH" ]; then
    err "subject is too long (${len} > ${HEADER_MAX_LENGTH}): \"${header}\""
  fi

  if [[ ! $header =~ $HEADER_RE ]]; then
    err "subject must follow Conventional Commits: <type>(<scope>)?(!)?: <description>"
    return
  fi
  # A matched header guarantees a non-empty description: the regex
  # requires at least one character after ": ", and git stripspace has
  # already removed any trailing whitespace, so the description cannot be
  # blank here. An empty "feat:" fails the format check above instead.
  local type=${BASH_REMATCH[1]}

  local -a types
  read -r -a types <<<"${COMMITLINT_TYPES:-$TYPES_DEFAULT}"
  local t found=0
  for t in "${types[@]}"; do
    if [ "$type" = "$t" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    local allowed
    printf -v allowed '%s, ' "${types[@]}"
    err "unknown type \"${type}\"; allowed: ${allowed%, }"
  fi
}

main() {
  local raw stripped
  if [ "$#" -ge 1 ]; then raw=$(cat -- "$1"); else raw=$(cat); fi
  stripped=$(printf '%s\n' "$raw" | strip_message)

  local -a lines=()
  local line
  while IFS= read -r line || [ -n "$line" ]; do lines+=("$line"); done <<<"$stripped"
  local -i n=${#lines[@]}

  check_header "${lines[0]}"

  # Conventional Commits requires a blank line between the subject and
  # the body.
  if [ "$n" -gt 1 ] && [ -n "${lines[1]}" ]; then
    err "the subject must be separated from the body by a blank line"
  fi

  # Partition the content after the subject's blank line into a body
  # region and a trailing footer (git-trailer) block, then apply the
  # per-region line-length caps. footer_start is the array index where
  # the footer begins, or -1 when no distinct footer block is found.
  local -i last=$((n - 1))
  while [ "$last" -ge 2 ] && [ -z "${lines[$last]}" ]; do last=$((last - 1)); done

  local -i footer_start=-1
  if [ "$last" -ge 2 ]; then
    local -i j=$last
    while [ "$j" -ge 2 ] && is_trailer "${lines[$j]}"; do j=$((j - 1)); done
    if [ "$j" -lt 2 ]; then
      footer_start=2
    elif [ -z "${lines[$j]}" ]; then
      footer_start=$((j + 1))
    fi
  fi

  local -i i len
  for ((i = 2; i <= last; i++)); do
    if [ -z "${lines[$i]}" ]; then continue; fi
    len=${#lines[$i]}
    if [ "$footer_start" -ge 0 ] && [ "$i" -ge "$footer_start" ]; then
      if [ "$len" -gt "$FOOTER_MAX_LINE_LENGTH" ]; then
        err "footer line $((i + 1)) exceeds ${FOOTER_MAX_LINE_LENGTH} chars (${len})"
      fi
    elif [ "$len" -gt "$BODY_MAX_LINE_LENGTH" ]; then
      err "body line $((i + 1)) exceeds ${BODY_MAX_LINE_LENGTH} chars (${len})"
    fi
  done

  if [ "$REQUIRE_SIGNED_OFF_BY" -eq 1 ]; then
    local l found=0
    for l in "${lines[@]}"; do
      if [[ $l =~ $SIGNOFF_RE ]]; then
        found=1
        break
      fi
    done
    if [ "$found" -eq 0 ]; then
      err "missing required Signed-off-by trailer (DCO)"
    fi
  fi

  if [ "${#errors[@]}" -gt 0 ]; then
    local e
    for e in "${errors[@]}"; do printf 'commitlint: %s\n' "$e" >&2; done
    return 1
  fi
}

main "$@"
