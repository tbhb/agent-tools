#!/usr/bin/env bats
#
# Tests for scripts/commitlint.sh — the bash Conventional-Commits linter
# that replaces the Go commitlint binary.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/commitlint.sh"
}

# write_msg writes its stdin to a temp file and echoes the path.
write_msg() {
  local f="${BATS_TEST_TMPDIR}/msg"
  cat >"$f"
  printf '%s' "$f"
}

# --- valid messages ---

@test "accepts a well-formed commit with body and trailers" {
  run "$SCRIPT" <<'EOF'
feat: add a working thing

A body paragraph that explains the change in enough words.

Assisted-by: claude-code:opus-4.8
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

@test "accepts a scoped, breaking-change subject" {
  run "$SCRIPT" <<'EOF'
feat(api)!: change the response envelope shape

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

@test "accepts a body-less commit with only a signoff footer" {
  run "$SCRIPT" <<'EOF'
fix: correct the off-by-one

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

# --- subject / header rules ---

@test "rejects an unknown type" {
  run "$SCRIPT" <<'EOF'
feet: do a thing in the tree

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown type"* ]]
}

@test "rejects an uppercase type as malformed" {
  run "$SCRIPT" <<'EOF'
Feat: do a thing in the tree

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"Conventional Commits"* ]]
}

@test "rejects a subject shorter than the minimum" {
  run "$SCRIPT" <<'EOF'
fix: x

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"too short"* ]]
}

@test "rejects a subject longer than the maximum" {
  local subject
  subject="feat: $(printf 'x%.0s' {1..90})"
  msg=$(printf '%s\n\nSigned-off-by: T <t@e.com>\n' "$subject" | write_msg)
  run "$SCRIPT" "$msg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"too long"* ]]
}

@test "rejects a subject with no description" {
  run "$SCRIPT" <<'EOF'
feat:

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"Conventional Commits"* ]]
}

@test "rejects a subject with no type prefix" {
  run "$SCRIPT" <<'EOF'
just some words without any type

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"Conventional Commits"* ]]
}

@test "requires a blank line after the subject" {
  run "$SCRIPT" <<'EOF'
feat: a valid subject here
body text with no blank line above it

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"blank line"* ]]
}

# --- DCO ---

@test "requires a Signed-off-by trailer" {
  run "$SCRIPT" <<'EOF'
feat: a valid subject here

A body paragraph with no signoff at all.
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"Signed-off-by"* ]]
}

# --- body / footer length caps ---

@test "rejects a body line over the 72-char cap" {
  local long
  long=$(printf 'x%.0s' {1..73})
  msg=$(printf 'feat: a valid subject here\n\n%s\n\nSigned-off-by: T <t@e.com>\n' "$long" | write_msg)
  run "$SCRIPT" "$msg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"body line"* ]]
}

@test "allows a body line at the 72-char cap" {
  local edge
  edge=$(printf 'x%.0s' {1..72})
  msg=$(printf 'feat: a valid subject here\n\n%s\n\nSigned-off-by: T <t@e.com>\n' "$edge" | write_msg)
  run "$SCRIPT" "$msg"
  [ "$status" -eq 0 ]
}

@test "holds footer lines to the looser footer cap, not the body cap" {
  local trailer
  trailer="Reviewed-by: $(printf 'x%.0s' {1..77})"
  msg=$(printf 'feat: a valid subject here\n\nA body line.\n\n%s\nSigned-off-by: T <t@e.com>\n' "$trailer" | write_msg)
  run "$SCRIPT" "$msg"
  [ "$status" -eq 0 ]
}

@test "rejects a footer line over the 100-char cap" {
  local long
  long=$(printf 'x%.0s' {1..120})
  msg=$(printf 'feat: a valid subject here\n\nA body line.\n\nReviewed-by: %s\nSigned-off-by: T <t@e.com>\n' "$long" | write_msg)
  run "$SCRIPT" "$msg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"footer line"* ]]
}

# --- stripping git scaffolding ---

@test "ignores git comment lines" {
  run "$SCRIPT" <<'EOF'
feat: a valid subject here

A body paragraph.
# Please enter the commit message for your changes.
# Lines starting with '#' will be ignored.

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

@test "ignores the verbose-diff scissors block" {
  local long
  long=$(printf 'x%.0s' {1..300})
  msg=$(printf 'feat: a valid subject here\n\nA body line.\n\nSigned-off-by: T <t@e.com>\n# ------------------------ >8 ------------------------\ndiff --git a/x b/x\n%s\n' "$long" | write_msg)
  run "$SCRIPT" "$msg"
  [ "$status" -eq 0 ]
}
