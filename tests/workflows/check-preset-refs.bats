#!/usr/bin/env bats
#
# Tests for the `check-preset-refs.mjs` script inlined in
# .github/workflows/renovate-config-validator.yaml, which verifies that
# every `github>` preset reference in a Renovate config resolves.
#
# The script is inlined in the workflow rather than committed as a file
# because `workflow_call` runs against the *caller's* checkout, where a
# file living in this repository would not exist. That constraint holds,
# so these tests extract the heredoc body from the workflow and run the
# shipped bytes rather than a copy. Extracting is also what keeps the
# suite honest: a test against a second copy would pass while the
# workflow shipped anything at all.
#
# The suite lives under tests/workflows/ rather than a literal mirror of
# .github/workflows/, because `bats --recursive tests` never descends
# into a dot directory.
#
# Two stubs stand in for what the script reaches for. `json5` resolves
# out of the Renovate image, which no development box has, so a stub on
# NODE_PATH answers the same require -- fixtures here are therefore
# strict JSON, which is valid JSON5 either way. And GITHUB_API_URL points
# at a local server rather than github.com, so the assertions cover which
# request the script makes rather than what some repository happens to
# hold today.
#
# The case the suite exists for is "a pinned reference is checked at that
# ref". Its control is a preset present on the default branch and absent
# at the pinned ref: without that case a passing test cannot tell the fix
# from the bug it replaced, since both report `ok` for a path that exists
# on main.

setup() {
  WORKFLOW="${BATS_TEST_DIRNAME}/../../.github/workflows/renovate-config-validator.yaml"
  SCRIPT="${BATS_TEST_TMPDIR}/check-preset-refs.mjs"
  POLICY="${BATS_TEST_TMPDIR}/policy"
  REQUESTS="${BATS_TEST_TMPDIR}/requests"
  WORK="${BATS_TEST_TMPDIR}/work"

  extract_script

  # A require of `json5` that answers without the Renovate image. The
  # script reaches it through the image's module path, and every lookup
  # that misses falls through to NODE_PATH.
  mkdir -p "${BATS_TEST_TMPDIR}/node_modules/json5"
  printf '{"name":"json5","version":"0.0.0","main":"index.js"}\n' \
    > "${BATS_TEST_TMPDIR}/node_modules/json5/package.json"
  printf 'module.exports = { parse: (text) => JSON.parse(text) };\n' \
    > "${BATS_TEST_TMPDIR}/node_modules/json5/index.js"
  export NODE_PATH="${BATS_TEST_TMPDIR}/node_modules"

  : > "$POLICY"
  : > "$REQUESTS"
  start_stub_api

  mkdir -p "$WORK/.github"
  cd "$WORK"
  export GITHUB_REPOSITORY="tbhb/consumer"
  unset GH_TOKEN
}

teardown() {
  [ -n "${STUB_PID:-}" ] && kill "$STUB_PID" 2>/dev/null
  return 0
}

# Lift the heredoc body out of the workflow, stripping the indentation
# the YAML block scalar carries and the shell never sees.
extract_script() {
  cat > "${BATS_TEST_TMPDIR}/extract.awk" <<'AWK'
/<<'MJS'/ && !seen { match($0, /^ */); indent = RLENGTH; seen = 1; capture = 1; next }
capture && substr($0, indent + 1) == "MJS" { capture = 0; next }
capture { print substr($0, indent + 1) }
AWK
  awk -f "${BATS_TEST_TMPDIR}/extract.awk" "$WORKFLOW" > "$SCRIPT"
  [ -s "$SCRIPT" ]
}

# A stand-in for the contents API. It re-reads the policy file on every
# request, so a test declares what exists after the server is already
# up, and it records each URL so a test can assert on the request rather
# than only on the verdict.
start_stub_api() {
  cat > "${BATS_TEST_TMPDIR}/stub-api.mjs" <<'MJS'
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";

const [policyFile, requestLog, portFile] = process.argv.slice(2);

const server = createServer((request, response) => {
  appendFileSync(requestLog, `${request.url}\n`);
  const url = new URL(request.url, "http://stub");
  const key = `${url.pathname}@${url.searchParams.get("ref") ?? ""}`;
  const allowed = readFileSync(policyFile, "utf8").split("\n");
  response.writeHead(allowed.includes(key) ? 200 : 404, {
    "content-type": "application/json",
  });
  response.end("{}");
});

server.listen(0, "127.0.0.1", () => {
  writeFileSync(portFile, String(server.address().port));
});
MJS
  local port_file="${BATS_TEST_TMPDIR}/port"
  node "${BATS_TEST_TMPDIR}/stub-api.mjs" "$POLICY" "$REQUESTS" "$port_file" &
  STUB_PID=$!
  # Off the job table, so teardown's kill does not print a termination
  # notice into the middle of the run.
  disown "$STUB_PID" 2>/dev/null || true
  local waited=0
  while [ ! -s "$port_file" ]; do
    sleep 0.05
    waited=$((waited + 1))
    [ "$waited" -lt 100 ] || {
      echo "stub API never bound a port" >&2
      return 1
    }
  done
  export GITHUB_API_URL="http://127.0.0.1:$(cat "$port_file")"
}

# Declare that $1 exists at ref $2, where an empty $2 is the default
# branch.
serves() {
  printf '/repos/%s/contents/%s@%s\n' "tbhb/repotools" "$1" "${2-}" >> "$POLICY"
}

# A config extending everything passed to it.
config_extending() {
  local refs="" entry
  for entry in "$@"; do
    refs="${refs}${refs:+, }\"${entry}\""
  done
  printf '{"extends": [%s]}\n' "$refs" > .github/renovate.json5
}

check() {
  run node "$SCRIPT" .github/renovate.json5
}

PRESET=".github/renovate-config.json5"
SHA="0123456789abcdef0123456789abcdef01234567"

@test "an unpinned reference resolves against the default branch" {
  config_extending "github>tbhb/repotools//${PRESET}"
  serves "$PRESET" ""

  check
  [ "$status" -eq 0 ]
  [[ $output == *"ok    tbhb/repotools//${PRESET} (default branch)"* ]]
  # No ref went out with it, so the answer really was the default branch.
  [[ $(cat "$REQUESTS") != *"ref="* ]]
}

@test "a reference pinned to a commit is checked at that commit" {
  config_extending "github>tbhb/repotools//${PRESET}#${SHA}"
  serves "$PRESET" "$SHA"

  check
  [ "$status" -eq 0 ]
  [[ $output == *"ok    tbhb/repotools//${PRESET} (ref ${SHA})"* ]]
  [[ $(cat "$REQUESTS") == *"ref=${SHA}"* ]]
}

@test "a reference pinned to a tag is checked at that tag" {
  config_extending "github>tbhb/repotools//${PRESET}#v0.5.0"
  serves "$PRESET" "v0.5.0"

  check
  [ "$status" -eq 0 ]
  [[ $output == *"ok    tbhb/repotools//${PRESET} (ref v0.5.0)"* ]]
}

@test "a preset absent at the pinned ref fails though the default branch carries it" {
  config_extending "github>tbhb/repotools//${PRESET}#${SHA}"
  serves "$PRESET" ""

  check
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  tbhb/repotools//${PRESET} (ref ${SHA}, HTTP 404)"* ]]
}

@test "a ref that does not exist fails" {
  config_extending "github>tbhb/repotools//${PRESET}#v9.9.9"

  check
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  tbhb/repotools//${PRESET} (ref v9.9.9, HTTP 404)"* ]]
}

@test "an unrecognized shape fails rather than being skipped" {
  config_extending "github>tbhb/repotools:some-preset"

  check
  [ "$status" -eq 1 ]
  [[ $output == *"unrecognized reference shape"* ]]
}

@test "an unpinned self-reference is checked against the PR tree" {
  export GITHUB_REPOSITORY="tbhb/repotools"
  config_extending "github>tbhb/repotools//${PRESET}"
  printf '{}\n' > "$PRESET"

  check
  [ "$status" -eq 0 ]
  [[ $output == *"(this repo, PR tree)"* ]]
  [ ! -s "$REQUESTS" ]
}

@test "an unpinned self-reference missing from the PR tree fails" {
  export GITHUB_REPOSITORY="tbhb/repotools"
  config_extending "github>tbhb/repotools//${PRESET}"

  check
  [ "$status" -eq 1 ]
  [[ $output == *"(not in this PR's tree)"* ]]
}

@test "a pinned self-reference is checked at its ref rather than in the PR tree" {
  export GITHUB_REPOSITORY="tbhb/repotools"
  config_extending "github>tbhb/repotools//${PRESET}#${SHA}"
  # Present in the tree and absent at the ref: the PR-tree branch would
  # report this green.
  printf '{}\n' > "$PRESET"

  check
  [ "$status" -eq 1 ]
  [[ $output == *"FAIL  tbhb/repotools//${PRESET} (ref ${SHA}, HTTP 404)"* ]]
}

@test "a pinned self-reference resolves where the ref carries the preset" {
  export GITHUB_REPOSITORY="tbhb/repotools"
  config_extending "github>tbhb/repotools//${PRESET}#${SHA}"
  serves "$PRESET" "$SHA"

  check
  [ "$status" -eq 0 ]
  [[ $output == *"ok    tbhb/repotools//${PRESET} (ref ${SHA})"* ]]
}
