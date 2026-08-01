# SPDX-License-Identifier: Apache-2.0
# Copyright Tony Burns

"""Property tests for the buildmeta module."""

from __future__ import annotations

from agent_tools_py import buildmeta
from hypothesis import given
from hypothesis import strategies as st


@given(fallback=st.text())
def test_absent_distribution_returns_the_fallback_verbatim(fallback: str) -> None:
    # Whatever the caller hands over comes back untouched: the fallback is
    # a value to pass through, not something to normalize.
    got = buildmeta.resolve_version("no-such-distribution-anywhere", fallback)
    assert got == fallback
