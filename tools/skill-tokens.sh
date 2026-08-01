#!/usr/bin/env bash
# skill-tokens — measure what a skill costs in context, and record it
# beside the skill.
#
# The two halves of a skill are paid for differently. A frontmatter
# description sits in context for every turn of every session, whether
# or not anyone invokes the skill, so its cost is constant and shared.
# The body loads only on invocation, and a bundled script costs nothing
# until something reads it. Measuring them together hides that split,
# so this reports each separately.
#
# Counts come from the real tokenizer through the ant CLI rather than
# from a characters-per-token guess. Claude Opus 4.7 and later use a
# tokenizer that yields roughly 30 percent more tokens than earlier
# models for the same text, which puts any remembered estimate well out
# of date.
#
# Each request carries a fixed envelope of its own. A baseline call
# measures it once, and every figure below has it subtracted, so what
# lands in the JSON is the text alone.
#
# The body budget is the platform's own guidance: keep the SKILL.md body
# under 5k tokens and push reference material into bundled files, which
# cost nothing until something reads them. Exceeding it is a warning
# rather than a refusal, because the number is a recommendation and no
# upload rejects a body for being long. The hard limits on name and
# description live in tools/skill-limits.sh, which stays offline.
#
# Usage: skill-tokens.sh [skill-dir ...]     (default: .apm/skills/*/)
# Env:   MODEL to count against another model.
#        BODY_BUDGET to move the warning threshold.
set -euo pipefail

readonly BODY_BUDGET=${BODY_BUDGET:-5000}

MODEL=${MODEL:-claude-opus-5}
export MODEL

root=$(git rev-parse --show-toplevel)
cd "$root"

command -v ant >/dev/null 2>&1 || {
  printf 'skill-tokens: ant is not installed. See the Claude Developer Platform CLI.\n' >&2
  exit 1
}

# One scratch area for the whole run, cleaned once. The loop below used
# to set and clear its own trap per skill, which would have dropped this
# one on the first pass.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
request="$scratch/request.yaml"

# count prints the token count of the text on stdin. The text goes in as
# a YAML literal block, which survives punctuation that would otherwise
# need quoting.
#
# The request is written to a file and redirected rather than piped in.
# ant decides at startup whether stdin carries a request, and a producer
# slower to start than ant loses that race: ant sees an empty pipe,
# concludes nothing was piped, and asks for the flags instead.
count() {
  python3 -c '
import os, sys
print("model: " + os.environ["MODEL"])
print("messages:")
print("  - role: user")
print("    content: |")
for line in sys.stdin.read().split("\n"):
    print("      " + line)
' >"$request"
  ant messages count-tokens <"$request" 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["input_tokens"])'
}

# The envelope every request pays, measured with a one-token payload.
baseline=$(printf 'x' | count) || {
  printf 'skill-tokens: the ant call failed. Check what ant auth status reports.\n' >&2
  exit 1
}
baseline=$((baseline - 1))
printf 'model %s, request envelope %s tokens\n\n' "$MODEL" "$baseline"

# net prints the token count of a file with the envelope removed.
net() {
  local raw
  raw=$(count <"$1")
  printf '%s\n' "$((raw - baseline))"
}

budget_exceeded=0
dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then
  dirs=(.apm/skills/*/)
fi

for dir in "${dirs[@]}"; do
  dir=${dir%/}
  skill=$(basename "$dir")
  manifest="$dir/SKILL.md"
  [ -f "$manifest" ] || {
    printf 'skip %s: no SKILL.md\n' "$dir" >&2
    continue
  }

  # Split the manifest so the always-loaded part can be told apart from
  # the part that loads on invocation.
  tmp="$scratch/split"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  python3 - "$manifest" "$tmp" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
out = pathlib.Path(sys.argv[2])
m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
frontmatter, body = (m.group(1), m.group(2)) if m else ("", text)
d = re.search(r"^description: >-\n((?:  .*\n)+)", frontmatter, re.M)
description = re.sub(r"\s+", " ", d.group(1)).strip() if d else ""
(out / "frontmatter").write_text(frontmatter)
(out / "body").write_text(body)
(out / "description").write_text(description)
PY

  total=$(net "$manifest")
  fm=$(net "$tmp/frontmatter")
  desc=$(net "$tmp/description")
  body=$(net "$tmp/body")

  # Bundled files, which cost nothing until something opens them.
  bundled=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    bundled="${bundled}${file}	$(net "$file")	$(wc -c <"$file" | tr -d ' ')
"
  done <<EOF
$(find "$dir" -type f ! -name SKILL.md ! -name tokens.json | sort)
EOF

  MODEL="$MODEL" SKILL="$skill" SKILL_DIR="$dir" TOTAL="$total" FM="$fm" DESC="$desc" BODY="$body" \
    BUNDLED="$bundled" MANIFEST_BYTES="$(wc -c <"$manifest" | tr -d ' ')" \
    python3 - "$dir/tokens.json" <<'PY'
import json, os, sys

rows = []
for line in os.environ["BUNDLED"].split("\n"):
    if not line.strip():
        continue
    path, tokens, size = line.split("\t")
    # Relative to the skill directory, so the record reads the same in
    # the .apm source and in the copy apm deploys under .claude.
    rows.append({
        "path": os.path.relpath(path, os.environ["SKILL_DIR"]),
        "tokens": int(tokens),
        "bytes": int(size),
    })

# No timestamp on purpose. This file is a deployed artifact, and a
# regenerated timestamp would read as drift to the packaging gate on
# every run even when nothing about the skill changed.
doc = {
    "skill": os.environ["SKILL"],
    "model": os.environ["MODEL"],
    "generated_by": "tools/skill-tokens.sh",
    "manifest": {
        "tokens": int(os.environ["TOTAL"]),
        "bytes": int(os.environ["MANIFEST_BYTES"]),
        "frontmatter_tokens": int(os.environ["FM"]),
        "body_tokens": int(os.environ["BODY"]),
    },
    "always_loaded": {
        "description_tokens": int(os.environ["DESC"]),
    },
    "bundled_files": rows,
    "bundled_files_tokens": sum(r["tokens"] for r in rows),
}
with open(sys.argv[1], "w") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

  over=""
  if [ "$body" -ge "$BODY_BUDGET" ]; then
    over="  OVER the ${BODY_BUDGET}-token body budget"
    budget_exceeded=1
  fi
  printf '%-24s description %5s   manifest %6s   bundled %6s%s\n' \
    "$skill" "$desc" "$total" \
    "$(printf '%s' "$bundled" | awk -F'\t' '{ s += $2 } END { print s + 0 }')" "$over"

done

printf '\nDescriptions load every turn. Manifests load on invocation.\n'
printf 'Bundled files cost nothing until something reads them.\n'

if [ "$budget_exceeded" = 1 ]; then
  printf '\nAt least one body sits past the %s-token budget. Move reference\n' "$BODY_BUDGET"
  printf 'material into a bundled file, which costs nothing until read.\n'
fi
