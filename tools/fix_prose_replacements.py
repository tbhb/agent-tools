#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///
"""Apply every vale finding that already carries its own correction.

Leave the rest alone.

Roughly a third of a typical run needs no judgment at all. Contractions
wants "don't" for "do not", WordList wants "turn off" for "disable",
OxfordComma wants a comma. The repo-local output template already prints the
replacement as replace_with= on the finding line, because the rule's own
action carries it. Reading those lines into a model and having it retype the
answer costs tokens to reproduce a lookup.

In the measured session behind this script, findings of this shape ran to
about 40 of 111. Applying them here leaves the model the findings that need
a decision.

Safety comes from refusing to guess. Vale gives a line and a column span,
and this checks that the span holds the exact text the finding quoted before
touching it. A span that holds anything else means the file moved under the
report, so that finding is skipped and named rather than applied. Findings
on one line apply right to left, so an earlier replacement never shifts a
later span.

Rules that rewrite meaning stay out by construction: a finding with no
replace_with is never touched, and that covers every distributional rule and
every judgment call.

Prints one line per applied change and one per skip. Silence means nothing
carried a replacement.

Usage:
    fix_prose_replacements.py <file>

Exit:
    0  every replacement that carried one was applied, and nothing was skipped
    1  at least one finding was skipped, or the file does not exist
    2  the invocation was wrong

A nonzero exit is the normal end of a run with skips, not a failure of this
script. The shell version this replaced ran under `set -uo pipefail` with no
`-e` for exactly that reason: vale exits nonzero whenever it has findings,
and `-e` would have aborted the run before anything was applied. That hazard
does not survive the port, since nothing here treats a subprocess status as
fatal on its own, but the exit contract above is unchanged.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

# The template prints match and replace_with as Go %q strings. Those overlap
# JSON string syntax for the escapes prose actually produces, so json.loads
# decodes them without running anything. A form it cannot read gets reported
# and skipped rather than guessed at.
LINE = re.compile(
    r"^(?P<line>\d+):(?P<start>\d+)-(?P<end>\d+) \[\w+\] (?P<rule>\S+) "
    r'match=(?P<match>"(?:[^"\\]|\\.)*")'
    r'(?: replace_with=(?P<repl>"(?:[^"\\]|\\.)*"))?'
)

# Google.Contractions pairs a pronoun with a form of "be" wherever the two
# sit next to each other, including across a clause boundary where the
# pronoun is really the object of the preceding preposition. Vale offers the
# contraction anyway, and taking it breaks the sentence: "a verdict from that
# is narrower" becomes "from that's narrower", and "the cost of a fix for it
# is another round" becomes "for it's another round". Both were live findings
# on this repository.
#
# So a pronoun contraction whose preceding word is a preposition gets
# reported rather than applied. A model reading the sentence settles it in
# one look, which is the whole division of labor here.
OBJECT_PRONOUN = re.compile(
    r"^(it|that|there|this|these|those)\s+(is|are|was|were)$", re.IGNORECASE
)
PREPOSITION = frozenset(
    {
        "about",
        "after",
        "against",
        "at",
        "before",
        "by",
        "for",
        "from",
        "in",
        "into",
        "of",
        "on",
        "over",
        "than",
        "through",
        "to",
        "under",
        "upon",
        "with",
        "without",
    }
)

TEMPLATE = "project-agent.tmpl"

# The script takes exactly one argument: the file to fix.
ARGC = 1

# line, start column, end column, rule, matched text, replacement.
type Edit = tuple[int, int, int, str, str, str]


def repo_root() -> Path:
    proc = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(proc.stdout.strip())


def findings(path: Path, cwd: Path) -> list[str]:
    """Run vale over the file and return its report lines.

    Runs from the repository root, because vale resolves .vale.ini and the
    template named below relative to the working directory.

    The environment is pinned for the same reason the shell version pinned
    it: the agent reads this output, so an operator's locale or grep
    preferences must not reshape it. Vale exits nonzero whenever it has
    findings, which is the ordinary case here, so the status is deliberately
    not consulted.
    """
    env = {**os.environ, "LC_ALL": "C"}
    env.pop("GREP_OPTIONS", None)
    proc = subprocess.run(
        ["vale", f"--output={TEMPLATE}", str(path)],
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd,
        env=env,
    )
    return proc.stdout.splitlines()


def parse(lines: list[str], path: Path) -> list[Edit]:
    """Return the edits carrying a replacement, reporting forms that will not parse."""
    edits = []
    for raw in lines:
        m = LINE.match(raw)
        if not m or not m.group("repl"):
            continue
        try:
            match = json.loads(m.group("match"))
            repl = json.loads(m.group("repl"))
        except ValueError:
            print(f"{path}:{m.group('line')} [error] unparsable-quoting  {raw.strip()}")
            continue
        edits.append(
            (
                int(m.group("line")),
                int(m.group("start")),
                int(m.group("end")),
                m.group("rule"),
                match,
                repl,
            )
        )
    return edits


def breaks_clause(text: str, start: int, match: str) -> bool:
    """True when this contraction would attach to the object of a preposition."""
    if not OBJECT_PRONOUN.match(match):
        return False
    prior = text[: start - 1].rstrip().split()
    return bool(prior) and prior[-1].strip("(,;:").lower() in PREPOSITION


def right_to_left(edit: Edit) -> tuple[int, int]:
    """Order edits by line, then by descending start column."""
    return edit[0], -edit[1]


def apply(path: Path, edits: list[Edit]) -> tuple[int, int]:
    lines = path.read_text(encoding="utf-8").split("\n")
    applied = skipped = 0

    # Right to left within a line, so an applied edit never moves a span that
    # has not been applied yet.
    for ln, start, end, rule, match, repl in sorted(edits, key=right_to_left):
        if ln > len(lines):
            continue
        text = lines[ln - 1]
        if breaks_clause(text, start, match):
            prior = text[: start - 1].rstrip().split()[-1]
            print(
                f"{path}:{ln} [error] context-sensitive  {rule} would write "
                f"{repl!r} after {prior!r}, which breaks the clause; reword it by hand"
            )
            skipped += 1
            continue
        found = text[start - 1 : end]
        if found != match:
            print(
                f"{path}:{ln} [error] span-mismatch  {rule} quoted {match!r} "
                f"but the span holds {found!r}; skipped"
            )
            skipped += 1
            continue
        lines[ln - 1] = text[: start - 1] + repl + text[end:]
        print(f"{path}:{ln} [fixed] {rule}  {match!r} -> {repl!r}")
        applied += 1

    if applied:
        path.write_text("\n".join(lines), encoding="utf-8")
    return applied, skipped


def main(argv: list[str]) -> int:
    if len(argv) != ARGC:
        sys.stderr.write("usage: fix_prose_replacements.py <file>\n")
        return 2
    path = Path(argv[0])
    if not path.is_file():
        print(f"{path}:1 [error] missing-file  no such file")
        return 1

    report = findings(path, repo_root())
    if not report:
        return 0
    edits = parse(report, path)
    if not edits:
        return 0

    applied, skipped = apply(path, edits)
    print(f"TOTAL: {applied} applied, {skipped} skipped")
    return 1 if skipped else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
