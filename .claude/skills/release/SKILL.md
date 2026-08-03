---
name: release
description: >-
  Release this repository end to end. Run the readiness preflight, settle the version number and confirm it, dispatch the release workflow, wait for the run to land, and verify the tag it produced. Use this whenever the operator asks to release, cut, publish, or tag a version of repotools, with or without a number named, as in "release 0.5.1," "go cut a release," "publish v0.6.0," or "is this ready to release." The tag is made and SSH-signed inside CI and nothing local reproduces that, so this dispatches and waits rather than tagging. Called without a version it reports the number the automatic path would derive and confirms it before anything is dispatched, because that number comes from the commit types since the last tag and has differed from the one intended.
argument-hint: "[X.Y.Z]"
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "${CLAUDE_PROJECT_DIR}/.claude/skills/release/scripts/guard-release.sh"
---

# Release repotools

Drive a release of this repository from readiness to a verified tag.

This skill orchestrates three tasks that already exist rather than writing them again. `check-repotools-release-readiness` reports, `release-repotools` dispatches, `verify-repotools-release` checks the result. Finding yourself writing what one of those does is the signal to stop and call it instead.

The release happens inside `.github/workflows/release.yml` and nowhere else. Cocogitto derives the version and writes the changelog. It rewrites the published version literals before committing and tagging. The workflow then replaces cog's lightweight tag with an SSH-signed annotated one and pushes both. The signing key is a repository secret and GitHub verifies it server-side against the tagger identity, so no local command produces the same object. A guard hook runs alongside this skill and refuses local tagging, local bumping, and a dispatch that goes around the task.

Nothing here edits a changelog or moves a version pin by hand. Cog owns both. Where a commit does turn out to be necessary, it goes through the `commit` skill, which owns the draft file, the trailers, and the gates.

## Which version

`$ARGUMENTS` carries the version when the operator named one. Strip a leading `v` before passing it on, since `release.yml` hands the value to `cog bump --version`, which takes a bare `X.Y.Z` and would otherwise put the letter into the tag twice.

Anything that's not three dot-separated numbers after that stops the run. Say what the operator gave and ask for the version rather than guessing at it. The dispatch task validates the same shape and is the backstop, not the first line.

An empty `$ARGUMENTS` means the version is still open. Step 2 determines it.

## Step 1: readiness

```text
mise run check-repotools-release-readiness
```

It prints one `OK` or `FAIL` line per check and an `INFO` line carrying the version `cog bump --auto` would derive. Read both.

On a failure, name the checks that failed and what each one said, then stop. "Not ready" on its own sends the operator looking for the reason this task already printed. Fix nothing: readiness reports and never writes, and a session that cleans the tree on the way to answering a question has answered a different question.

The common failures and what they mean:

- `working tree clean`. Uncommitted work would not reach the release, and cog refuses a dirty tree anyway.
- `HEAD is origin/main`. This checkout stands somewhere other than the commit the release branch points at, so the operator's picture of what the workflow would tag is wrong. The check compares commits rather than branch names, so any branch name passes it and so does a detached `HEAD`. Landing the outstanding work and moving onto that commit is the fix, never a dispatch anyway.
- `version literals name the latest tag`. A published literal has drifted from the last tag. `cog.toml`'s pre-bump hooks rewrite those during a bump, so a failure here means a site nothing rewrites.
- `checks green on HEAD`. A commit with no checks reported fails this too, deliberately. The bump commit itself goes out under `--skip-ci`, so "nothing reported" is a state this repository really produces, and reading it as green would release whatever the last skipped commit left behind.

## Step 2: settle the version and confirm it

This is the step a task can't do, and the reason this is a skill.

Where the operator named a version, that number wins. Pass it through. If readiness derived a different one, say so in a line before dispatching, because the difference is worth seeing even when the operator has already decided the answer.

With nothing named, the automatic path derives the version from the Conventional Commit types since the last tag. A run of fixes and chores yields a patch bump where the operator wanted a minor, and #25 exists because that went unnoticed until after the tag. Don't dispatch the automatic path on an assumption. Show the derived number with the commits behind it and confirm.

Run `mise run preview-changelog` for the entries cog writes, and print this first so the operator reads it in your message text rather than in a widget that truncates:

```text
Latest tag:      <the current tag>
Derived version: <what cog bump --auto would produce>
Commits since:   <count>, types: <the Conventional Commit types present>

<the preview-changelog output>
```

Now call `AskUserQuestion` with `question` set to `Release which version?`, `header` set to `Version`, `multiSelect` set to `false`, and these options in order:

| Label | Description |
| --- | --- |
| `Release <derived>` | `The version the commit types since <tag> derive.` |
| `Release <next minor>` | `A minor bump instead, dispatched with an explicit version.` |
| `Stop here` | `Nothing is dispatched. The tag and the branch stay as they are.` |

Offer the minor only where the derived number is a patch, which is the shape the mistake takes. Where the operator picks something else entirely, take it and re-check the `X.Y.Z` shape.

## Step 3: dispatch

Record which run is newest before dispatching. The watcher needs it to tell the run it just triggered from the previous release's, which is still the newest one for the first few seconds after a dispatch:

```text
gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId'
```

An empty answer means the workflow has never run. Carry `none` through to step 4.

Then dispatch:

```text
mise run release-repotools <X.Y.Z>
```

Omit the version only where the operator chose the derived one in step 2 and wants the automatic path. Passing the number explicitly is the safer form, and it records the intended version in the run's own inputs.

That task runs readiness again before it dispatches. The repetition is deliberate: the task is independently useful and gates itself rather than trusting a caller. Expect the `OK` lines a second time.

## Step 4: wait for the run

`gh workflow run` returns the moment GitHub accepts the request. The workflow hasn't tagged anything yet. Arm the watcher through the `Monitor` tool, which turns each line into a notification:

```text
Monitor({
  command: "bash .claude/skills/release/scripts/watch-release.sh <baseline-run-id>",
  description: "the repotools release run",
  timeout_ms: 1800000,
  persistent: false,
})
```

Pass the ID recorded in step 3, or `none`.

The lines to expect:

- `RELEASE RUN <id>  <url>` once, when the dispatched run registers
- `PASS <step>`, `SKIP <step>`, or `FAIL <step> (<conclusion>)`, one per step as it settles
- `RELEASE RUN SUCCEEDED <url>`, `RELEASE RUN <CONCLUSION> <url>`, `TIMEOUT run <id> ...`, or `NO RUN registered ...` to close

Running the same command through `Bash` blocks to the same ending, with the exit code carrying the outcome: `0` the run succeeded, `1` it didn't, `2` the wait ran out or no run appeared. Prefer `Monitor`.

Never dispatch again on an unclear answer. A `TIMEOUT` or a `NO RUN` says the state is unknown, not that nothing happened, and the run may well be mid-tag. Report what the watcher said, give the run list command, and stop. A stalled release costs a look. Dispatching twice costs a retracted tag.

`RELEASE_RUN_TIMEOUT` and `RELEASE_RUN_INTERVAL` override the bounds in seconds. Keep `timeout_ms` past `RELEASE_RUN_TIMEOUT` so the script reports its own timeout rather than dying at the tool's.

## Step 5: verify

The tag and the release commit are on the remote and this checkout has neither. Fetch first, or verification fails on a tag it has never seen:

```text
git fetch origin --tags
mise run verify-repotools-release v<X.Y.Z>
```

That task checks that:

- the tag is an annotated one rather than a lightweight one
- it carries an SSH signature
- it names the release tagger
- it matches the object origin holds
- it verifies at GitHub
- it's reachable from `main`
- every published version literal names it

Annotation is the sharp check. Cog drives libgit2 and can only make a lightweight tag, which `push --follow-tags` silently leaves behind. To work around exactly that, the workflow deletes and re-creates the tag signed. A `FAIL` on that line means the workaround didn't take and the tag on the remote isn't the one consumers should pin.

The bump runs under `--skip-ci`. CI skips the release commit entirely, which leaves this task as the only thing standing between a bad release commit and every consumer.

## Step 6: report

Say the tag, the run it came from, and what verification concluded, line by line. Where anything failed, say what and stop there rather than proposing a repair: a released tag becomes public the moment it reaches the remote, and undoing one is the operator's call.

The tag is the whole release. Consumers resolve the ref directly through apm, the Go module proxy, a `.pre-commit-config.yaml` rev, or a workflow pin, so this repository publishes no GitHub Release object, assets, or built artifacts. Finding no release object is correct rather than a gap, so don't go looking for one.

## Never

- Tag or bump locally, under any circumstance, including a workflow that failed partway. Nothing here can reproduce the signature, and an unsigned tag looks right until somebody reads the object. The guard hook refuses those forms because of that.
- Dispatch a second time on an ambiguous state. Read the run first.
- Edit `CHANGELOG.md`, `apm.yml`'s version, or any published version literal. `cog.toml`'s pre-bump hooks own them all, and a hand edit puts the tree and the hooks in a disagreement `mise run check-versions` then reports.

## Preconditions

- a clean checkout whose `HEAD` stands at the commit `origin/main` points at, under any branch name
- `gh` installed and authenticated, and `cog` on `PATH`
- `jq` for the watcher

Readiness checks the first, and the watcher checks the rest. Where one is missing, say so rather than improvising a substitute.
