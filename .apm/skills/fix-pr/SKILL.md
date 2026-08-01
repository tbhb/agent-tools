---
name: fix-pr
license: Apache-2.0
description: >-
  Diagnose the failing checks on a pull request and fix them. One call reads the failing logs and names the local recipe that reproduces each failure. The correction itself goes through the commit skill and out with a push. Use this whenever a pull request is red, whenever the user asks to fix CI, and whenever watch-pr comes back with failures.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "${CLAUDE_PROJECT_DIR}/.claude/skills/fix-pr/scripts/guard-fix.sh"
---

# Fix a failing pull request

Take a red pull request and make the checks pass. This skill ends when the branch carries a fix and the push has gone out. Confirming the result belongs to `watch-pr`, and merging belongs to `merge-pr`.

A guard hook runs alongside. It refuses a log sweep that goes around the diagnosis below, while leaving one job's full log open to read, because that's the real next step once the printed tail runs short.

## Which pull request

`$ARGUMENTS` names the pull request number when the caller knows it. An empty value means whatever is open for the current branch.

## Step 0: open the task list

Create these with `TaskCreate`, then move each through `in_progress` and `completed`.

1. Diagnose the failures
2. Reproduce each one locally
3. Fix the cause
4. Commit through the commit skill
5. Push and hand back

## Step 1: diagnose

```text
bash .claude/skills/fix-pr/scripts/diagnose.sh <number>
```

One call gets the failing jobs, the tail of each failing step's log, and the local recipe covering the same ground. Read that output before running anything else. Going straight to `gh run view` repeats work the script already did.

The script also compares the local checkout against the commit CI tested. Stop when it reports a mismatch. The logs then describe code this worktree no longer carries, so a fix aimed at them reaches the wrong revision. Check out the branch the pull request names, or pull it forward, and diagnose again.

## Step 2: reproduce

Run the recipe the script named for each failure. Reproducing first is what separates a fix from a guess.

The mapping from job name to recipe is a guess, so treat a recipe that passes locally as a signal rather than a contradiction. Look for the explanation among these:

- The job runs something the recipe doesn't. Read the workflow.
- The failure depends on the environment, such as a pinned tool version or a container image the worktree isn't running.
- The failure is a flake, which makes the run worth repeating before anything changes.

Say which one applies rather than editing until the symptom moves.

## Step 3: fix the cause

Change what made the check fail, and nothing else. A red pull request is a poor moment for adjacent cleanup: it widens the diff a reviewer already has questions about, and it hides the fix inside unrelated edits.

Where a lint gate failed, the finding names the file and the line, and often the replacement too. Apply it exactly. Where a test failed, read the assertion before changing either side, because a test that caught a real defect deserves the fix on the other side.

Never silence a gate to make it pass. Excluding a path changes the project's standards, and so does a new rule exception or a lowered threshold. Any of those goes to the operator as a proposal rather than into the commit.

Re-run the reproducer until it passes.

## Step 4: commit

Run the `commit` skill. It owns the message, the review, and the gates, and this workflow adds nothing to that.

Where the fix splits into unrelated groups, the commit skill says so and takes them one at a time.

## Step 5: push and hand back

```text
git push origin HEAD
```

Report what failed, what caused it, and what the fix changed. Then say the checks are running again.

Where the caller asked for a fix and nothing more, stop here. Where the caller asked to see it through, invoke `watch-pr` with the same number and repeat from step 1 on a fresh failure.

Bound the loop. After three rounds on the same check, stop, then report what each attempt changed and why the check still fails. A fourth attempt at the same shape of fix is rarely the one that works.

## Preconditions

- `gh` installed and authenticated
- the pull request's branch checked out, so a fix reaches the code CI tested
- the `commit` skill deployed alongside this one
