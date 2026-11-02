"""Keep the l10n import on the library, never on its `part of` files."""

import os
import re
import subprocess

IMPORT = "import 'package:diting_shared/app/l10n/l10n.dart';"


def main():
    files = subprocess.run(
        ['rg', '-l', r'^part of ', 'lib'], capture_output=True, text=True
    ).stdout.split()
    parents = set()
    for name in files:
        path = name.replace(os.sep, '/')
        source = open(path, encoding='utf-8').read()
        match = re.search(r"^part of '([^']+)';", source, re.M)
        if not match:
            continue
        if IMPORT in source:
            source = source.replace(IMPORT + '\n', '', 1)
            open(path, 'w', encoding='utf-8').write(source)
        parents.add(
            os.path.normpath(os.path.join(os.path.dirname(path), match.group(1)))
        )
    for parent in parents:
        source = open(parent, encoding='utf-8').read()
        if IMPORT in source:
            continue
        lines = source.split('\n')
        for index, line in enumerate(lines):
            if line.startswith('import '):
                lines.insert(index, IMPORT)
                break
        open(parent, 'w', encoding='utf-8').write('\n'.join(lines))
        print('parent import:', parent)
    print(f'{len(files)} part files checked')


if __name__ == '__main__':
    main()
