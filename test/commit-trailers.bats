#!/usr/bin/env bats
#
# Behavioral parity tests for scripts/commit-trailers.sh, mirroring the
# table cases from the Go trailers package the script replaces.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/commit-trailers.sh"
}

# --- Rule 1: Assisted-by format ---

@test "passes a message carrying only a sign-off" {
  run "$SCRIPT" <<'EOF'
feat: a change

A body paragraph with no assistant trailers.

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

@test "accepts a well-formed Assisted-by value" {
  run "$SCRIPT" <<'EOF'
feat: a change

Assisted-by: claude-code:opus-4.8
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

@test "accepts an Assisted-by value with trailing tool names" {
  run "$SCRIPT" <<'EOF'
feat: a change

Assisted-by: claude:opus-4.8 claude-code zed
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

@test "rejects the older slash-form Assisted-by value" {
  run "$SCRIPT" <<'EOF'
feat: a change

Assisted-by: claude-code/opus
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed Assisted-by value"* ]]
  [[ "$output" == *"line 3"* ]]
}

@test "rejects an uppercase Assisted-by agent name" {
  run "$SCRIPT" <<'EOF'
feat: a change

Assisted-by: Claude:Opus
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed Assisted-by value"* ]]
}

@test "rejects an Assisted-by value with trailing punctuation" {
  # The model field allows dots and dashes (version strings like 4.8),
  # so faithfulness to the Go regex means a trailing comma or colon is
  # rejected while a trailing dot is not. Dotted versions are covered by
  # the well-formed cases above.
  run "$SCRIPT" <<'EOF'
feat: a change

Assisted-by: claude-code:opus-4.8,
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
}

# --- Rule 3: Co-authored-by LLM attribution ---

@test "accepts a human Co-authored-by" {
  run "$SCRIPT" <<'EOF'
feat: a change

Co-authored-by: Jane Doe <jane@example.com>
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

@test "does not flag 'ai' inside ordinary words" {
  run "$SCRIPT" <<'EOF'
feat: a change

Co-authored-by: Kai Mailer <kai@example.com>
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

@test "rejects a Co-authored-by crediting an LLM by name" {
  run "$SCRIPT" <<'EOF'
feat: a change

Co-authored-by: Claude <noreply@anthropic.com>
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"forbidden Co-authored-by attribution to an LLM"* ]]
}

@test "rejects a standalone 'ai' Co-authored-by token" {
  run "$SCRIPT" <<'EOF'
feat: a change

Co-authored-by: ai <ai@example.com>
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
}

# --- Rule 2: trailer order ---

@test "accepts Assisted-by before Signed-off-by" {
  run "$SCRIPT" <<'EOF'
feat: a change

Assisted-by: claude-code:opus-4.8
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

@test "rejects Signed-off-by before Assisted-by" {
  run "$SCRIPT" <<'EOF'
feat: a change

Signed-off-by: Tony Burns <tony@example.com>
Assisted-by: claude-code:opus-4.8
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"Assisted-by must appear before Signed-off-by"* ]]
}

@test "ignores order when only one of the two trailers is present" {
  run "$SCRIPT" <<'EOF'
feat: a change

Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 0 ]
}

# --- Rule 4: required Signed-off-by ---

@test "rejects a message with no Signed-off-by" {
  run "$SCRIPT" <<'EOF'
feat: a change

A body paragraph with an assist trailer but no sign-off.

Assisted-by: claude-code:opus-4.8
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required Signed-off-by"* ]]
}

# --- Aggregation and input handling ---

@test "reports every violation in one run" {
  run "$SCRIPT" <<'EOF'
feat: a change

Assisted-by: bad/value
Co-authored-by: gpt <gpt@example.com>
Signed-off-by: Tony Burns <tony@example.com>
EOF
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed Assisted-by value"* ]]
  [[ "$output" == *"forbidden Co-authored-by attribution to an LLM"* ]]
}

@test "reads the message from a file argument" {
  msg="${BATS_TEST_TMPDIR}/msg"
  cat >"$msg" <<'EOF'
feat: a change

Assisted-by: claude-code:opus-4.8
Signed-off-by: Tony Burns <tony@example.com>
EOF
  run "$SCRIPT" "$msg"
  [ "$status" -eq 0 ]
}
