# SPDX-License-Identifier: Apache-2.0
# Copyright Tony Burns

"""Report the running distribution's version.

This mirrors the Go side's internal/buildmeta: anything that grows a
command-line surface eventually has to answer "which version am I", and the
answer has to survive being run from a source checkout where no distribution
metadata exists.
"""

from __future__ import annotations

from importlib import metadata

# What to report when the package is not installed, which is what running
# straight from a source checkout looks like.
DEVELOPMENT: str = "dev"

DISTRIBUTION: str = "repotools"


def resolve_version(distribution: str, fallback: str = DEVELOPMENT) -> str:
    """Look up an installed distribution's version.

    Args:
        distribution: The distribution name to look up.
        fallback: What to return when no metadata is installed.

    Returns:
        The installed version, or ``fallback`` when the distribution is
        absent.
    """
    try:
        return metadata.version(distribution)
    except metadata.PackageNotFoundError:
        return fallback


def version() -> str:
    """Return this package's own version.

    Returns:
        The installed version, or ``DEVELOPMENT`` from a source checkout.
    """
    return resolve_version(DISTRIBUTION)
