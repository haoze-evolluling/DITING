"""Drop `unused_import` warnings for the l10n import (analyzer output on stdin)."""

import re
import sys

IMPORT = "import 'package:diting_shared/app/l10n/l10n.dart';"
LINE = re.compile(r'(?P<file>[^-\n]+\.dart):\d+:\d+ - unused_import')


def main():
    for raw in sys.stdin:
        if 'app/l10n/l10n.dart' not in raw:
            continue
        match = LINE.search(raw)
        if not match:
            continue
        path = match.group('file').strip().replace('\\', '/')
        source = open(path, encoding='utf-8').read()
        open(path, 'w', encoding='utf-8').write(source.replace(IMPORT + '\n', '', 1))
        print(path)


if __name__ == '__main__':
    main()
