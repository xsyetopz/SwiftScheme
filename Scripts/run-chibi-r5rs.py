#!/usr/bin/env python3
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / "Tests/External/Chibi/r5rs-tests.scm"
proc = subprocess.run(
    ["swift", "run", "swiftscheme", str(source)],
    cwd=root,
    text=True,
    capture_output=True,
    check=False,
)
print(proc.stdout, end="")
print(proc.stderr, end="", file=sys.stderr)
match = re.search(r"(\d+) out of (\d+) passed", proc.stdout)
if proc.returncode or not match or match.group(1) != match.group(2):
    sys.exit(1)
