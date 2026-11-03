#!/usr/bin/env python3
"""Check that the keyboard extension target does not link PrivateKeyboardUpdater."""
from __future__ import annotations

import re
import sys
from pathlib import Path

project = Path("PrivateKeyboard.xcodeproj/project.pbxproj").read_text()
target = re.search(
    r"([A-F0-9]{24}) /\* PrivateKeyboardKeyboard \*/ = \{\s*isa = PBXNativeTarget;(.*?)\n\t\t\};",
    project,
    re.S,
)
if not target:
    print("could not locate keyboard target in project.pbxproj", file=sys.stderr)
    raise SystemExit(1)
block = target.group(2)
phases = re.search(r"buildPhases = \((.*?)\);", block, re.S)
if not phases:
    print("could not locate build phases", file=sys.stderr)
    raise SystemExit(1)
framework_ids = re.findall(r"([A-F0-9]{24}) /\* Frameworks \*/", phases.group(1))
if not framework_ids:
    print("could not locate framework phase", file=sys.stderr)
    raise SystemExit(1)
for phase_id in framework_ids:
    phase = re.search(
        re.escape(phase_id) + r" /\* Frameworks \*/ = \{.*?files = \((.*?)\);",
        project,
        re.S,
    )
    if phase and "PrivateKeyboardUpdater" in phase.group(1):
        print("keyboard extension links PrivateKeyboardUpdater", file=sys.stderr)
        raise SystemExit(1)
print("project structural privacy check: keyboard target does not link PrivateKeyboardUpdater")
