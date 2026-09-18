# SPDX-License-Identifier: AGPL-3.0-or-later
"""Root entry point of the eva-image zipapp; see ../Makefile."""

from __future__ import annotations

import sys

from eva_kernel_image.cli import main

raise SystemExit(main(sys.argv[1:]))
