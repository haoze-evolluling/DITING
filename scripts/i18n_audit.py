#!/usr/bin/env python3
"""i18n coverage audit for DNSSR.

Extracts every Chinese string literal from Kotlin sources, then checks each
against the three translation layers of LocalizationEngine:
  1. hashed string resources (localized_text_<hash>) in values*/strings.xml
  2. exact-match dictionaries (translate*Exact: "中" -> "En")
  3. dynamic pattern functions are reported separately (manual review)

Outputs:
  - uncovered literals (not in layer 1/2) grouped by file
  - literals in UI code NOT wrapped by localizedText() (never translated)
"""
import hashlib
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.join(os.path.dirname(__file__), "..", "app", "src", "main")
JAVA = os.path.join(ROOT, "java")
RES = os.path.join(ROOT, "res")

CJK = re.compile(r"[\u4e00-\u9fff]")
# string literal content (no escape handling needed for CJK text)
LIT = re.compile(r'"([^"\n]*)"')


def string_hash(text: str) -> str:
    h = 0
    for ch in text:
        h = (31 * h + ord(ch)) & 0xFFFFFFFF
    # Kotlin uses Int; simulate 32-bit signed then mask like engine
    if h >= 0x80000000:
        h -= 0x100000000
    return str(h & 0x7FFFFFFF)


def load_resource_names():
    names = set()
    for sub in ("values", "values-en"):
        p = os.path.join(RES, sub, "strings.xml")
        if os.path.exists(p):
            with open(p, encoding="utf-8") as f:
                for m in re.finditer(r'<string name="([^"]+)"', f.read()):
                    names.add(m.group(1))
    return names


def load_exact_dictionary():
    """Parse translate*Exact when-branches: "zh" -> "en"."""
    pairs = {}
    loc_dir = os.path.join(JAVA, "com", "haoze", "dnssr", "ui", "localization")
    for fn in os.listdir(loc_dir):
        if not fn.endswith(".kt"):
            continue
        with open(os.path.join(loc_dir, fn), encoding="utf-8") as f:
            content = f.read()
        # remove comments (guard URLs like https:// from being cut as line comments)
        content = content.replace("://", "\x00SCHEME\x00")
        content = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
        content = re.sub(r"//[^\n]*", "", content)
        content = content.replace("\x00SCHEME\x00", "://")
        for m in re.finditer(r'"([^"\n]*[\u4e00-\u9fff][^"\n]*)"\s*->\s*"([^"\n]*)"', content):
            pairs[m.group(1)] = m.group(2)
    return pairs


def extract_line_literals(line):
    """Return list of (start, end, text) of string literals containing CJK."""
    # strip line comments but keep string positions
    out = []
    i = 0
    in_str = False
    start = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                out.append((start, i + 1, line[start + 1:i]))
                in_str = False
        else:
            if c == '"':
                in_str = True
                start = i
            elif c == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break
        i += 1
    return [t for t in out if CJK.search(t[2])]


def is_comment_line(stripped):
    return stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*")


def walk_kt():
    for dirpath, _, files in os.walk(JAVA):
        for fn in files:
            if fn.endswith(".kt"):
                yield os.path.join(dirpath, fn)


def main():
    resource_names = load_resource_names()
    dictionary = load_exact_dictionary()

    # matches both localizedText("x") and localizedText(context, "x") openers
    wrapped_re = re.compile(r"localizedText\s*\(\s*(?:[A-Za-z_][A-Za-z0-9_.]*\s*,\s*)?$")

    uncovered = defaultdict(list)      # zh -> [(file, line, context)]
    unwrapped = defaultdict(list)      # zh -> [(file, line, context)]  (not wrapped, not log/comment)
    covered_by_dict = set()
    covered_by_res = set()
    pattern_suspects = set()           # contains ${...} templates

    loc_dir_token = os.path.join("ui", "localization") + os.sep

    for path in walk_kt():
        rel = os.path.relpath(path, JAVA)
        in_loc_pkg = loc_dir_token in path
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
        # track multi-line wrapped call state: if a line has unclosed localizedText( paren
        wrapped_depth = 0
        for idx, raw in enumerate(lines, 1):
            stripped = raw.strip()
            if is_comment_line(stripped):
                continue
            for start, end, text in extract_line_literals(raw):
                pre = raw[:start]
                if in_loc_pkg:
                    # dictionary entries or pattern code; dict entries already harvested
                    continue
                # skip log lines
                if re.search(r"\bLog\.[dewiv]\(", pre):
                    continue
                is_wrapped = bool(wrapped_re.search(pre)) or wrapped_depth > 0
                if "${" in text or "$" in text:
                    pattern_suspects.add((rel, idx, text))
                    continue
                if is_wrapped:
                    h = "localized_text_" + string_hash(text)
                    if h in resource_names:
                        covered_by_res.add(text)
                    elif text in dictionary:
                        covered_by_dict.add(text)
                    else:
                        uncovered[text].append((rel, idx, "wrapped"))
                else:
                    # not wrapped: candidate hardcoded UI text OR internal key/log
                    unwrapped[text].append((rel, idx, ""))
            # update wrapped_depth for multi-line calls (count both forms)
            opens = len(re.findall(r"localizedText\s*\(", raw))
            closes = raw.count(")")
            wrapped_depth = max(0, wrapped_depth + opens - (1 if (opens == 0 and wrapped_depth > 0 and closes > 0) else 0))
            if opens > 0:
                # rough: if line has opens but net parens unclosed, keep depth
                net = raw.count("(") - raw.count(")")
                if net > 0:
                    wrapped_depth = wrapped_depth + 0  # already counted via opens above
                elif opens > 0 and closes >= opens:
                    wrapped_depth = 0

    report = {
        "stats": {
            "exact_dict_entries": len(dictionary),
            "covered_by_resource": len(covered_by_res),
            "covered_by_dict": len(covered_by_dict),
            "uncovered_unique": len(uncovered),
            "unwrapped_unique": len(unwrapped),
            "pattern_suspects": len(pattern_suspects),
        },
        "uncovered": {k: v[:8] for k, v in sorted(uncovered.items(), key=lambda kv: -len(kv[1]))},
        "unwrapped": {k: v[:8] for k, v in sorted(unwrapped.items(), key=lambda kv: -len(kv[1]))},
        "pattern_suspects": sorted({t for _, _, t in pattern_suspects}),
    }
    out = os.path.join(os.path.dirname(__file__), "i18n_report.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    print(json.dumps(report["stats"], ensure_ascii=False))
    print("report ->", out)


if __name__ == "__main__":
    main()
