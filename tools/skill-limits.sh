#!/usr/bin/env bash
# skill-limits — check every skill against the limits the platform
# actually enforces.
#
# Two of these are hard limits. A skill whose name or description
# exceeds them is rejected at upload rather than degraded, and the
# failure surfaces far from the edit that caused it, so catching them
# here costs nothing and saves a confusing round trip:
#
#   name         64 characters, lowercase letters, numbers, and hyphens
#                only, no XML tags, and neither reserved word
#   description  non-empty, 1024 characters, no XML tags
#
# The body budget is a recommendation rather than a limit, and it is
# measured in tokens, so tools/skill-tokens.sh carries that check where
# the real counts already are. This script stays offline so `mise run lint`
# needs no network.
#
# Findings print one per line in the shape the vale template uses.
# Silence means a clean run.
set -euo pipefail

# --- environment hardening -------------------------------------------
# Output here feeds an agent and a committed artifact, so the operator's
# locale must not reorder it. PYTHONUTF8 is the companion: under LC_ALL=C
# python would otherwise read these files as ASCII and raise on the first
# non-ASCII character.
export LC_ALL=C
export PYTHONUTF8=1
unset CDPATH GREP_OPTIONS
IFS=$' \t\n'

readonly NAME_MAX=64
readonly DESC_MAX=1024

root=$(git rev-parse --show-toplevel)
cd "$root"

findings=0
report() {
  printf '%s [error] %s  %s\n' "$1" "$2" "$3"
  findings=$((findings + 1))
}

dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then
  dirs=(.apm/skills/*/)
fi

for dir in "${dirs[@]}"; do
  dir=${dir%/}
  manifest="$dir/SKILL.md"
  [ -f "$manifest" ] || continue

  # Read the two fields out of the frontmatter. The description is a
  # folded block, so it needs unfolding before its length means
  # anything.
  #
  # Cleared first, and the exit status checked. Without both, a python
  # block that fails evaluates to nothing and the variables keep the
  # previous iteration's values, so this reports a clean pass for a
  # skill it never read.
  skill_name=""
  skill_desc=""
  fields=$(
    python3 - "$manifest" <<'PY'
import pathlib, re, shlex, sys
text = pathlib.Path(sys.argv[1]).read_text()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
fm = m.group(1) if m else ""
name = ""
n = re.search(r"^name:[ \t]*(.+)$", fm, re.M)
if n:
    name = n.group(1).strip()
desc = ""
d = re.search(r"^description: >-\n((?:[ \t]+.*\n)+)", fm, re.M)
if d:
    desc = re.sub(r"\s+", " ", d.group(1)).strip()
else:
    d = re.search(r"^description:[ \t]*(.+)$", fm, re.M)
    if d:
        desc = d.group(1).strip()
print("skill_name=" + shlex.quote(name))
print("skill_desc=" + shlex.quote(desc))
PY
  ) || {
    report "$manifest:1" unreadable "could not parse the frontmatter"
    continue
  }
  eval "$fields"

  if [ -z "$skill_name" ]; then
    report "$manifest:1" name-missing "the frontmatter sets no name"
  else
    if [ "${#skill_name}" -gt "$NAME_MAX" ]; then
      report "$manifest:1" name-too-long \
        "the name runs ${#skill_name} characters, past the ${NAME_MAX} the platform allows"
    fi
    case $skill_name in
    *[!a-z0-9-]*)
      report "$manifest:1" name-charset \
        "\"${skill_name}\" holds something outside lowercase letters, numbers, and hyphens"
      ;;
    esac
    case $skill_name in
    *anthropic* | *claude*)
      report "$manifest:1" name-reserved \
        "\"${skill_name}\" carries a reserved word; the platform rejects anthropic and claude"
      ;;
    esac
  fi

  if [ -z "$skill_desc" ]; then
    report "$manifest:1" description-missing "the frontmatter sets no description"
  elif [ "${#skill_desc}" -gt "$DESC_MAX" ]; then
    report "$manifest:1" description-too-long \
      "the description runs ${#skill_desc} characters, past the ${DESC_MAX} the platform allows"
  fi

  case $skill_name$skill_desc in
  *"<"*">"*)
    report "$manifest:1" xml-tags "the name or description holds what reads as an XML tag"
    ;;
  esac
done

if [ "$findings" -gt 0 ]; then
  printf 'TOTAL: %s finding(s)\n' "$findings"
  exit 1
fi
