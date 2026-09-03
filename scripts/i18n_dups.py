#!/usr/bin/env python3
"""List duplicate exact-dictionary keys per localization file."""
import re
import os

LOC = os.path.join(os.path.dirname(__file__), "..", "app", "src", "main", "java", "com", "haoze", "dnssr", "ui", "localization")
KEY_LINE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*->\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$')

for fn in sorted(os.listdir(LOC)):
    if not fn.endswith(".kt"):
        continue
    lines = open(os.path.join(LOC, fn), encoding="utf-8").read().split("\n")
    seen = {}
    dups = []
    for i, ln in enumerate(lines):
        m = KEY_LINE.match(ln)
        if m:
            k = m.group(1)
            if k in seen:
                dups.append((k, seen[k] + 1, i + 1))
            else:
                seen[k] = i
    for k, first, second in dups:
        print(f"{fn}: {k!r} keep@{first} drop@{second}")
