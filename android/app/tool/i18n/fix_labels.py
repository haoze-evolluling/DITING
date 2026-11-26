#!/usr/bin/env python3
"""Pass `context.l10n` to enum text methods that now take an AppL10n.

Usage: flutter analyze lib | python tool/i18n/fix_labels.py

Only lines the analyzer flagged as a type mismatch are touched, and only the last
`.<name>` on the line without a call, so a plain String field elsewhere on the
same line keeps working.
"""

import re
import sys
from collections import defaultdict

ERROR = re.compile(
    r'(?P<file>[^-\n]+\.dart):(?P<line>\d+):\d+ - .*'
    r'(argument_type_not_assignable|return_of_invalid_type_from_closure|list_element_type_not_assignable)'
)
NAMES = re.compile(r'\.(label|title|summary|badge|description)\b(?!\s*\()')


def main():
    hits = defaultdict(set)
    for raw in sys.stdin:
        match = ERROR.search(raw)
        if match:
            hits[match.group('file').strip()].add(int(match.group('line')))
    for name, lines in hits.items():
        path = name.replace('\\', '/')
        source = open(path, encoding='utf-8').read().split('\n')
        for line in lines:
            index = line - 1
            matches = list(NAMES.finditer(source[index]))
            if not matches:
                continue
            last = matches[-1]
            source[index] = (
                source[index][: last.end()]
                + '(context.l10n)'
                + source[index][last.end() :]
            )
        open(path, 'w', encoding='utf-8').write('\n'.join(source))
        print(f'{path}: {len(lines)} labels')


if __name__ == '__main__':
    main()
