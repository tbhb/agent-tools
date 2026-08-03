"""Tests for skill_attribution.py.

Driven as a subprocess against a synthetic projects directory, the same way
test_fix_prose_replacements.py drives its subject. The contract worth
asserting is what the command reports, and the reporting is where the claims
live: a fork's transcript bounds one run, a main transcript's attribution
span bounds its own, a relocated session counts once, and a command collapses
to a shape that survives comparison across runs.

A real transcript can't be pinned to a fixture, so the records here are the
minimum an assistant record needs to reach the report.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

# tests/tools/ mirrors tools/. See the note in
# tests/skills/resolve-rebase-conflicts/scripts/test_conflict_shape.py for
# why these sit outside the tree they test.
REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "tools/skill_attribution.py"
assert SCRIPT.is_file(), f"subject not found: {SCRIPT}"

MISSING_PROJECTS = 2


def assistant(uuid: str, skill: str | None, commands: list[str], session: str) -> str:
    """One assistant record carrying a bash call per command."""
    return json.dumps(
        {
            "type": "assistant",
            "uuid": uuid,
            "sessionId": session,
            "timestamp": "2026-08-03T12:00:00.000Z",
            "version": "2.1.220",
            **({"attributionSkill": skill} if skill else {}),
            "message": {
                "content": [
                    {"type": "tool_use", "name": "Bash", "input": {"command": command}}
                    for command in commands
                ]
            },
        }
    )


@pytest.fixture
def projects(tmp_path: Path) -> Path:
    root = tmp_path / "projects"
    (root / "-repo").mkdir(parents=True)
    return root


def write_main(projects: Path, session: str, lines: list[str]) -> None:
    (projects / "-repo" / f"{session}.jsonl").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def write_fork(projects: Path, session: str, agent: str, lines: list[str]) -> None:
    forks = projects / "-repo" / session / "subagents"
    forks.mkdir(parents=True, exist_ok=True)
    (forks / f"{agent}.jsonl").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (forks / f"{agent}.meta.json").write_text(
        json.dumps({"agentType": "Explore"}), encoding="utf-8"
    )


def run(projects: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--projects-dir", str(projects), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def rows(projects: Path, *args: str) -> list[dict[str, str]]:
    result = run(projects, "--json", *args)
    assert result.returncode == 0, result.stderr
    return [json.loads(line) for line in result.stdout.splitlines()]


@pytest.mark.parametrize(
    ("command", "shape"),
    [
        ("gh pr diff 42 --color never", "gh pr diff"),
        ("git log --format=%h main..HEAD", "git log"),
        ("cat SQUASH_AGENTMSG", "cat"),
        ("REPO=/tmp gh pr view 7", "gh pr view"),
        ("/bin/grep -n foo bar.txt", "grep"),
        (
            "bash .claude/skills/merge-pr/scripts/preflight.sh",
            "<merge-pr/preflight.sh>",
        ),
    ],
)
def test_command_collapses_to_a_comparable_shape(
    projects: Path, command: str, shape: str
) -> None:
    write_main(projects, "s0", [assistant("u1", "commit", [command], "s0")])
    assert [row["detail"] for row in rows(projects)] == [shape]


def test_fork_transcript_is_one_run(projects: Path) -> None:
    write_fork(
        projects,
        "s1",
        "agent-a1",
        [
            assistant("u1", "review-squash-message", ["gh pr diff 3"], "s1"),
            assistant("u2", "review-squash-message", ["gh pr view 3", "cat X"], "s1"),
        ],
    )
    collected = rows(projects)
    assert len(collected) == 3
    assert {row["run"] for row in collected} == {"agent-a1"}
    assert {row["skill"] for row in collected} == {"review-squash-message"}
    assert {row["agent_type"] for row in collected} == {"Explore"}


def test_main_transcript_splits_runs_at_each_attribution_change(
    projects: Path,
) -> None:
    write_main(
        projects,
        "s2",
        [
            assistant("u1", None, ["ls"], "s2"),
            assistant("u2", "commit", ["git status"], "s2"),
            assistant("u3", "fix-prose", ["just lint-commit-msg"], "s2"),
            assistant("u4", "commit", ["git add x"], "s2"),
        ],
    )
    runs = {(row["skill"], row["run"]) for row in rows(projects)}
    # commit loaded twice around fix-prose, so it counts as two runs, not one.
    assert sorted(run for skill, run in runs if skill == "commit") == ["s2#2", "s2#4"]


def test_summary_counts_those_runs_separately(projects: Path) -> None:
    write_main(
        projects,
        "s2",
        [
            assistant("u1", "commit", ["git status"], "s2"),
            assistant("u2", "fix-prose", ["just lint-commit-msg"], "s2"),
            assistant("u3", "commit", ["git add x"], "s2"),
        ],
    )
    result = run(projects)
    assert result.returncode == 0, result.stderr
    line = next(x for x in result.stdout.splitlines() if x.startswith("commit "))
    calls, count = line.split()[1:3]
    assert (calls, count) == ("2", "2")


def test_relocated_session_counts_once(projects: Path) -> None:
    (projects / "-old-name").mkdir()
    line = assistant("u1", "commit", ["git status"], "s3")
    write_main(projects, "s3", [line])
    (projects / "-old-name" / "s3.jsonl").write_text(line + "\n", encoding="utf-8")
    assert len(rows(projects)) == 1


def test_since_drops_earlier_records(projects: Path) -> None:
    write_main(projects, "s4", [assistant("u1", "commit", ["git status"], "s4")])
    assert rows(projects, "--since", "2026-08-04") == []
    assert len(rows(projects, "--since", "2026-08-01")) == 1


def test_truncated_final_line_is_skipped(projects: Path) -> None:
    (projects / "-repo" / "s5.jsonl").write_text(
        assistant("u1", "commit", ["git status"], "s5") + '\n{"type": "user"',
        encoding="utf-8",
    )
    assert len(rows(projects)) == 1


def test_detail_names_a_skill_with_no_calls(projects: Path) -> None:
    write_main(projects, "s6", [assistant("u1", "commit", ["git status"], "s6")])
    result = run(projects, "--skill", "merge-pr")
    assert result.returncode == 0
    assert "no calls attributed to merge-pr" in result.stdout


def test_missing_projects_directory_is_an_error(tmp_path: Path) -> None:
    result = run(tmp_path / "absent")
    assert result.returncode == MISSING_PROJECTS
    assert "no projects directory" in result.stderr
