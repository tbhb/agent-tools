---
name: release
description: >-
  Release this repository end to end. Prepare an isolated clone of the release branch, run the readiness preflight against it, settle the version number and confirm it, dispatch the release workflow, wait for the run to land, and verify the tag it produced. Use this whenever the operator asks to release, cut, publish, or tag a version of repotools, with or without naming a number, as in "release 0.5.1," "go cut a release," "publish v0.6.0," or "is this ready to release." It runs from any worktree and never touches the checkout you invoked it from. CI makes and SSH-signs the tag, and nothing local reproduces that, so this dispatches and waits rather than tagging. Called without a version it reports the number the automatic path would derive and confirms it before dispatching anything, because that number comes from the commit types since the last tag and has differed from the version the operator intended.
argument-hint: "[X.Y.Z]"
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "${CLAUDE_PROJECT_DIR}/.claude/skills/release/scripts/guard-release.sh"
---

# Release repotools

Drive a release of this repository from readiness to a verified tag, from whatever checkout you happen to be in.

This skill orchestrates three tasks that already exist rather than writing them again. `check-repotools-release-readiness` reports, `release-repotools` dispatches, `verify-repotools-release` checks the result. Finding yourself writing what one of those does is the signal to stop and call it instead.

## The work happens in a clone

Every step below runs against a throwaway clone of the release branch, never against the checkout you invoked from. `release-clone.sh` makes it, and a guard hook refuses a release task run any other way.

That's not a workaround. The release is a statement about `origin/main` and nothing else, because the workflow checks that branch out fresh on the runner, so the tree a local checkout happens to hold has never been the thing released. Reading the version literals, the changelog preview, and the derived version out of a clone of `origin/main` answers the question rather than answering a nearby one. It also frees the release from where it runs, which matters here: a dozen agent worktrees can be in flight at once and the local main checkout stays pristine.

The clone borrows objects from the local repository through `--reference`, so it costs well under a second and fetches only what the remote has and the local repository lacks. It writes nothing back.

A fresh clone has a clean working tree, and its `HEAD` is the release commit by construction. The clone makes both trivially true, so readiness reports them as `OK` without having checked anything. Those checks existed to catch an operator releasing while believing uncommitted or unmerged work was in it. `prepare` prints that as a `NOTE` read from the invoking checkout instead, naming the commits the release leaves behind. It's an advisory rather than a gate, because a branch in flight is the normal state here and never a reason a release of main can't proceed.

## What the release does, so a `FAIL` line means something

The release happens inside `.github/workflows/release.yml` and nowhere else. Cocogitto derives the version. It writes the changelog and rewrites the published version literals, and the commit it makes never leaves the runner. The workflow replays that commit through `createCommitOnBranch`, so GitHub creates it and signs it with its own key. Then the workflow replaces cog's lightweight tag with an SSH-signed annotated one and pushes the tag.

Two signatures, from two signers, and neither one can stand in for the other. A GitHub App holds no key, so only GitHub can sign a commit under the release App. No API creates a signed tag, so a key on the runner has to sign that one, under the tagger identity GitHub verifies it against. Nothing local reproduces either. The guard hook refuses local tagging, local bumping, and a dispatch that goes around the task.

Nothing here edits a changelog or moves a version pin by hand. Cog owns both. Where a commit does turn out to be necessary, it goes through the `commit` skill, which owns the draft file, the trailers, and the gates.

## Which version

`$ARGUMENTS` carries the version when the operator named one. Strip a leading `v` before passing it on, since `release.yml` hands the value to `cog bump --version`, which takes a bare `X.Y.Z` and would otherwise put the letter into the tag twice.

Anything that's not three dot-separated numbers after that stops the run. Say what the operator gave and ask for the version rather than guessing at it. The dispatch task validates the same shape and is the backstop, not the first line.

An empty `$ARGUMENTS` means the version is still open. Step 2 determines it.

## Step 1: prepare the clone

```text
bash .claude/skills/release/scripts/release-clone.sh prepare
```

It prints where the clone is, which commit of the release branch it holds, and a `NOTE` naming any local work the release doesn't carry.

Read that `NOTE` out to the operator whenever it appears, before going further. It's the one thing this skill knows that nobody else does, and the case it exists for is the obvious one: work sitting on the branch in front of you that you assumed was going out. Say what the release would leave behind and let the operator decide. Landing it first and preparing again is the fix where they want it in. Going on is fine where they don't.

## Step 2: readiness

```text
bash .claude/skills/release/scripts/release-clone.sh run check-repotools-release-readiness
```

It prints one `OK` or `FAIL` line per check and an `INFO` line carrying the version `cog bump --auto` would derive. Read both.

On a failure, name the checks that failed and what each one said, then stop, because "Not ready" on its own sends the operator looking for the reason this task already printed. Fix nothing. Readiness reports and never writes. A session that cleans the tree on the way to answering a question has answered a different question.

The failures that can happen against a clone, and what they mean:

- `version literals name the latest tag`. A published literal has drifted from the last tag. `cog.toml`'s pre-bump hooks rewrite those during a bump, so a failure here means a site nothing rewrites.
- `checks green on HEAD`. Something on the release branch is red or reported nothing at all. A commit with no checks fails this deliberately, because the bump commit goes out under `--skip-ci` and reading "nothing reported" as green would release whatever the last skipped commit left behind.
- `the changelog previews`. Cog couldn't render the entries since the last tag, so a release now would write a changelog nobody has seen.

The other two lines come back `OK` for that reason rather than because anything tested them, so never quote them to the operator as evidence the release is safe.

## Step 3: settle the version and confirm it

This is the step a task can't do, and the reason this is a skill.

Where the operator named a version, that number wins. Pass it through. If readiness derived a different one, say so in a line before dispatching, because the difference is worth seeing even when the operator has already decided the answer.

With nothing named, the automatic path derives the version from the Conventional Commit types since the last tag. A run of fixes and chores yields a patch bump where the operator wanted a minor, and #25 exists because that went unnoticed until after the tag. Don't dispatch the automatic path on an assumption. Show the derived number with the commits behind it and confirm.

```text
bash .claude/skills/release/scripts/release-clone.sh run preview-changelog
```

Then get a second opinion on the number, from an agent that reads the commits rather than their types:

```text
Skill(review-release-version, args: "<the clone path from step 1>")
```

It returns a version, cog's number, and `AGREE` or `DISAGREE`. Cog derives a bump from Conventional Commit types alone, which is right whenever a type describes what a change does to consumers and wrong whenever it describes what its author was doing. A `build:` commit rewriting the vendored payload reaches every consumer on the next sync and derives a patch, and that has already produced a release numbered smaller than the change it carried. The reviewer reads the published surface for that gap. A `DISAGREE` isn't a veto and never stops the release on its own. Show it to the operator with the reasoning intact and let them settle it.

Print this first, so the operator reads it in your message text rather than in a widget that truncates:

```text
Latest tag:      <the current tag>
Derived version: <what cog bump --auto would produce>
Reviewed as:     <the reviewer's version, and AGREE or DISAGREE>
Commits since:   <count>, types: <the Conventional Commit types present>
Leaving behind:  <the NOTE from step 1, or "nothing">

<the reviewer's reasoning, where it disagreed>

<the preview-changelog output>
```

Now call `AskUserQuestion` with `question` set to `Release which version?`, `header` set to `Version`, `multiSelect` set to `false`, and these options in order:

| Label | Description |
| --- | --- |
| `Release <derived>` | `The version the commit types since <tag> derive.` |
| `Release <the reviewer's number>` | `What reading the commits argues for instead.` |
| `Stop here` | `Nothing is dispatched. The tag and the branch stay as they are.` |

Offer the middle row as the reviewer's number where it disagreed. Where it agreed, make that row the next minor instead, and only where the derived number is a patch, which is the shape the mistake takes. Where the operator picks something else entirely, take it and re-check the `X.Y.Z` shape.

## Step 4: dispatch

Record which run is newest before dispatching. The watcher needs it to tell the run it just triggered from the previous release's, which is still the newest one for the first few seconds after a dispatch:

```text
gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId'
```

An empty answer means the workflow has never run. Carry `none` through to step 5.

Then dispatch:

```text
bash .claude/skills/release/scripts/release-clone.sh run release-repotools <X.Y.Z>
```

Omit the version only where the operator chose the derived one in step 3 and wants the automatic path. Passing the number explicitly is the safer form, and it records the intended version in the run's own inputs.

That task runs readiness again before it dispatches. The repetition is deliberate: the task is independently useful and gates itself rather than trusting a caller. Expect the `OK` lines a second time.

## Step 5: wait for the run

`gh workflow run` returns the moment GitHub accepts the request. The workflow hasn't tagged anything yet. Arm the watcher through the `Monitor` tool, which turns each line into a notification:

```text
Monitor({
  command: "bash .claude/skills/release/scripts/watch-release.sh <baseline-run-id>",
  description: "the repotools release run",
  timeout_ms: 1800000,
  persistent: false,
})
```

Pass the ID recorded in step 4, or `none`. This watcher reads GitHub rather than a checkout, so it needs no clone.

The lines to expect:

- `RELEASE RUN <id>  <url>` once, when the dispatched run registers
- `PASS <step>`, `SKIP <step>`, or `FAIL <step> (<conclusion>)`, one per step as it settles
- `RELEASE RUN SUCCEEDED <url>`, `RELEASE RUN <CONCLUSION> <url>`, `TIMEOUT run <id> ...`, or `NO RUN registered ...` to close

Running the same command through `Bash` blocks to the same ending, with the exit code carrying the outcome: `0` the run succeeded, `1` it didn't, `2` the wait ran out or no run appeared. Prefer `Monitor`.

Never dispatch again on an unclear answer. A `TIMEOUT` or a `NO RUN` says the state is unknown, not that nothing happened, and the run may well be mid-tag. Report what the watcher said, give the run list command, and stop. A stalled release costs a look. Dispatching twice costs a retracted tag.

`RELEASE_RUN_TIMEOUT` and `RELEASE_RUN_INTERVAL` override the bounds in seconds. Keep `timeout_ms` past `RELEASE_RUN_TIMEOUT` so the script reports its own timeout rather than dying at the tool's.

## Step 6: verify

The release landed a commit and a tag on the branch, which leaves the clone describing the state before its own release.

Throw it away and take a fresh one, then verify:

```text
bash .claude/skills/release/scripts/release-clone.sh refresh
bash .claude/skills/release/scripts/release-clone.sh run verify-repotools-release v<X.Y.Z>
```

Verifying against the stale clone reads a tag it has never seen and version literals naming the previous release, so it reports failures belonging to the clone rather than to the release.

That task checks that:

- the tag is an annotated one rather than a lightweight one
- it carries an SSH signature
- it names the release tagger
- the commit beneath it carries a signature
- that commit names the release App as its author
- origin carries the same tag object
- GitHub reports the tag verified
- GitHub reports the release commit verified
- the tag is reachable from `main`
- every published version literal names it

Annotation is the sharp check. Cog drives libgit2 and can only make a lightweight tag, which `push --follow-tags` silently leaves behind. To work around exactly that, the workflow deletes and re-creates the tag signed. A `FAIL` on that line means the workaround didn't take and the tag on the remote isn't the one consumers should pin.

Signing splits into two assertions rather than one, because two signers produce them and either can fail alone. Every release from v0.3.0 through v0.5.0 carried a verified tag over an unsigned commit, and a check reading the tag by itself called each of them good. The bump runs under `--skip-ci`, so CI skips the release commit entirely, which leaves this task as the only thing standing between a bad release commit and every consumer.

## Step 7: report and clean up

```text
bash .claude/skills/release/scripts/release-clone.sh done
```

Then say the tag, the run it came from, and what verification concluded, line by line. Repeat the step 1 `NOTE` where there was one, since work left out of a release is worth hearing about twice. Where anything failed, say what and stop there rather than proposing a repair: a released tag becomes public the moment it reaches the remote, and undoing one is the operator's call.

Clean up even where the release failed or the operator stopped early. The clone is a temporary directory and a pointer file inside this repository's git directory, and a leftover one gets reused by the next run, which would then release against a branch state fetched at some earlier time.

The tag is the whole release. Consumers resolve the ref directly through apm, the Go module proxy, a `.pre-commit-config.yaml` rev, or a workflow pin, so this repository publishes the tag alone. A GitHub Release object, release assets, and built artifacts are all absent by design, which is the correct state rather than a gap, so don't go looking for them.

## Never

- Tag or bump locally, under any circumstance, including a workflow that failed partway. Nothing here can reproduce the signature, and an unsigned tag looks right until somebody reads the object. The guard hook refuses those forms for that reason.
- Run a release task outside the clone. It would read the checkout you are sitting in, which isn't what gets released. The verdict it reports would be about the wrong tree, and the guard hook refuses that too.
- Dispatch a second time on an ambiguous state. Read the run first.
- Edit `CHANGELOG.md`, `apm.yml`'s version, or any published version literal. `cog.toml`'s pre-bump hooks own them all, and a hand edit puts the tree and the hooks in a disagreement `mise run check-versions` then reports.

## Preconditions

- `git`, `mise`, `gh` authenticated, and `jq`
- an `origin` remote, which the clone comes from

This skill requires nothing of the checkout you invoke from. It can sit on any branch and trail the remote while carrying uncommitted work, and the release is unaffected either way. The clone script says so where something is missing rather than improvising a substitute.
