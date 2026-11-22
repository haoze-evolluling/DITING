#!/usr/bin/env python3
"""Drop `const` from constructor calls that now take a `context.l10n` argument.

Usage: python tool/i18n/fix_const.py   (reads `flutter analyze` output on stdin)

The analyzer reports `Invalid constant value` / `non_constant_list_element` at the
argument; the `const` that has to go sits on the nearest enclosing call above it.
"""

import re
import sys
from collections import defaultdict

ERROR = re.compile(
    r'(?P<file>[^-\n]+\.dart):(?P<line>\d+):\d+ - '
    r'(invalid_constant|non_constant_list_element|const_with_non_const)'
)


def main():
    hits = defaultdict(set)
    for raw in sys.stdin:
        match = ERROR.search(raw)
        if match:
            hits[match.group('file')].add(int(match.group('line')))
    for name, lines in hits.items():
        path = name.strip().replace('\\', '/')
        source = open(path, encoding='utf-8').read().split('\n')
        for line in sorted(lines, reverse=True):
            for index in range(line - 1, max(line - 12, -1), -1):
                if 'const ' in source[index]:
                    source[index] = source[index].replace('const ', '', 1)
                    break
        open(path, 'w', encoding='utf-8').write('\n'.join(source))
        print(f'{path}: {len(lines)} const removed')


if __name__ == '__main__':
    main()
