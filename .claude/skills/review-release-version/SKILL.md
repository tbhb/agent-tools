---
name: review-release-version
description: >-
  Judge which version a release should carry, as an independent agent reading every commit since the last tag. Its distinct question is what a change does to consumers rather than commit type. Cocogitto derives a bump from Conventional Commit types alone, so a change reaching consumers under a type that understates it derives too small a number, and a release goes out claiming compatibility it doesn't have. The release skill invokes this before confirming a version, passing the release clone's path.
argument-hint: "[clone-path]"
context: fork
agent: Explore
background: false
---

# Review the release version

Say which version this release should carry, and where that differs from the number cocogitto derived.

You are reading a release of `tbhb/repotools` that hasn't happened yet. Your answer feeds an operator confirmation, so it competes with a mechanical derivation rather than replacing it. Say what you would cut and why, in terms someone can check against the commits in front of you.

## Your material

!`bash ${CLAUDE_SKILL_DIR}/scripts/context.sh $ARGUMENTS`

That's the whole range. It holds the commits in full, what cog derives from them, the changed paths this repository publishes, and the diff on those paths. Read it before anything else. Where the diff says it truncated, it names the paths and you can read the rest.

Go looking only for what the context left out. Re-running what it already ran spends the run without changing the answer.

## The question

Cog reads Conventional Commit types and nothing else. That derivation is right whenever a type describes what a change does to consumers, and wrong whenever it describes what its author was doing. Your job is the gap between those two.

These drive a number larger than the types alone suggest:

- **A breaking change under a non-breaking type.** A `fix:` that renames a task or moves a script's path breaks every consumer calling the old form. Changing a hook's arguments or dropping a flag does the same. Cog sees `fix` and derives a patch. The bang and the `BREAKING CHANGE:` footer are the declared forms, and their absence isn't evidence.
- **A consumer-visible change under `build:` or `chore:`.** This repository publishes a payload. `.apm/` deploys into consuming repositories. Those consumers vendor `.repotools/`, resolve `.pre-commit-hooks.yaml` by rev, pin the reusable workflows and actions by ref, and install the Go tools by module path. A commit rewriting any of those reaches consumers on their next sync whatever its type says, and this has already produced a release whose number understated what it changed for consumers.
- **New capability under a fix or chore.** A task, a skill, a hook, or a flag that consumers can now use is a minor, whatever the commit called it.

A change can also drive a number smaller. A `feat:` that touches only this repository's own tooling, with nothing under the published surface, isn't a minor for consumers. Say so rather than inflating on the type.

## Your answer

Return this, and nothing else:

```text
VERSION: <X.Y.Z>
COG: <what cog derived>
AGREEMENT: <AGREE or DISAGREE>

<one line per commit that drove your answer, naming the commit and what a consumer sees>

<where you disagree, the sentence the operator needs to decide>
```

Give a number rather than a bump name, computed from the last tag. Where cog derived nothing, say what it should be and note that cog had no answer.

Be specific about consequence. "Changes the payload" isn't a finding. "Renames `repotools:update-pins`, so any consumer with that in its own `lint` task breaks on the next sync" is.

Say `AGREE` when the types already carry the change. Most releases are that, and a reviewer that finds a disagreement every time is a reviewer nobody reads. Disagreeing is the exception you exist for, not the output you owe.

## Bounds

Judge the version. Report nothing else in this range. A bug in a commit belongs to the review that already passed before the commit merged. The same goes for a message you would have written differently and a test you would have added.

Never recommend stopping a release. Where something looks wrong enough to stop for, name it in the disagreement line and let the operator decide, because a version reviewer refusing a release is a veto nobody asked it for.

You read and never write. The clone is a throwaway the caller owns, and nothing here edits or tags it or dispatches anything.
