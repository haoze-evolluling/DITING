#!/usr/bin/env python3
"""Remove duplicate (later-occurrence) dictionary lines found by i18n_dups.py."""
import re
import os

LOC = os.path.join(os.path.dirname(__file__), "..", "app", "src", "main", "java", "com", "haoze", "dnssr", "ui", "localization")
KEY_LINE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*->\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$')

for fn in ("CommonLocalization.kt", "RulesAndSubscriptionLocalization.kt"):
    p = os.path.join(LOC, fn)
    lines = open(p, encoding="utf-8").read().split("\n")
    seen = {}
    drop = set()
    for i, ln in enumerate(lines):
        m = KEY_LINE.match(ln)
        if m:
            k = m.group(1)
            if k in seen:
                drop.add(i)
            else:
                seen[k] = i
    if not drop:
        continue
    out = [ln for i, ln in enumerate(lines) if i not in drop]
    open(p, "w", encoding="utf-8", newline="\n").write("\n".join(out))
    print(f"{fn}: removed {len(drop)} duplicate lines")
