---
name: pr
license: Apache-2.0
description: >-
  Open a pull request for the current branch. The title and the pull request properties and the template's sections draft into PR_AGENTDESC.md. That draft then goes through an independent review plus a mechanical validator, and publishes once the operator confirms. Whatever follows routes to the watch-pr and fix-pr and merge-pr skills. Use this whenever the user asks to open or draft a pull request in a tbhb repo, and whenever a task ends in one.
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "${CLAUDE_PROJECT_DIR}/.claude/skills/pr/scripts/guard-gh.sh"
  PostToolUse:
    - matcher: Skill
      hooks:
        - type: command
          command: "${CLAUDE_PROJECT_DIR}/.claude/skills/pr/scripts/stamp-review.sh"
---

# Open a pull request

Work the steps in order. A pair of hooks runs alongside them and refuses the shortcuts. A direct `gh pr create` is out, so is a `gh pr edit` rewriting the title or body, and so is any publish whose description the reviewer hasn't seen in its current form.

This skill ends when the pull request is open. From there `watch-pr`, `fix-pr`, and `merge-pr` take over, and step 7 routes to whichever the operator asked for.

## Preflight

!`bash ${CLAUDE_SKILL_DIR}/scripts/preflight.sh`

## Step 0: open the task list

Create these with `TaskCreate`, then move each through `in_progress` and `completed`.

1. Confirm the branch is ready
2. Draft the description in PR_AGENTDESC.md
3. Review the draft with review-pr-description
4. Run the validator and the prose gates
5. Ask the operator how far to take it
6. Publish the pull request
7. Route the rest

Stop before any of it where preflight reports a rebase, merge, or cherry-pick in progress, or a missing precondition. Say what's wrong and hand back.

## Step 1: confirm the branch is ready

Preflight answered each of these, so read rather than re-run:

- The branch carries commits the base doesn't. Nothing to open otherwise.
- The branch isn't the default branch.
- Uncommitted changes stay out of the pull request. Where preflight listed some, say so and let the operator decide before going on.
- A pull request may already exist. Where one is open, publishing updates it rather than opening a second.

Preflight also removed a stale `PR_AGENTDESC.md` where no open pull request stood behind it, so an absent draft at this point is the expected state.

## Step 2: draft the description

Write `PR_AGENTDESC.md` at the repository root. A gitignore entry keeps it out of history, and `merge-pr` removes it once the branch merges. Preflight printed the exact skeleton, the repository's label set, and the template's sections.

### Frontmatter

```text
---
base: <branch this merges into>
draft: <true or false>
labels: [<one or more from the set preflight printed>]
reviewers: []
assignees: []
milestone:
---
```

Those keys and no others. Labels take a flow sequence, and an empty one fails the validator, because nobody's filter finds an unlabelled pull request.

### Title

A level 1 heading, immediately after the frontmatter, in the Conventional Commits shape `<type>(<scope>)?(!)?: <description>`. A squash merge turns this into the commit subject on the default branch, so the type has to be one the landing commits use, and the description names what the whole branch does rather than what the last commit did.

### Sections

Fill every section the template declares, in the template's order, with prose. Replace each instructional comment rather than leaving it in place: a surviving comment reads as an unfilled section, and the validator treats it that way.

The sections answer different questions, so don't let them repeat each other. Summary says what changes. Why says what problem made it necessary. Verification names the commands you actually ran, in backticks. Risk says what breaks if this is wrong and how to back it out. Related points at issues, or says `None`.

Avoid:

- Restating the diff. A reviewer reads the diff already.
- Counting. No file, line, test, or commit counts.
- Provenance filler. Nothing about requests, sessions, prompts, models, or tools.
- Claims you haven't checked, including verification you didn't run.
- Selling it. Drop `robust`, `comprehensive`, `significantly`, and their neighbors.
- Paths that don't exist. The validator resolves every backticked path against the tree and the diff.

## Step 3: review the draft

Invoke the `review-pr-description` skill, passing the repository root from preflight as its argument. It runs as an independent agent that hasn't watched you work, so it reads the description against the branch with no memory of what you meant to write.

This step is mandatory, and `create-pr.sh` enforces it. A clean verdict signs the exact bytes of the draft, a finding erases any earlier signature, and editing the draft afterward voids it the same way.

Fix everything it returns. Push back only where it's demonstrably wrong about the diff, and say why.

## Step 4: run the validator and the prose gates

```text
just lint-pr-description
```

That recipe runs the mechanical checks, then vale and cspell over the draft. The validator settles the frontmatter shape, the title's form and bounds, section presence and order, empty sections, surviving comments, unclosed fences, dead links, and whether every backticked path exists. Each finding names a line and the fix.

Resolve every one. Edited the draft to clear them? Then step 3 runs again, because the gate compares bytes rather than intentions.

## Step 5: ask the operator how far to take it

Print the draft first so the operator reads it in your message text rather than in the truncated widget:

```text
Branch:  <branch> into <base>
Commits: <count>

<the entire PR_AGENTDESC.md contents, verbatim>
```

Now call `AskUserQuestion` with `question` set to `How far should I take this?`, `header` set to `Pull request`, `multiSelect` set to `false`, and these four options in order, from the most automated to the least:

| Label | Description |
| --- | --- |
| `Open, fix, and merge` | `Open it, watch the checks, fix what fails, and squash merge once it is green.` |
| `Open, watch, and fix` | `Open it, watch the checks, and fix what fails. Stop before merging.` |
| `Open and watch` | `Open it, watch the checks, and report the result without changing anything.` |
| `Open only` | `Open it and hand back.` |

Record the answer. Step 7 routes on it without asking again.

A fifth path stays available without an option of its own. Where the operator wants the description changed, redraft it, put it back through the review, and return here.

## Step 6: publish the pull request

```text
bash .claude/skills/pr/scripts/create-pr.sh
```

That script is the only thing here that publishes, and it gates itself first:

- runs the validator over the draft again
- compares the review signature against the bytes on disk
- resolves labels, the milestone, and every issue reference against the API, so an unknown one refuses cleanly rather than leaving a published pull request missing what it should carry

Only then does the branch go up and the pull request open. A second run updates the open pull request rather than opening another.

Never call `gh pr create` yourself. A guard hook refuses it, because every gate named here lives in that script.

Report the URL.

## Step 7: route the rest

Follow the answer from step 5.

`Open only` ends here. Say the pull request is open and hand back.

`Open and watch` invokes `watch-pr` with the number, then reports what it found. Stop there even when something failed.

`Open, watch, and fix` invokes `watch-pr`, then `fix-pr` on failure, then `watch-pr` again to confirm. Repeat until the checks pass, then stop before merging. Bound the loop. After three rounds on the same check, stop, then report what each attempt changed.

`Open, fix, and merge` does the same, then invokes `merge-pr` with the number once the checks are green. That skill drafts the squash message and puts it through its own review. It also asks the operator to confirm before merging, so the merge earns a confirmation of its own.

Where the description drifts as remediation commits arrive, redraft it, review it again, and re-run `create-pr.sh` to update the published copy.

## Preconditions

This skill assumes the shared tbhb toolchain:

- `gh` installed and authenticated
- a `just lint-pr-description` recipe
- a gitignore entry for `PR_AGENTDESC.md`
- a pull request template at `.github/pull_request_template.md`
- the `review-pr-description` skill deployed alongside this one
- the `watch-pr`, `fix-pr`, and `merge-pr` skills deployed for step 7

Preflight checks each. Where one is missing, tell the operator rather than improvising a substitute.
