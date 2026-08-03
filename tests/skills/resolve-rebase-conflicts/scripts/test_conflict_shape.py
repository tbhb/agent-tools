"""Tests for conflict_shape.py.

The script is driven as a subprocess rather than imported, because its
contract is the command line: argv in, stdout out, and an exit status that
distinguishes a refusal from a crash. Importing it would test the functions
while leaving that contract, where the defect this suite was written for
lived, uncovered.
"""

import subprocess
import sys
import tomllib
from pathlib import Path

import pytest

# tests/ mirrors the source tree one level down: this file sits at
# tests/skills/<skill>/scripts/ and its subject at
# .apm/skills/<skill>/scripts/. The tests live outside .apm/ because APM
# deploys every file under a skill directory, and a consumer repo has no
# pytest to run them with.
REPO_ROOT = Path(__file__).resolve().parents[4]
SCRIPT = REPO_ROOT / ".apm/skills/resolve-rebase-conflicts/scripts/conflict_shape.py"
assert SCRIPT.is_file(), f"subject not found: {SCRIPT}"

OK = 0
MISUSE = 2
REFUSED = 3


def run(
    mode: str,
    stages: tuple[str | None, ...],
    tmp_path: Path,
    declared: str = "",
) -> subprocess.CompletedProcess[str]:
    """Invoke the script over three stage files and return the completed process."""
    paths = []
    for name, content in zip(("1", "2", "3"), stages, strict=True):
        p = tmp_path / name
        if content is None:
            p.touch()
        else:
            p.write_text(content, encoding="utf-8")
        paths.append(str(p))
    return subprocess.run(
        [sys.executable, str(SCRIPT), mode, "some/path", *paths],
        capture_output=True,
        text=True,
        check=False,
        env={"DECLARED": declared, "PATH": "/usr/bin:/bin"},
    )


SORTED_UNION = ("alpha\nbravo\n", "alpha\nbravo\ndelta\n", "alpha\nbravo\nzulu\n")
DELETION = ("alpha\nbravo\ncharlie\n", "alpha\ncharlie\n", "alpha\nbravo\nzulu\n")
UNSORTED = ("charlie\nalpha\n", "charlie\nalpha\nzulu\n", "charlie\nalpha\ndelta\n")


class TestUnionMode:
    def test_provable_union_prints_the_union_and_exits_zero(
        self, tmp_path: Path
    ) -> None:
        proc = run("union", SORTED_UNION, tmp_path)
        assert proc.returncode == OK
        assert proc.stdout == "alpha\nbravo\ndelta\nzulu\n"

    def test_a_deleted_line_refuses_with_three(self, tmp_path: Path) -> None:
        proc = run("union", DELETION, tmp_path)
        assert proc.returncode == REFUSED
        assert proc.stdout == ""
        assert "removed a line the ancestor had" in proc.stderr

    def test_unsorted_input_refuses_with_three(self, tmp_path: Path) -> None:
        proc = run("union", UNSORTED, tmp_path)
        assert proc.returncode == REFUSED
        assert "not sorted and unique" in proc.stderr

    def test_declared_manual_refuses_even_when_provable(self, tmp_path: Path) -> None:
        proc = run("union", SORTED_UNION, tmp_path, declared="manual")
        assert proc.returncode == REFUSED
        assert "rebase-resolve=manual" in proc.stderr

    def test_an_empty_stage_refuses_rather_than_crashing(self, tmp_path: Path) -> None:
        proc = run("union", ("alpha\n", None, "alpha\nzulu\n"), tmp_path)
        assert proc.returncode == REFUSED
        assert "is absent" in proc.stderr

    def test_a_binary_stage_refuses_rather_than_crashing(self, tmp_path: Path) -> None:
        (tmp_path / "bin").write_bytes(b"alpha\n\x00\n")
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "union",
                "some/path",
                str(tmp_path / "bin"),
                str(tmp_path / "bin"),
                str(tmp_path / "bin"),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode == REFUSED
        assert "is binary" in proc.stderr


class TestExitContract:
    """Refusal is exit 3 alone. Every other nonzero must stay distinguishable.

    resolve-union.sh branches on these exact values. When it could not tell 3
    from 1 it reported a crash mid-rebase as a routine "read this one
    yourself", which is the wrong instruction to give an agent holding a
    half-applied rebase.
    """

    @pytest.mark.parametrize(
        "argv",
        [
            [],
            ["union"],
            ["union", "p", "a", "b"],
            ["union", "p", "a", "b", "c", "d"],
            ["sideways", "p", "a", "b", "c"],
        ],
    )
    def test_bad_invocation_exits_two_not_three(self, argv: list[str]) -> None:
        proc = subprocess.run(
            [sys.executable, str(SCRIPT), *argv],
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode == MISUSE
        assert proc.stdout == ""

    def test_a_missing_stage_file_is_a_refusal_not_a_traceback(
        self, tmp_path: Path
    ) -> None:
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "union",
                "some/path",
                str(tmp_path / "nope"),
                str(tmp_path / "nope"),
                str(tmp_path / "nope"),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert proc.returncode == REFUSED
        assert "Traceback" not in proc.stderr


class TestClassifyMode:
    """classify has no refusal path: every input exits 0 with a verdict.

    classify-conflicts.sh calls it without branching on the status, so any
    nonzero would be the tool breaking.
    """

    @pytest.mark.parametrize(
        ("stages", "expected"),
        [
            (SORTED_UNION, "class: sorted-union"),
            (DELETION, "class: content"),
            (UNSORTED, "class: content"),
        ],
    )
    def test_classifies_and_always_exits_zero(
        self, stages: tuple[str, ...], expected: str, tmp_path: Path
    ) -> None:
        proc = run("classify", stages, tmp_path)
        assert proc.returncode == OK
        assert proc.stdout.startswith(expected)

    def test_token_union_is_offered_as_a_proposal(self, tmp_path: Path) -> None:
        stages = (
            "flags: --a --b\nother\n",
            "flags: --a --b --x\nother\n",
            "flags: --a --b --y\nother\n",
        )
        proc = run("classify", stages, tmp_path)
        assert proc.returncode == OK
        assert "class: token-union" in proc.stdout
        assert "proposal:       flags: --a --b --x --y" in proc.stdout

    def test_a_wrong_union_declaration_is_reported_not_forced(
        self, tmp_path: Path
    ) -> None:
        proc = run("classify", DELETION, tmp_path, declared="union")
        assert proc.returncode == OK
        assert "NOTE: declared rebase-resolve=union, but" in proc.stdout
        assert "class: content" in proc.stdout

    def test_a_right_union_declaration_is_confirmed(self, tmp_path: Path) -> None:
        proc = run("classify", SORTED_UNION, tmp_path, declared="union")
        assert "declared: rebase-resolve=union, and the evidence agrees" in proc.stdout


class TestScriptHeader:
    """The PEP 723 header is the dependency contract, so it has to parse."""

    def test_inline_metadata_is_well_formed_and_pins_the_interpreter(self) -> None:
        text = SCRIPT.read_text(encoding="utf-8")
        block = text.split("# /// script\n")[1].split("# ///\n")[0]
        meta = tomllib.loads(
            "\n".join(
                line.removeprefix("# ").removeprefix("#") for line in block.splitlines()
            )
        )
        assert meta["requires-python"] == ">=3.14"
        assert meta["dependencies"] == []

    def test_the_shebang_runs_it_through_uv(self) -> None:
        first = SCRIPT.read_text(encoding="utf-8").splitlines()[0]
        assert first == "#!/usr/bin/env -S uv run --script"
