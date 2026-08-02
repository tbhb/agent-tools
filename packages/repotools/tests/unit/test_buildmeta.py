# SPDX-License-Identifier: Apache-2.0
# Copyright Tony Burns

"""Unit tests for the buildmeta module."""

from __future__ import annotations

from repotools import buildmeta


def test_installed_distribution_reports_its_version() -> None:
    # The suite runs against an editable install of this package, so its
    # own metadata is the one lookup guaranteed to resolve.
    assert buildmeta.resolve_version(buildmeta.DISTRIBUTION) != buildmeta.DEVELOPMENT


def test_absent_distribution_falls_back() -> None:
    assert buildmeta.resolve_version("no-such-distribution-anywhere") == (
        buildmeta.DEVELOPMENT
    )


def test_custom_fallback_is_honored() -> None:
    assert buildmeta.resolve_version("no-such-distribution-anywhere", "custom") == (
        "custom"
    )


def test_version_reads_this_package() -> None:
    assert buildmeta.version() == buildmeta.resolve_version(buildmeta.DISTRIBUTION)
