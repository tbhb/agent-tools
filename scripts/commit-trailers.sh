#!/usr/bin/env bash
# commit-trailers — enforce the AI-assistant trailer rules a
# Conventional-Commits linter doesn't cover. The rules follow the Linux
# kernel coding-assistants policy
# (https://docs.kernel.org/process/coding-assistants.html), with one
# override: the kernel forbids an AI assistant from adding its own
# Signed-off-by; these repositories allow it because the human committer
# still owns the DCO.
#
#   Rule 1: An Assisted-by value must match the kernel-style format
#           AGENT_NAME:MODEL_VERSION [TOOL...].
#   Rule 2: When both Assisted-by and Signed-off-by appear, Assisted-by
#           must come first.
#   Rule 3: A Co-authored-by trailer attributing the work to a known LLM
#           is rejected; LLM attribution belongs in Assisted-by.
#   Rule 4: A Signed-off-by trailer is required. commitlint also checks
#           this, so the DCO gate holds even when commitlint is skipped.
#
# Reads the commit message from the file named by $1, or from stdin when
# no argument is given. The commit-msg hook passes the buffer path as $1.
set -euo pipefail

# Rule 1: agent name (lowercase, dashes, digits), colon, model version,
# then optional space-separated tool names. Conservative enough to reject
# the older slash form and trailing punctuation.
readonly ASSISTED_BY_FORMAT='^[a-z0-9][a-z0-9-]*:[a-z0-9][a-z0-9.-]*( [a-z0-9][a-z0-9.-]*)*$'

# Rule 3: marks a Co-authored-by value as an LLM. grep -iwE gives the
# same whole-word, case-insensitive semantics as the Go port's
# (?i)\b(...)\b — grep's word characters match Go's \w, so "ai" fires on
# a standalone token but not inside "email".
readonly LLM_AUTHOR_PATTERN='(claude|chatgpt|copilot|gpt|gemini|bard|anthropic|openai|ai|llm)'

# trim strips leading and trailing whitespace from $1.
trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

# report writes one violation to stderr under the command prefix.
report() {
  printf 'commit-trailers: %s\n' "$1" >&2
}

main() {
  local message
  if [ "$#" -ge 1 ]; then
    message=$(cat -- "$1")
  else
    message=$(cat)
  fi

  local -i failed=0 lineno=0 assisted_at=0 signed_at=0
  local line value credit

  while IFS= read -r line || [ -n "$line" ]; do
    lineno+=1
    case $line in
    'Assisted-by:'*)
      if [ "$assisted_at" -eq 0 ]; then assisted_at=$lineno; fi
      value=$(trim "${line#'Assisted-by:'}")
      if [[ ! $value =~ $ASSISTED_BY_FORMAT ]]; then
        report "malformed Assisted-by value: expected AGENT_NAME:MODEL_VERSION [TOOL...] (line ${lineno}: \"${value}\")"
        failed=1
      fi
      ;;
    'Signed-off-by:'*)
      if [ "$signed_at" -eq 0 ]; then signed_at=$lineno; fi
      ;;
    'Co-authored-by:'*)
      credit=$(trim "${line#'Co-authored-by:'}")
      if grep -iqwE "$LLM_AUTHOR_PATTERN" <<<"$credit"; then
        report "forbidden Co-authored-by attribution to an LLM; use Assisted-by instead (line ${lineno}: \"${credit}\")"
        failed=1
      fi
      ;;
    esac
  done <<<"$message"

  if [ "$assisted_at" -gt 0 ] && [ "$signed_at" -gt 0 ] && [ "$assisted_at" -gt "$signed_at" ]; then
    report "trailer order: Assisted-by must appear before Signed-off-by (line ${assisted_at} after line ${signed_at})"
    failed=1
  fi

  if [ "$signed_at" -eq 0 ]; then
    report "missing required Signed-off-by trailer (DCO)"
    failed=1
  fi

  return "$failed"
}

main "$@"
