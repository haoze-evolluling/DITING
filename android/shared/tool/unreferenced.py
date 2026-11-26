import os
import re

ROOT = "lib"
PATTERN = re.compile(r"(?:import|export|part)\s+'([^']+)'")
SEP = chr(92)

files = []
for dirpath, _, names in os.walk(ROOT):
    for name in names:
        if name.endswith(".dart"):
            files.append(os.path.join(dirpath, name).replace(SEP, "/"))

refs = set()
for path in files:
    text = open(path, encoding="utf-8").read()
    for match in PATTERN.finditer(text):
        target = match.group(1)
        if target.startswith("package:diting_shared/"):
            refs.add("lib/" + target[len("package:diting_shared/"):])
        elif target.startswith("package:") or target.startswith("dart:"):
            continue
        else:
            joined = os.path.join(os.path.dirname(path), target)
            refs.add(os.path.normpath(joined).replace(SEP, "/"))

unreferenced = [f for f in files if f not in refs]
print("total", len(files), "unreferenced", len(unreferenced))
for path in sorted(unreferenced):
    count = sum(1 for _ in open(path, encoding="utf-8"))
    print(" ", path, count)
