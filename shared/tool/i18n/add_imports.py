#!/usr/bin/env python3
"""Add the l10n import to every Dart file that uses `context.l10n` / `currentL10n`."""

import subprocess
import sys

IMPORT = "import 'package:diting_shared/app/l10n/l10n.dart';"


def add_import(source):
    if IMPORT in source:
        return source
    lines = source.split('\n')
    for index, line in enumerate(lines):
        if line.startswith('import '):
            lines.insert(index, IMPORT)
            return '\n'.join(lines)
    return IMPORT + '\n' + source


def main():
    out = subprocess.run(
        ['rg', '-l', r'context\.l10n|currentL10n', 'lib', 'test'],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    for name in out:
        path = name.replace('\\', '/')
        source = open(path, encoding='utf-8').read()
        patched = add_import(source)
        if patched != source:
            open(path, 'w', encoding='utf-8').write(patched)
            print(path)


if __name__ == '__main__':
    main()
