#!/usr/bin/env bash
# guard-release — PreToolUse gate on Bash, scoped to the release skill.
#
# Two invariants, and both fail quietly rather than loudly.
#
# The tag is SSH-signed inside release.yml, with a repository secret,
# under the tagger identity GitHub verifies that key against. Nothing on
# a development box reproduces any of that. A local `git tag` therefore
# mints an object that looks like a release and carries no signature,
# and `push --follow-tags` will happily send it. Refusing the tagging
# and bumping forms outright is the only reliable answer, because the
# bad tag is indistinguishable from the good one until somebody reads
# the object.
#
# A bare `gh workflow run release.yml` is the second. It reaches the
# same workflow as the task, and skips the readiness preflight and the
# version confirmation on the way -- the confirmation being the one
# thing this skill does that a task cannot. #25 exists because the
# derived version differed from the intended one and nobody looked.
#
# Reading stays open throughout. Listing tags, viewing runs, and
# inspecting a tag object all run without asking, because none of them
# can produce a release.
#
# Exit 2 blocks and hands stderr back as the reason. Verified against
# Claude Code 2.1.220: a skill-frontmatter PreToolUse hook receives the
# Bash payload with the command at .tool_input.command, and exit 2 does
# block the call.
set -euo pipefail

# --- environment hardening -------------------------------------------
# The agent reads this output, so the operator's preferences must not
# change its shape. LC_ALL pins collation, because sort and the [a-z]
# ranges below mean different things under a UTF-8 locale. The unsets
# cover variables that silently retarget a command: GH_REPO sends gh at
# another repository, CDPATH makes a relative cd print somewhere else.
export LC_ALL=C
export GH_PAGER=cat
export GH_PROMPT_DISABLED=1
export PYTHONUTF8=1
unset CDPATH GH_REPO GH_HOST GREP_OPTIONS
IFS=$' \t\n'

payload=$(cat)
command=$(jq -r '.tool_input.command // ""' <<<"$payload")

deny() {
  printf 'Blocked by the release skill guard.\n\n%s\n' "$1" >&2
  exit 2
}

# Each command in the line, one per segment, split on every separator
# that starts a new one. Matching the whole line instead would let a
# reading form shelter a writing one behind it: a bash regex reports the
# leftmost match alone, so `git tag -l && git tag -a v1 -m x` would be
# read as the listing call and the tagging call would go unexamined.
# Command substitution splits on its opening paren for the same reason.
segments=$command
segments=${segments//;/$'\n'}
segments=${segments//&/$'\n'}
segments=${segments//|/$'\n'}
segments=${segments//(/$'\n'}

readonly LOCAL_TAG_REFUSAL="The release tag is SSH-signed inside release.yml, with a repository secret,
under the tagger identity GitHub verifies that key against. Nothing here
reproduces that, so a tag made locally carries no signature while looking
exactly like one that does.

Dispatch the workflow instead, and let it tag:

  mise run release-repotools [X.Y.Z]

Then, once the run finishes:

  git fetch origin --tags
  mise run verify-repotools-release [vX.Y.Z]

Reading tags stays open: git tag with -l, -n, --points-at, --contains,
--sort, --merged, or --format, and git cat-file on the tag object, all
run without asking."

while IFS= read -r segment; do

  # --- Local tagging -------------------------------------------------
  #
  # An allowlist of the listing forms, matching how the gh guards are
  # written. Naming the reads rather than the writes means a creating
  # flag git grows later arrives already refused. A bare `git tag` lists
  # every tag, so it belongs on the reading side too.

  if [[ $segment =~ ^[[:space:]]*git[[:space:]]+tag([[:space:]]+(.*))?$ ]]; then
    args=${BASH_REMATCH[2]:-}
    case $args in
    '') ;;
    -l* | --list* | -n* | --points-at* | --contains* | --no-contains* | \
      --sort* | --merged* | --no-merged* | --format* | -v* | --verify*) ;;
    *) deny "$LOCAL_TAG_REFUSAL" ;;
    esac
  fi

  # --- Pushing tags --------------------------------------------------
  #
  # The companion to the rule above. A tag that never leaves the machine
  # harms nothing. This is the step that publishes one.

  if [[ $segment =~ ^[[:space:]]*git[[:space:]]+push ]] &&
    [[ $segment =~ (--tags|--follow-tags|refs/tags/) ]]; then
    deny "$LOCAL_TAG_REFUSAL"
  fi

  # --- Local bumping -------------------------------------------------
  #
  # Cocogitto owns the version and runs inside CI. A second bumper on a
  # development box is a second source for one number, which is how
  # numbers drift. `cog bump --dry-run` reads rather than writes, so it
  # is left alone, and readiness already calls it to report the derived
  # version.

  if [[ $segment =~ ^[[:space:]]*cog[[:space:]]+bump ]] &&
    [[ ! $segment =~ --dry-run ]]; then
    deny "\`cog bump\` writes the changelog, rewrites the version literals, commits,
and tags. It belongs to release.yml, which runs it against a clean
checkout and then signs what it produced.

  mise run release-repotools [X.Y.Z]

\`cog bump --auto --dry-run\` reads only, and stays open. Readiness
already runs it and prints the version it derives."
  fi

  # --- Dispatching around the task -----------------------------------

  if [[ $segment =~ ^[[:space:]]*gh[[:space:]]+workflow[[:space:]]+run ]] &&
    [[ $segment =~ release ]]; then
    deny "Dispatching directly skips the two gates that stand in front of a
release:

  mise run release-repotools [X.Y.Z]

That task runs the readiness preflight first and refuses on a failure,
then passes the version through. Without a version the workflow derives
one from the Conventional Commit types since the last tag, and that
number has differed from the intended one before, which is why this
skill confirms it with the operator before anything is dispatched.

\`gh workflow run\` on any other workflow is fine."
  fi

  if [[ $segment =~ ^[[:space:]]*gh[[:space:]]+api ]] &&
    [[ $segment =~ workflows/release ]] &&
    [[ $segment =~ dispatches ]]; then
    deny "That is the dispatch endpoint release.yml runs from, reached around the
task that gates it:

  bash .claude/skills/release/scripts/release-clone.sh run release-repotools [X.Y.Z]"
  fi

  # --- Release tasks outside the clone --------------------------------
  #
  # Every release task resolves its repository from the current
  # directory, so a bare `mise run` reads whatever checkout the session
  # happens to sit in. That checkout is not what gets released: the
  # workflow builds main fresh on the runner. Readiness would then
  # report a verdict about a tree nobody is releasing, and the dispatch
  # would gate on it.
  #
  # `release-clone.sh run` is the same task against a clone of the
  # release branch, which is the thing under discussion.

  if [[ $segment =~ ^[[:space:]]*mise[[:space:]] ]] &&
    [[ $segment =~ (check-repotools-release-readiness|release-repotools|verify-repotools-release) ]]; then
    deny "A release task run here reads this checkout, and this checkout is not
what gets released. The workflow builds the release branch fresh on the
runner, so a verdict about the tree in front of you describes something
else.

Run it against the clone instead:

  bash .claude/skills/release/scripts/release-clone.sh prepare
  bash .claude/skills/release/scripts/release-clone.sh run <task> [args...]

That works from any worktree, leaves this checkout untouched, and says
up front which local work the release does not carry."
  fi

done <<EOF
$segments
EOF

exit 0
