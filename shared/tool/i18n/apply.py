#!/usr/bin/env python3
"""Replace Chinese literals with `context.l10n.<key>` using a batch glossary.

Usage: python tool/i18n/apply.py batch.json lib/pages/foo.dart [...]

The batch file is the same one fed to `merge_arb.py`: `{key: ["中文", "English"]}`.
Every occurrence of the exact literal `'中文'` in the listed files becomes
`context.l10n.key`, and the ARB import is added when missing. Anything that
cannot be a plain `context.l10n` call (const contexts, functions without a
BuildContext, interpolated strings) is left alone for a manual pass; the
analyzer then points at it.
"""

import json
import sys
from pathlib import Path

IMPORT = "import 'package:diting_shared/app/l10n/l10n.dart';"


def add_import(source):
    if IMPORT in source:
        return source
    lines = source.split('\n')
    if lines and lines[0].startswith('///') or (lines and lines[0].startswith('//')):
        # Keep the library doc comment first, then `library;`, then imports.
        for index, line in enumerate(lines):
            if line.startswith('import '):
                lines.insert(index, IMPORT)
                return '\n'.join(lines)
    for index, line in enumerate(lines):
        if line.startswith('import '):
            lines.insert(index, IMPORT)
            return '\n'.join(lines)
    return IMPORT + '\n' + source


def main(batch_path, files, scope='context', imports=True):
    batch = json.loads(Path(batch_path).read_text(encoding='utf-8'))
    glossary = {}
    for key, value in batch.items():
        zh = value[0] if isinstance(value, list) else value['zh']
        if zh in glossary:
            sys.exit(f'{zh} maps to both {glossary[zh]} and {key}')
        glossary[zh] = key
    receiver = 'context.l10n' if scope == 'context' else 'currentL10n'
    for name in files:
        path = Path(name)
        source = path.read_text(encoding='utf-8')
        before = source
        hits = 0
        for zh, key in sorted(glossary.items(), key=lambda item: -len(item[0])):
            literal = "'" + zh + "'"
            if literal in source:
                hits += source.count(literal)
                source = source.replace(literal, f'{receiver}.{key}')
        if source != before:
            path.write_text(add_import(source) if imports else source, encoding='utf-8')
        print(f'{name}: {hits} replaced')


if __name__ == '__main__':
    args = sys.argv[1:]
    scope = 'context'
    imports = True
    while args and args[0].startswith('--'):
        flag = args[0]
        if flag.startswith('--l10n='):
            scope = flag.split('=', 1)[1]
        elif flag == '--no-import':
            imports = False
        else:
            sys.exit(f'unknown flag {flag}')
        args = args[1:]
    main(args[0], args[1:], scope, imports)
